import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef CockpitDemoAcceptanceProgress =
    void Function(Map<String, Object?> event);

final class CockpitDemoAcceptanceRequest {
  CockpitDemoAcceptanceRequest({
    required this.projectDirectory,
    required this.platform,
    required this.entrypoint,
    required this.suitePath,
    required this.outputRoot,
    required this.discoveryTimeout,
    required this.launchTimeout,
    required this.runTimeout,
    this.rootDirectory,
    this.deviceId,
    this.stopDaemon = false,
  }) {
    if (!const <String>{
      'android',
      'ios',
      'linux',
      'macos',
      'web',
      'windows',
    }.contains(platform)) {
      throw FormatException('Unsupported acceptance platform: $platform.');
    }
    if (discoveryTimeout <= Duration.zero ||
        launchTimeout <= Duration.zero ||
        runTimeout <= Duration.zero) {
      throw const FormatException('Acceptance timeouts must be positive.');
    }
    _requireRelativePath(entrypoint, 'entrypoint');
    _requireRelativePath(suitePath, 'suitePath');
  }

  final String projectDirectory;
  final String? rootDirectory;
  final String platform;
  final String? deviceId;
  final String entrypoint;
  final String suitePath;
  final String outputRoot;
  final Duration discoveryTimeout;
  final Duration launchTimeout;
  final Duration runTimeout;
  final bool stopDaemon;
}

final class CockpitDemoAcceptanceResult {
  const CockpitDemoAcceptanceResult({
    required this.success,
    required this.stage,
    required this.platform,
    required this.deviceId,
    required this.outputDirectory,
    required this.eventCount,
    required this.artifactCount,
    required this.cleanupFailures,
    this.rootId,
    this.workspaceId,
    this.targetId,
    this.runId,
    this.outcome,
    this.stability,
    this.counts,
    this.failure,
  });

  final bool success;
  final String stage;
  final String platform;
  final String? deviceId;
  final String outputDirectory;
  final String? rootId;
  final String? workspaceId;
  final String? targetId;
  final String? runId;
  final String? outcome;
  final String? stability;
  final int eventCount;
  final int artifactCount;
  final Map<String, Object?>? counts;
  final Map<String, Object?>? failure;
  final List<Map<String, Object?>> cleanupFailures;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 'cockpit.demo.acceptance/v2',
    'success': success,
    'stage': stage,
    'platform': platform,
    if (deviceId != null) 'deviceId': deviceId,
    'outputDirectory': outputDirectory,
    if (rootId != null) 'rootId': rootId,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (targetId != null) 'targetId': targetId,
    if (runId != null) 'runId': runId,
    if (outcome != null) 'outcome': outcome,
    if (stability != null) 'stability': stability,
    'eventCount': eventCount,
    'artifactCount': artifactCount,
    if (counts != null) 'counts': counts,
    if (failure != null) 'failure': failure,
    'cleanupFailures': cleanupFailures,
  };
}

final class CockpitDemoAcceptanceRunner {
  const CockpitDemoAcceptanceRunner({this.progress});

  final CockpitDemoAcceptanceProgress? progress;

  Future<CockpitDemoAcceptanceResult> run(
    CockpitDemoAcceptanceRequest request,
  ) async {
    final projectDirectory = await _canonicalDirectory(
      request.projectDirectory,
    );
    final requestedRoot = request.rootDirectory == null
        ? projectDirectory
        : await _canonicalDirectory(request.rootDirectory!);
    if (!_contains(requestedRoot, projectDirectory)) {
      throw const FormatException('The project is outside the requested root.');
    }
    await _workspaceFile(projectDirectory, request.entrypoint);
    final suiteFile = await _workspaceFile(projectDirectory, request.suitePath);
    final invocationId = _invocationId(request.platform);
    final outputRoot = p.normalize(
      p.isAbsolute(request.outputRoot)
          ? request.outputRoot
          : p.join(projectDirectory, request.outputRoot),
    );
    final outputDirectory = p.join(outputRoot, invocationId);
    await Directory(outputDirectory).create(recursive: true);

    CockpitSupervisorApiClient? api;
    CockpitRootResource? root;
    CockpitWorkspaceResource? workspace;
    CockpitAutomationTargetResource? target;
    CockpitRunResource? run;
    CockpitTestSuiteReport? report;
    String? deviceId;
    String? appId;
    String? runId;
    IOSink? eventSink;
    var launched = false;
    var primaryPassed = false;
    var eventCount = 0;
    var stage = 'bootstrap';
    Map<String, Object?>? failure;
    final artifacts = <CockpitArtifactResource>[];
    final downloadedArtifacts = <Map<String, Object?>>[];
    final cleanupFailures = <Map<String, Object?>>[];

    void advance(String next, String message) {
      stage = next;
      progress?.call(<String, Object?>{
        'stage': next,
        'message': message,
        'platform': request.platform,
        'runId': ?runId,
      });
    }

    try {
      advance('bootstrap', 'Connecting to the Cockpit Supervisor.');
      api = await createCockpitSupervisorApiClient(
        requiredFeatures: const <String>[
          'automationTargets',
          'digestCheckedArtifacts',
          'durableRunEvents',
          'suiteRuns',
        ],
      );
      await api.server();

      advance('workspace', 'Resolving root and workspace identity.');
      root = await _resolveRoot(api, projectDirectory, requestedRoot);
      workspace = await _resolveWorkspace(api, root.rootId, projectDirectory);

      advance('documents', 'Indexing and validating the acceptance suite.');
      final documents = await api.documents(workspace.workspaceId);
      final entrypointDocument = _requireDocument(
        documents,
        request.entrypoint,
        CockpitIndexedDocumentKind.source,
      );
      final suiteDocument = _requireDocument(
        documents,
        request.suitePath,
        CockpitIndexedDocumentKind.suite,
      );
      final validation = await api.validateCaseDocument(
        workspace.workspaceId,
        CockpitDocumentValidationRequest(
          format: _documentFormat(request.suitePath),
          sourceText: await suiteFile.readAsString(),
          relativePath: _protocolPath(request.suitePath),
        ),
      );
      if (!validation.valid ||
          validation.document is! CockpitTestSuite ||
          validation.sourceSha256 != suiteDocument.sha256 ||
          validation.document!.id != suiteDocument.authoredId) {
        throw FormatException(
          'Acceptance suite validation failed: '
          '${validation.diagnostics.map((item) => item.message).join('; ')}',
        );
      }

      advance('target', 'Discovering and registering the Flutter target.');
      deviceId = await _resolveDevice(api, request);
      final launchMode = cockpitDemoLaunchModeForPlatform(request.platform);
      target = await _resolveTarget(
        api: api,
        workspaceId: workspace.workspaceId,
        platform: request.platform,
        deviceId: deviceId,
        mode: launchMode,
        entrypointDocument: entrypointDocument,
      );

      advance('launch', 'Launching the target in $launchMode mode.');
      final launch = await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'target.launch',
          workspaceId: workspace.workspaceId,
          idempotencyKey: CockpitIdempotencyKey('$invocationId-launch'),
          deadline: DateTime.now().toUtc().add(
            request.launchTimeout + const Duration(seconds: 30),
          ),
          input: <String, Object?>{
            'targetId': target.targetId,
            'mode': launchMode,
            'launchTimeoutMs': request.launchTimeout.inMilliseconds,
          },
        ),
      );
      launched = true;
      appId = launch.output?['appId'] as String?;

      advance('run', 'Submitting the indexed regression suite.');
      final accepted = await api.submitRun(
        CockpitRunSubmission(
          workspaceId: workspace.workspaceId,
          targetId: target.targetId,
          source: CockpitIndexedSuiteSource(
            reference: CockpitIndexedSuiteReference(
              documentId: suiteDocument.documentId,
              suiteId: suiteDocument.authoredId!,
              documentSha256: suiteDocument.sha256,
            ),
          ),
          idempotencyKey: CockpitIdempotencyKey('$invocationId-run'),
          requiredFeatures: const <String>[
            'digestCheckedArtifacts',
            'durableRunEvents',
            'suiteRuns',
          ],
        ),
      );
      runId = accepted.runId;
      eventSink = File(p.join(outputDirectory, 'events.jsonl')).openWrite();
      eventCount = await _consumeEvents(
        api: api,
        runId: runId,
        deadline: DateTime.now().toUtc().add(request.runTimeout),
        sink: eventSink,
        progress: progress,
      );
      await eventSink.flush();
      await eventSink.close();
      eventSink = null;

      advance('report', 'Reading the terminal run and canonical report.');
      run = await api.run(runId);
      report = await api.report(runId);
      await _writeJson(File(p.join(outputDirectory, 'run.json')), run.toJson());
      await _writeJson(
        File(p.join(outputDirectory, 'report.json')),
        report.toJson(),
      );

      advance('artifacts', 'Downloading and verifying all run artifacts.');
      artifacts.addAll(await api.artifacts(runId));
      for (final artifact in artifacts) {
        final destination = _artifactDestination(outputDirectory, artifact);
        final receipt = await api.downloadArtifactToFile(
          artifact: artifact,
          destination: destination,
        );
        downloadedArtifacts.add(<String, Object?>{
          ...artifact.toJson(),
          'localPath': p.relative(receipt.file.path, from: outputDirectory),
        });
      }
      await _writeJson(
        File(p.join(outputDirectory, 'artifacts.json')),
        <String, Object?>{'items': downloadedArtifacts},
      );
      primaryPassed =
          run.outcome == CockpitRunOutcome.passed &&
          report.outcome == CockpitRunOutcome.passed &&
          report.complete;
      if (!primaryPassed) {
        failure =
            run.failure?.toJson() ??
            report.failure?.toJson() ??
            <String, Object?>{
              'code': 'acceptanceFailed',
              'message': 'The regression suite did not pass.',
            };
      }
      advance('completed', 'Acceptance execution reached terminal state.');
    } on Object catch (error) {
      failure = _failure(error, stage);
      progress?.call(<String, Object?>{
        'stage': 'failed',
        'failedStage': stage,
        'message': failure['message'],
        'runId': ?runId,
      });
    } finally {
      await _closeEventSink(eventSink, cleanupFailures);
      if (api != null && runId != null && failure != null) {
        await _cancelActiveRun(api, runId, invocationId, cleanupFailures);
      }
      if (api != null && workspace != null && target != null && launched) {
        await _stopTargetApp(
          api: api,
          workspaceId: workspace.workspaceId,
          targetId: target.targetId,
          appId: appId,
          idempotencyKey: '$invocationId-stop',
          failures: cleanupFailures,
        );
      }
      if (api != null && request.stopDaemon) {
        try {
          await api.lifecycle.stop(mode: CockpitDaemonShutdownMode.drain);
        } on Object catch (error) {
          cleanupFailures.add(_failure(error, 'daemonStop'));
        }
      }
    }

    final result = CockpitDemoAcceptanceResult(
      success: primaryPassed && failure == null && cleanupFailures.isEmpty,
      stage: stage,
      platform: request.platform,
      deviceId: deviceId,
      outputDirectory: outputDirectory,
      rootId: root?.rootId,
      workspaceId: workspace?.workspaceId,
      targetId: target?.targetId,
      runId: runId,
      outcome: run?.outcome?.name,
      stability: run?.stability?.name,
      eventCount: eventCount,
      artifactCount: artifacts.length,
      counts: report?.counts.toJson(),
      failure: failure,
      cleanupFailures: List<Map<String, Object?>>.unmodifiable(cleanupFailures),
    );
    await _writeJson(
      File(p.join(outputDirectory, 'summary.json')),
      <String, Object?>{
        ...result.toJson(),
        if (run != null) 'run': run.toJson(),
        if (report != null) 'report': report.toJson(),
        'artifacts': downloadedArtifacts,
      },
    );
    return result;
  }
}

void _requireRelativePath(String value, String name) {
  final normalized = p.normalize(value);
  if (value.trim().isEmpty ||
      p.isAbsolute(value) ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.startsWith('..${p.separator}')) {
    throw FormatException('$name must be a confined relative path.');
  }
}

Future<String> _canonicalDirectory(String path) async {
  final normalized = p.normalize(p.absolute(path));
  if (await FileSystemEntity.type(normalized, followLinks: true) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('Directory does not exist.', normalized);
  }
  return p.normalize(await Directory(normalized).resolveSymbolicLinks());
}

Future<File> _workspaceFile(String workspace, String relativePath) async {
  _requireRelativePath(relativePath, 'workspace file');
  final candidate = p.normalize(p.join(workspace, relativePath));
  if (!p.isWithin(workspace, candidate) ||
      await FileSystemEntity.type(candidate, followLinks: false) !=
          FileSystemEntityType.file) {
    throw FileSystemException(
      'Workspace file is missing or is not a regular file.',
      candidate,
    );
  }
  final canonical = p.normalize(await File(candidate).resolveSymbolicLinks());
  if (!p.equals(candidate, canonical) || !p.isWithin(workspace, canonical)) {
    throw FileSystemException('Workspace file must not be a link.', candidate);
  }
  return File(canonical);
}

bool _contains(String root, String candidate) =>
    p.equals(root, candidate) || p.isWithin(root, candidate);

String _protocolPath(String value) => p.normalize(value).replaceAll('\\', '/');

String cockpitDemoLaunchModeForPlatform(String platform) =>
    platform == 'web' ? 'development' : 'automation';

CockpitDocumentFormat _documentFormat(String path) =>
    p.extension(path).toLowerCase() == '.json'
    ? CockpitDocumentFormat.json
    : CockpitDocumentFormat.yaml;

Future<CockpitRootResource> _resolveRoot(
  CockpitSupervisorApiClient api,
  String projectDirectory,
  String requestedRoot,
) async {
  final containing =
      (await api.roots())
          .where(
            (root) =>
                root.state == CockpitRootState.active &&
                _contains(root.canonicalPath, projectDirectory),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              right.canonicalPath.length.compareTo(left.canonicalPath.length),
        );
  if (containing.isNotEmpty) return containing.first;
  return api.registerRoot(CockpitRootRegistration(path: requestedRoot));
}

Future<CockpitWorkspaceResource> _resolveWorkspace(
  CockpitSupervisorApiClient api,
  String rootId,
  String projectDirectory,
) async {
  final matches = (await api.workspaces())
      .where(
        (workspace) =>
            workspace.state == CockpitWorkspaceState.active &&
            p.equals(workspace.canonicalPath, projectDirectory),
      )
      .toList(growable: false);
  if (matches.length > 1) {
    throw const FormatException(
      'Multiple active workspaces resolve to the project directory.',
    );
  }
  if (matches.isNotEmpty) return matches.single;
  return api.registerWorkspace(
    CockpitWorkspaceRegistration(rootId: rootId, path: projectDirectory),
  );
}

CockpitDocumentResource _requireDocument(
  List<CockpitDocumentResource> documents,
  String relativePath,
  CockpitIndexedDocumentKind kind,
) {
  final expectedPath = _protocolPath(relativePath);
  final matches = documents
      .where(
        (document) =>
            _protocolPath(document.relativePath) == expectedPath &&
            document.kind == kind,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw FormatException(
      'Expected one indexed ${kind.name} document at $expectedPath; '
      'found ${matches.length}.',
    );
  }
  return matches.single;
}

Future<String> _resolveDevice(
  CockpitSupervisorApiClient api,
  CockpitDemoAcceptanceRequest request,
) async {
  final discovery = await _operation(
    api,
    CockpitOperationInvocation(
      kind: 'target.discover',
      input: <String, Object?>{
        'timeoutMs': request.discoveryTimeout.inMilliseconds,
      },
    ),
  );
  final rawTargets = discovery.output?['targets'];
  if (rawTargets is! List<Object?>) {
    throw const FormatException('Target discovery returned no target list.');
  }
  final candidates = <Map<String, Object?>>[
    for (final value in rawTargets)
      if (value is Map<Object?, Object?> &&
          value.keys.every((key) => key is String))
        Map<String, Object?>.from(value),
  ].where((value) => value['platform'] == request.platform).toList();
  final requested = request.deviceId?.trim();
  if (requested != null && requested.isNotEmpty) {
    final matches = candidates.where((value) => value['id'] == requested);
    if (matches.length != 1) {
      throw FormatException(
        'Device $requested is not an available ${request.platform} target.',
      );
    }
    return requested;
  }
  if (candidates.length == 1) return candidates.single['id']! as String;
  final stable = candidates
      .where((value) => value['ephemeral'] == false)
      .toList(growable: false);
  if (stable.length == 1) return stable.single['id']! as String;
  if (candidates.isEmpty) {
    throw FormatException(
      'No connected Flutter target is available for ${request.platform}.',
    );
  }
  throw FormatException(
    'Multiple ${request.platform} targets are available; pass --device-id.',
  );
}

Future<CockpitAutomationTargetResource> _resolveTarget({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String platform,
  required String deviceId,
  required String mode,
  required CockpitDocumentResource entrypointDocument,
}) async {
  final targetMode = CockpitAutomationTargetMode.values.byName(mode);
  final matches = (await api.targets(workspaceId))
      .where(
        (target) =>
            target.platform == platform &&
            target.deviceId == deviceId &&
            target.targetKind == CockpitTargetKind.flutterApp &&
            target.mode == targetMode &&
            target.environment == CockpitAutomationTargetEnvironment.test &&
            target.entrypoint == entrypointDocument.relativePath &&
            target.entrypointSha256 == entrypointDocument.sha256 &&
            target.flavor == null &&
            target.appId == null,
      )
      .toList(growable: false);
  if (matches.isNotEmpty) return matches.last;

  final identity = jsonEncode(<String, Object?>{
    'workspaceId': workspaceId,
    'platform': platform,
    'deviceId': deviceId,
    'entrypoint': entrypointDocument.relativePath,
    'sha256': entrypointDocument.sha256,
    'mode': mode,
    'environment': 'test',
  });
  final digest = sha256.convert(utf8.encode(identity)).toString();
  final registration = await _operation(
    api,
    CockpitOperationInvocation(
      kind: 'target.register',
      workspaceId: workspaceId,
      idempotencyKey: CockpitIdempotencyKey(
        'demo-target-${digest.substring(0, 32)}',
      ),
      input: <String, Object?>{
        'platform': platform,
        'deviceId': deviceId,
        'entrypointDocumentId': entrypointDocument.documentId,
        'targetKind': 'flutterApp',
        'mode': mode,
        'environment': 'test',
      },
    ),
  );
  final targetId = registration.output?['targetId'];
  if (targetId is! String) {
    throw const FormatException('Target registration returned no target id.');
  }
  return api.target(workspaceId, targetId);
}

Future<CockpitOperationResult> _operation(
  CockpitSupervisorApiClient api,
  CockpitOperationInvocation invocation,
) async {
  final result = await api.executeOperation(invocation);
  if (result.lifecycle != CockpitOperationLifecycle.completed ||
      result.outcome != CockpitOperationOutcome.succeeded) {
    throw CockpitSupervisorClientException(
      code: result.failure?.primary.code ?? 'operationFailed',
      message:
          result.failure?.primary.message ??
          'Operation ${invocation.kind} failed.',
    );
  }
  return result;
}

Future<int> _consumeEvents({
  required CockpitSupervisorApiClient api,
  required String runId,
  required DateTime deadline,
  required IOSink sink,
  required CockpitDemoAcceptanceProgress? progress,
}) async {
  var afterSequence = 0;
  var eventCount = 0;
  String? lastEventId;
  while (DateTime.now().toUtc().isBefore(deadline)) {
    var disconnected = false;
    final remaining = deadline.difference(DateTime.now().toUtc());
    try {
      await for (final item
          in api
              .events(
                runId,
                afterSequence: afterSequence,
                lastEventId: lastEventId,
              )
              .timeout(remaining)) {
        if (item is CockpitRunStreamEvent) {
          final event = item.event;
          afterSequence = event.sequence;
          lastEventId = event.eventId;
          eventCount += 1;
          sink.writeln(jsonEncode(event.toJson()));
          progress?.call(<String, Object?>{
            'stage': 'run',
            'runId': runId,
            'sequence': event.sequence,
            'kind': event.kind,
            if (event.lifecycle != null) 'lifecycle': event.lifecycle!.name,
            if (event.outcome != null) 'outcome': event.outcome!.name,
          });
          continue;
        }
        if (item is CockpitRunStreamGap) {
          throw CockpitSupervisorClientException(
            code: 'eventReplayGap',
            message:
                'Run events are no longer complete: '
                '${jsonEncode(item.boundary.toJson())}',
          );
        }
        if (item is CockpitRunStreamTerminal) {
          return eventCount;
        }
        if (item is CockpitRunStreamDisconnected) {
          afterSequence = item.afterSequence;
          disconnected = true;
        }
      }
    } on CockpitSupervisorClientException catch (error) {
      if (error.code != CockpitErrorCode.transportFailed) rethrow;
      disconnected = true;
      progress?.call(<String, Object?>{
        'stage': 'run',
        'runId': runId,
        'message': 'Event stream disconnected; resuming from $afterSequence.',
      });
    }
    if (!disconnected) {
      throw const CockpitSupervisorClientException(
        code: 'eventStreamEnded',
        message: 'Run event stream ended without a terminal marker.',
      );
    }
    final delay = deadline.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) break;
    await Future<void>.delayed(
      delay < const Duration(milliseconds: 250)
          ? delay
          : const Duration(milliseconds: 250),
    );
  }
  throw TimeoutException(
    'Acceptance run $runId did not finish.',
    Duration.zero,
  );
}

File _artifactDestination(
  String outputDirectory,
  CockpitArtifactResource artifact,
) {
  final root = p.normalize(p.join(outputDirectory, 'artifacts'));
  final relative = p.normalize(
    artifact.relativePath.replaceAll('/', p.separator),
  );
  final destination = p.normalize(p.join(root, relative));
  if (p.isAbsolute(relative) || !p.isWithin(root, destination)) {
    throw const FormatException('Artifact path escapes the output directory.');
  }
  return File(destination);
}

Future<void> _cancelActiveRun(
  CockpitSupervisorApiClient api,
  String runId,
  String invocationId,
  List<Map<String, Object?>> failures,
) async {
  try {
    final current = await api.run(runId);
    if (current.lifecycle == CockpitRunLifecycle.completed) return;
    await api.cancelRun(
      runId,
      CockpitRunCancellationRequest(
        idempotencyKey: CockpitIdempotencyKey('$invocationId-cancel'),
        reason: 'Acceptance runner cleanup after an incomplete execution.',
      ),
    );
  } on Object catch (error) {
    failures.add(_failure(error, 'runCancel'));
  }
}

Future<void> _stopTargetApp({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String targetId,
  required String? appId,
  required String idempotencyKey,
  required List<Map<String, Object?>> failures,
}) async {
  try {
    var resolvedAppId = appId;
    if (resolvedAppId == null) {
      final listed = await _operation(
        api,
        CockpitOperationInvocation(kind: 'app.list', workspaceId: workspaceId),
      );
      final rawApps = listed.output?['apps'];
      final matches = rawApps is List<Object?>
          ? rawApps
                .whereType<Map<Object?, Object?>>()
                .where((app) => app['targetId'] == targetId)
                .toList(growable: false)
          : const <Map<Object?, Object?>>[];
      if (matches.isEmpty) return;
      if (matches.length != 1 || matches.single['appId'] is! String) {
        throw const FormatException(
          'Cannot identify one launched app for target cleanup.',
        );
      }
      resolvedAppId = matches.single['appId']! as String;
    }
    await _operation(
      api,
      CockpitOperationInvocation(
        kind: 'app.stop',
        workspaceId: workspaceId,
        idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        input: <String, Object?>{'appId': resolvedAppId},
      ),
    );
  } on Object catch (error) {
    failures.add(_failure(error, 'appStop'));
  }
}

Future<void> _closeEventSink(
  IOSink? sink,
  List<Map<String, Object?>> failures,
) async {
  if (sink == null) return;
  try {
    await sink.close();
  } on Object catch (error) {
    failures.add(_failure(error, 'eventLogClose'));
  }
}

Future<void> _writeJson(File file, Object? value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}

Map<String, Object?> _failure(Object error, String stage) {
  if (error is CockpitSupervisorClientException) {
    return <String, Object?>{
      'code': error.code,
      'message': _boundedError(error.message),
      'stage': stage,
      if (error.apiError != null) 'apiError': error.apiError!.toJson(),
    };
  }
  return <String, Object?>{
    'code': error.runtimeType.toString(),
    'message': _boundedError('$error'),
    'stage': stage,
  };
}

String _boundedError(String value) {
  final normalized = value
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\t', ' ')
      .trim();
  return normalized.length <= 2048
      ? normalized
      : '${normalized.substring(0, 2048)}...';
}

String _invocationId(String platform) =>
    'acceptance-$platform-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
