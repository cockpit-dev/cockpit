import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../development/cockpit_checkout_identity.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_runtime.dart';
import 'cockpit_cli_session_handles.dart';
import 'cockpit_dev_runtime.dart';

final class CockpitDevStartRequest {
  const CockpitDevStartRequest({
    this.sessionReference,
    this.entrypoint,
    this.platform,
    this.deviceId,
    this.flavor,
    this.launchConfiguration,
    this.launchTimeoutMilliseconds = 600000,
  });

  final String? sessionReference;
  final String? entrypoint;
  final String? platform;
  final String? deviceId;
  final String? flavor;
  final Map<String, Object?>? launchConfiguration;
  final int launchTimeoutMilliseconds;

  bool get hasExplicitSelection =>
      entrypoint != null ||
      platform != null ||
      deviceId != null ||
      flavor != null ||
      launchConfiguration != null;
}

final class CockpitDevStartService {
  CockpitDevStartService(this.runtime) : dev = CockpitDevRuntime(runtime);

  final CockpitCliRuntime runtime;
  final CockpitDevRuntime dev;

  Future<int> start(CockpitDevStartRequest request) async {
    final store = await runtime.sessionHandleStore();
    CockpitCheckoutIdentity? resolvedCheckout;
    CockpitCliSessionHandle? active;
    if (request.sessionReference != null) {
      active = await runtime.resolveDevelopmentSession(
        request.sessionReference,
      );
    } else if (!request.hasExplicitSelection) {
      runtime.progress('Resolving Flutter project...');
      resolvedCheckout = await runtime.checkoutIdentity();
      active = await store.activeForPath(
        checkoutIdentity: resolvedCheckout.value,
        path: await runtime.canonicalWorkingDirectory(),
      );
    }
    if (active != null && !request.hasExplicitSelection) {
      runtime.progress(
        active.lifecycle == 'stopped'
            ? 'Relaunching session ${active.handleId}...'
            : 'Reconnecting session ${active.handleId}...',
      );
      final resolution = active.lifecycle == 'stopped'
          ? await dev.relaunch(active)
          : await dev.reconcile(active, allowRelaunch: true);
      if (resolution.ready) {
        runtime.progress('Ready: session ${resolution.session.handleId}.');
        return dev.writeEnvelope(
          action: 'start',
          session: resolution.session,
          ok: true,
          state: resolution.state,
          changed: resolution.changed,
        );
      }
      return dev.writeUnavailable(action: 'start', resolution: resolution);
    }

    runtime.progress('Resolving checkout...');
    final checkout = resolvedCheckout ?? await runtime.checkoutIdentity();
    final launchRequest = active == null || request.sessionReference == null
        ? request
        : CockpitDevStartRequest(
            sessionReference: request.sessionReference,
            entrypoint: request.entrypoint ?? active.entrypoint,
            platform: request.platform ?? active.platform,
            deviceId: request.deviceId ?? active.deviceId,
            flavor: request.flavor ?? active.flavor,
            launchConfiguration: request.launchConfiguration,
            launchTimeoutMilliseconds: request.launchTimeoutMilliseconds,
          );
    runtime.progress('Preparing Flutter target...');
    final project = await _project(
      checkout,
      requestedEntrypoint: launchRequest.entrypoint,
    );
    final projectDirectory = project.path;
    final entrypoint = project.entrypoint;
    if (active != null &&
        (active.checkoutIdentity != checkout.value ||
            !p.equals(active.projectPath!, projectDirectory))) {
      throw const CockpitSupervisorClientException(
        code: 'sessionProjectMismatch',
        message:
            'The selected session belongs to a different Flutter project. '
            'Run inside that project or omit --session to start another app.',
      );
    }
    final launchConfiguration =
        await cockpitResolveDevFlutterLaunchConfiguration(
          launchRequest.launchConfiguration,
          sourceDirectory: runtime.workingDirectory,
          projectDirectory: projectDirectory,
        );
    runtime.progress('Starting Cockpit services...');
    final client = await runtime.developmentClient();
    final workspace = await _workspace(client, checkout, projectDirectory);
    final documents = await client.documents(
      workspace.workspaceId,
      kind: CockpitIndexedDocumentKind.source,
      relativePath: entrypoint,
    );
    if (documents.length != 1) {
      throw CockpitSupervisorClientException(
        code: 'entrypointNotIndexed',
        message:
            'Flutter entrypoint $entrypoint was not indexed uniquely after '
            'refresh.',
      );
    }

    runtime.progress('Discovering Flutter devices...');
    final device = await _device(client, launchRequest);
    var targets = await client.targets(workspace.workspaceId);
    var matches = targets
        .where(
          (target) => cockpitMatchesDevelopmentTarget(
            target,
            entrypoint: entrypoint,
            platform: device.platform,
            deviceId: device.id,
            flavor: launchRequest.flavor,
          ),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      throw const CockpitSupervisorClientException(
        code: 'developmentTargetAmbiguous',
        message:
            'Multiple matching Flutter development targets exist; remove the '
            'duplicate registrations.',
      );
    }
    if (matches.isEmpty) {
      final registered = await _invokeWorkspace(
        client,
        workspace.workspaceId,
        'target.register',
        <String, Object?>{
          'platform': device.platform,
          'deviceId': device.id,
          'targetKind': CockpitTargetKind.flutterApp.name,
          'environment': CockpitAutomationTargetEnvironment.development.name,
          'mode': CockpitAutomationTargetMode.development.name,
          'entrypointDocumentId': documents.single.documentId,
          if (launchRequest.flavor != null) 'flavor': launchRequest.flavor,
        },
      );
      if (!_succeeded(registered)) {
        return _writePreSessionFailure('start', registered);
      }
      targets = await client.targets(workspace.workspaceId);
      matches = targets
          .where(
            (target) => cockpitMatchesDevelopmentTarget(
              target,
              entrypoint: entrypoint,
              platform: device.platform,
              deviceId: device.id,
              flavor: launchRequest.flavor,
            ),
          )
          .toList(growable: false);
      if (matches.length != 1) {
        throw const CockpitSupervisorClientException(
          code: 'developmentTargetRegistrationFailed',
          message: 'Registered Flutter target could not be resolved uniquely.',
        );
      }
    }
    final target = matches.single;
    if (active != null && active.targetId != target.targetId) {
      throw const CockpitSupervisorClientException(
        code: 'sessionTargetMismatch',
        message:
            'The selected session uses a different Flutter launch target. '
            'Omit --session to start or select that target independently.',
      );
    }
    active ??= await store.developmentForTarget(
      checkoutIdentity: checkout.value,
      projectPath: projectDirectory,
      targetId: target.targetId,
    );
    if (active != null && active.lifecycle != 'stopped') {
      runtime.progress('Stopping session ${active.handleId} for relaunch...');
      final stopped = await dev.invoke(
        active,
        'session.development.stop',
        <String, Object?>{'sessionId': active.sessionId},
      );
      if (!_succeeded(stopped)) {
        return _writePreSessionFailure('start', stopped);
      }
      active = await runtime.updateDevelopmentSession(
        previous: active,
        workspaceId: active.workspaceId,
        sessionId: active.sessionId,
        targetId: active.targetId!,
        appId: active.appId!,
        lifecycle: 'stopped',
      );
    }
    runtime.progress(
      'Building and launching Flutter on ${device.id}; '
      'waiting for the Cockpit bridge...',
    );
    final launched = await _invokeWorkspace(
      client,
      workspace.workspaceId,
      'target.launch',
      <String, Object?>{
        'targetId': target.targetId,
        'mode': 'development',
        'launchTimeoutMs': runtime.operationTimeout.inMilliseconds,
        'launchConfiguration': ?launchConfiguration,
      },
    );
    if (!_succeeded(launched)) {
      return _writePreSessionFailure('start', launched);
    }
    runtime.progress('Binding development session...');
    final output = launched.output ?? const <String, Object?>{};
    final sessionId = output['sessionId'];
    final appId = output['appId'];
    final targetId = output['targetId'] ?? target.targetId;
    if (sessionId is! String || appId is! String || targetId is! String) {
      throw const CockpitSupervisorClientException(
        code: 'developmentLaunchReceiptInvalid',
        message: 'Flutter launch did not return app, target, and session IDs.',
      );
    }
    final recoverable = launchConfiguration == null;
    final handle = active == null
        ? await runtime.bindDevelopmentSession(
            checkout: checkout,
            projectPath: projectDirectory,
            workspaceId: workspace.workspaceId,
            sessionId: sessionId,
            targetId: targetId,
            appId: appId,
            entrypoint: entrypoint,
            platform: device.platform,
            deviceId: device.id,
            flavor: launchRequest.flavor,
            recoverable: recoverable,
            launchTimeoutMilliseconds: launchRequest.launchTimeoutMilliseconds,
            replaceLaunchIdentity: true,
          )
        : await runtime.updateDevelopmentSession(
            previous: active,
            workspaceId: workspace.workspaceId,
            sessionId: sessionId,
            targetId: targetId,
            appId: appId,
            entrypoint: entrypoint,
            platform: device.platform,
            deviceId: device.id,
            flavor: launchRequest.flavor,
            recoverable: recoverable,
            launchTimeoutMilliseconds: launchRequest.launchTimeoutMilliseconds,
            replaceLaunchIdentity: true,
          );
    runtime.progress('Ready: session ${handle.handleId}.');
    return dev.writeEnvelope(
      action: 'start',
      session: handle,
      ok: true,
      state: <String, Object?>{
        'lifecycle': 'ready',
        'platform': device.platform,
        'device': device.id,
        'projectPath': projectDirectory,
        'entrypoint': entrypoint,
        'recoverable': recoverable,
      },
      changed: active == null ? 'launched' : 'relaunched',
    );
  }

  Future<CockpitWorkspaceResource> _workspace(
    CockpitSupervisorApiClient client,
    CockpitCheckoutIdentity checkout,
    String projectPath,
  ) async {
    final existing = cockpitSelectDevWorkspace(
      await client.workspaces(),
      projectPath: projectPath,
    );
    if (existing != null) return existing;
    final roots = await client.roots();
    final rootMatches = roots
        .where(
          (item) =>
              item.state == CockpitRootState.active &&
              (p.equals(item.canonicalPath, checkout.canonicalRoot) ||
                  p.isWithin(item.canonicalPath, checkout.canonicalRoot)),
        )
        .toList();
    rootMatches.sort(
      (left, right) =>
          right.canonicalPath.length.compareTo(left.canonicalPath.length),
    );
    final root = rootMatches.isNotEmpty
        ? rootMatches.first
        : await client.registerRoot(
            CockpitRootRegistration(path: checkout.canonicalRoot),
          );
    return client.registerWorkspace(
      CockpitWorkspaceRegistration(rootId: root.rootId, path: projectPath),
    );
  }

  Future<({String path, String entrypoint})> _project(
    CockpitCheckoutIdentity checkout, {
    String? requestedEntrypoint,
  }) async {
    final absoluteEntrypoint = requestedEntrypoint == null
        ? await _defaultEntrypoint(checkout.canonicalRoot)
        : _absoluteEntrypoint(checkout.canonicalRoot, requestedEntrypoint);
    final projectPath = _flutterProjectDirectory(
      checkout.canonicalRoot,
      absoluteEntrypoint,
    );
    return (
      path: projectPath,
      entrypoint: p.posix.joinAll(
        p.split(p.relative(absoluteEntrypoint, from: projectPath)),
      ),
    );
  }

  Future<String> _defaultEntrypoint(String checkoutRoot) async {
    final project = await _nearestFlutterPackage(checkoutRoot);
    for (final candidate in const <String>['cockpit/main.dart', 'main.dart']) {
      final file = File(p.join(project, candidate));
      if (await file.exists()) {
        return p.normalize(await file.resolveSymbolicLinks());
      }
    }
    throw const CockpitSupervisorClientException(
      code: 'flutterBridgeShellMissing',
      message:
          'No Cockpit Flutter bridge shell was found. Integrate '
          'cockpit/main.dart first, or pass an intentional development '
          'entrypoint explicitly.',
    );
  }

  Future<String> _nearestFlutterPackage(String checkoutRoot) async {
    var current = p.normalize(
      await Directory(runtime.workingDirectory).resolveSymbolicLinks(),
    );
    if (!p.equals(current, checkoutRoot) &&
        !p.isWithin(checkoutRoot, current)) {
      throw const CockpitSupervisorClientException(
        code: 'checkoutPathMismatch',
        message: 'Current directory is outside its resolved checkout root.',
      );
    }
    while (true) {
      if (await File(p.join(current, 'pubspec.yaml')).exists()) return current;
      if (p.equals(current, checkoutRoot)) break;
      final parent = p.dirname(current);
      if (parent == current || !p.isWithin(checkoutRoot, parent)) break;
      current = parent;
    }
    throw const CockpitSupervisorClientException(
      code: 'flutterProjectNotFound',
      message: 'No Flutter pubspec.yaml contains the current directory.',
    );
  }

  String _flutterProjectDirectory(
    String checkoutRoot,
    String absoluteEntrypoint,
  ) {
    var directory = p.dirname(absoluteEntrypoint);
    while (p.equals(directory, checkoutRoot) ||
        p.isWithin(checkoutRoot, directory)) {
      final manifest = p.join(directory, 'pubspec.yaml');
      if (FileSystemEntity.typeSync(manifest, followLinks: false) ==
          FileSystemEntityType.file) {
        final canonicalManifest = p.normalize(
          File(manifest).resolveSymbolicLinksSync(),
        );
        if (p.equals(canonicalManifest, manifest)) return directory;
      }
      if (p.equals(directory, checkoutRoot)) break;
      directory = p.dirname(directory);
    }
    throw const CockpitSupervisorClientException(
      code: 'flutterProjectNotFound',
      message: 'No Flutter pubspec.yaml contains the selected entrypoint.',
    );
  }

  String _absoluteEntrypoint(String checkoutRoot, String requested) {
    final unresolved = p.normalize(
      p.isAbsolute(requested)
          ? requested
          : p.join(runtime.workingDirectory, requested),
    );
    final file = File(unresolved);
    if (!file.existsSync()) {
      throw FileSystemException(
        'Flutter entrypoint must be an existing file inside the checkout.',
        unresolved,
      );
    }
    final absolute = p.normalize(file.resolveSymbolicLinksSync());
    if (!p.isWithin(checkoutRoot, absolute)) {
      throw FileSystemException(
        'Flutter entrypoint must resolve inside the checkout.',
        absolute,
      );
    }
    return absolute;
  }

  Future<({String id, String platform})> _device(
    CockpitSupervisorApiClient client,
    CockpitDevStartRequest request,
  ) async {
    final remaining = runtime.operationTimeout;
    const maximumDiscoveryTimeout = Duration(minutes: 2);
    final discoveryTimeout = remaining < maximumDiscoveryTimeout
        ? remaining
        : maximumDiscoveryTimeout;
    final discovered = await _invokeSupervisor(
      client,
      'target.discover',
      <String, Object?>{'timeoutMs': discoveryTimeout.inMilliseconds},
    );
    final rawTargets = discovered.output?['targets'];
    if (rawTargets is! List) {
      throw const CockpitSupervisorClientException(
        code: 'deviceDiscoveryInvalid',
        message: 'Flutter device discovery returned no target list.',
      );
    }
    final candidates = <({String id, String platform})>[];
    for (final value in rawTargets.whereType<Map<Object?, Object?>>()) {
      final id = value['id'];
      final platform = value['platform'];
      if (id is String && platform is String) {
        if (request.deviceId != null && id != request.deviceId) continue;
        if (request.platform != null && platform != request.platform) continue;
        candidates.add((id: id, platform: platform));
      }
    }
    if (request.deviceId == null && request.platform == null) {
      final hostPlatform = Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
          ? 'windows'
          : Platform.isLinux
          ? 'linux'
          : null;
      final host = candidates
          .where((item) => item.platform == hostPlatform)
          .toList(growable: false);
      if (host.length == 1) return host.single;
      final exact = host.where((item) => item.id == hostPlatform).toList();
      if (exact.length == 1) return exact.single;
    }
    if (candidates.length != 1) {
      final commands = candidates
          .take(8)
          .map(
            (item) =>
                'cockpit dev start --platform ${item.platform} '
                '--device ${item.id}',
          )
          .join('; ');
      throw CockpitSupervisorClientException(
        code: candidates.isEmpty ? 'deviceNotFound' : 'deviceAmbiguous',
        message: candidates.isEmpty
            ? 'No matching Flutter device is available.'
            : 'Choose one Flutter device: $commands',
      );
    }
    return candidates.single;
  }

  Future<CockpitOperationResult> _invokeWorkspace(
    CockpitSupervisorApiClient client,
    String workspaceId,
    String kind,
    Map<String, Object?> input,
  ) async {
    final descriptors = await client.operations(workspaceId: workspaceId);
    final descriptor = descriptors.singleWhere((item) => item.kind == kind);
    return client.executeAdvertisedOperation(
      CockpitOperationInvocation(
        kind: kind,
        workspaceId: workspaceId,
        input: input,
        idempotencyKey: runtime.operationIdempotencyKey(descriptor, null),
        deadline: runtime.operationDeadline(descriptor),
      ),
      descriptor: descriptor,
    );
  }

  Future<CockpitOperationResult> _invokeSupervisor(
    CockpitSupervisorApiClient client,
    String kind,
    Map<String, Object?> input,
  ) async {
    final descriptor = (await client.operations()).singleWhere(
      (item) => item.kind == kind,
    );
    return client.executeAdvertisedOperation(
      CockpitOperationInvocation(
        kind: kind,
        input: input,
        idempotencyKey: runtime.operationIdempotencyKey(descriptor, null),
        deadline: runtime.operationDeadline(descriptor),
      ),
      descriptor: descriptor,
    );
  }

  Future<int> _writePreSessionFailure(
    String action,
    CockpitOperationResult result,
  ) async {
    await runtime.success(<String, Object?>{
      'ok': false,
      'action': action,
      'state': result.output,
      'changed': 'none',
      'errors': <Object?>[
        result.failure?.toJson() ??
            <String, Object?>{
              'code': 'productOutcomeFailed',
              'operation': result.kind,
            },
      ],
      'next': 'cockpit dev start',
    });
    return cockpitDataExitCode;
  }
}

CockpitWorkspaceResource? cockpitSelectDevWorkspace(
  Iterable<CockpitWorkspaceResource> workspaces, {
  required String projectPath,
}) {
  final matches = workspaces
      .where(
        (item) =>
            item.state == CockpitWorkspaceState.active &&
            p.equals(item.canonicalPath, projectPath),
      )
      .toList(growable: false);
  if (matches.length > 1) {
    throw const CockpitSupervisorClientException(
      code: 'workspaceAmbiguous',
      message: 'Flutter project has multiple active workspace registrations.',
    );
  }
  return matches.firstOrNull;
}

bool cockpitMatchesDevelopmentTarget(
  CockpitAutomationTargetResource target, {
  required String entrypoint,
  required String platform,
  required String deviceId,
  required String? flavor,
}) {
  return target.targetKind == CockpitTargetKind.flutterApp &&
      target.mode == CockpitAutomationTargetMode.development &&
      target.entrypoint == entrypoint &&
      target.platform == platform &&
      target.deviceId == deviceId &&
      target.flavor == flavor &&
      (target.environment == CockpitAutomationTargetEnvironment.development ||
          target.environment == CockpitAutomationTargetEnvironment.test);
}

bool _succeeded(CockpitOperationResult result) =>
    result.lifecycle == CockpitOperationLifecycle.completed &&
    result.outcome == CockpitOperationOutcome.succeeded;

Future<Map<String, Object?>?> cockpitResolveDevFlutterLaunchConfiguration(
  Map<String, Object?>? configuration, {
  required String sourceDirectory,
  required String projectDirectory,
}) async {
  if (configuration == null) return null;
  final rawFiles = configuration['dartDefineFromFiles'];
  if (rawFiles == null) return configuration;
  if (rawFiles is! List<Object?> || rawFiles.any((value) => value is! String)) {
    throw const FormatException(
      'Flutter dartDefineFromFiles must contain only file paths.',
    );
  }

  final canonicalProject = p.normalize(
    await Directory(projectDirectory).resolveSymbolicLinks(),
  );
  final canonicalSource = p.normalize(
    await Directory(sourceDirectory).resolveSymbolicLinks(),
  );
  final resolvedFiles = <String>[];
  for (final rawFile in rawFiles.cast<String>()) {
    final requestedPath = p.normalize(
      p.isAbsolute(rawFile) ? rawFile : p.join(canonicalSource, rawFile),
    );
    if (await FileSystemEntity.type(requestedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException(
        'Flutter --dart-define-from-file is not an existing regular file: '
        '$rawFile',
      );
    }
    final canonicalFile = p.normalize(
      await File(requestedPath).resolveSymbolicLinks(),
    );
    if (!p.isWithin(canonicalProject, canonicalFile)) {
      throw FormatException(
        'Flutter --dart-define-from-file must resolve inside the selected '
        'Flutter project: $rawFile',
      );
    }
    resolvedFiles.add(
      p.posix.joinAll(
        p.split(p.relative(canonicalFile, from: canonicalProject)),
      ),
    );
  }
  return <String, Object?>{
    ...configuration,
    'dartDefineFromFiles': resolvedFiles,
  };
}
