import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../development/cockpit_checkout_identity.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_runtime.dart';
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
    final checkout = await runtime.checkoutIdentity();
    final store = await runtime.sessionHandleStore();
    final active = request.sessionReference == null
        ? await store.activeForCheckout(checkout.value)
        : await runtime.resolveDevelopmentSession(request.sessionReference);
    if (active != null && !request.hasExplicitSelection) {
      final resolution = active.lifecycle == 'stopped'
          ? await dev.relaunch(active)
          : await dev.reconcile(active, allowRelaunch: true);
      if (resolution.ready) {
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

    final client = await runtime.developmentClient();
    final workspace = await _workspace(client, checkout);
    final entrypoint = await _entrypoint(workspace, request.entrypoint);
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

    final device = await _device(client, request);
    var targets = await client.targets(workspace.workspaceId);
    var matches = targets
        .where(
          (target) =>
              target.targetKind == CockpitTargetKind.flutterApp &&
              target.mode == CockpitAutomationTargetMode.development &&
              target.entrypoint == entrypoint &&
              target.platform == device.platform &&
              target.deviceId == device.id &&
              target.flavor == request.flavor &&
              (target.environment ==
                      CockpitAutomationTargetEnvironment.development ||
                  target.environment ==
                      CockpitAutomationTargetEnvironment.test),
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
          if (request.flavor != null) 'flavor': request.flavor,
        },
      );
      if (!_succeeded(registered)) {
        return _writePreSessionFailure('start', registered);
      }
      targets = await client.targets(workspace.workspaceId);
      matches = targets
          .where(
            (target) =>
                target.targetKind == CockpitTargetKind.flutterApp &&
                target.entrypoint == entrypoint &&
                target.platform == device.platform &&
                target.deviceId == device.id &&
                target.flavor == request.flavor,
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
    final launched = await _invokeWorkspace(
      client,
      workspace.workspaceId,
      'target.launch',
      <String, Object?>{
        'targetId': target.targetId,
        'mode': 'development',
        'launchTimeoutMs': runtime.operationTimeout.inMilliseconds,
        if (request.launchConfiguration != null)
          'launchConfiguration': request.launchConfiguration,
      },
    );
    if (!_succeeded(launched)) {
      return _writePreSessionFailure('start', launched);
    }
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
    final recoverable = request.launchConfiguration == null;
    final handle = await runtime.bindDevelopmentSession(
      checkout: checkout,
      workspaceId: workspace.workspaceId,
      sessionId: sessionId,
      targetId: targetId,
      appId: appId,
      entrypoint: entrypoint,
      platform: device.platform,
      deviceId: device.id,
      flavor: request.flavor,
      recoverable: recoverable,
      launchTimeoutMilliseconds: request.launchTimeoutMilliseconds,
      replaceLaunchIdentity: true,
    );
    return dev.writeEnvelope(
      action: 'start',
      session: handle,
      ok: true,
      state: <String, Object?>{
        'lifecycle': 'ready',
        'platform': device.platform,
        'device': device.id,
        'entrypoint': entrypoint,
        'recoverable': recoverable,
      },
      changed: active == null ? 'launched' : 'relaunched',
    );
  }

  Future<CockpitWorkspaceResource> _workspace(
    CockpitSupervisorApiClient client,
    CockpitCheckoutIdentity checkout,
  ) async {
    final workspaces = await client.workspaces();
    final exact = workspaces
        .where(
          (item) =>
              item.state == CockpitWorkspaceState.active &&
              p.equals(item.canonicalPath, checkout.canonicalRoot),
        )
        .toList(growable: false);
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) {
      throw const CockpitSupervisorClientException(
        code: 'workspaceAmbiguous',
        message: 'Checkout has multiple active workspace registrations.',
      );
    }
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
      CockpitWorkspaceRegistration(
        rootId: root.rootId,
        path: checkout.canonicalRoot,
      ),
    );
  }

  Future<String> _entrypoint(
    CockpitWorkspaceResource workspace,
    String? requested,
  ) async {
    if (requested != null) {
      return _workspaceRelativeFile(workspace.canonicalPath, requested);
    }
    final package = await _nearestFlutterPackage(workspace.canonicalPath);
    for (final candidate in const <String>[
      'cockpit/main.dart',
      'lib/main.dart',
    ]) {
      final file = File(p.join(package, candidate));
      if (await file.exists()) {
        return p.posix.joinAll(
          p.split(p.relative(file.path, from: workspace.canonicalPath)),
        );
      }
    }
    throw const CockpitSupervisorClientException(
      code: 'entrypointNotFound',
      message:
          'No unique cockpit/main.dart or lib/main.dart entrypoint was found; '
          'pass one to `cockpit dev start <entrypoint>`.',
    );
  }

  Future<String> _nearestFlutterPackage(String workspaceRoot) async {
    var current = p.normalize(
      await Directory(runtime.workingDirectory).resolveSymbolicLinks(),
    );
    if (!p.equals(current, workspaceRoot) &&
        !p.isWithin(workspaceRoot, current)) {
      throw const CockpitSupervisorClientException(
        code: 'checkoutPathMismatch',
        message: 'Current directory is outside its resolved checkout root.',
      );
    }
    while (true) {
      if (await File(p.join(current, 'pubspec.yaml')).exists()) return current;
      if (p.equals(current, workspaceRoot)) break;
      final parent = p.dirname(current);
      if (parent == current || !p.isWithin(workspaceRoot, parent)) break;
      current = parent;
    }
    return workspaceRoot;
  }

  String _workspaceRelativeFile(String workspaceRoot, String requested) {
    final unresolved = p.normalize(
      p.isAbsolute(requested)
          ? requested
          : p.join(runtime.workingDirectory, requested),
    );
    final file = File(unresolved);
    if (!file.existsSync()) {
      throw FileSystemException(
        'Flutter entrypoint must be an existing file inside the workspace.',
        unresolved,
      );
    }
    final absolute = p.normalize(file.resolveSymbolicLinksSync());
    if (!p.isWithin(workspaceRoot, absolute)) {
      throw FileSystemException(
        'Flutter entrypoint must resolve inside the workspace.',
        absolute,
      );
    }
    return p.posix.joinAll(p.split(p.relative(absolute, from: workspaceRoot)));
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

bool _succeeded(CockpitOperationResult result) =>
    result.lifecycle == CockpitOperationLifecycle.completed &&
    result.outcome == CockpitOperationOutcome.succeeded;
