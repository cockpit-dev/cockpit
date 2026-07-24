import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_capture_screenshot_service.dart';
import '../application/cockpit_execute_remote_command_batch_service.dart';
import '../application/cockpit_execute_remote_command_service.dart';
import '../application/cockpit_hot_reload_service.dart';
import '../application/cockpit_hot_restart_service.dart';
import '../application/cockpit_inspect_surface_service.dart';
import '../application/cockpit_inspect_ui_service.dart';
import '../application/cockpit_interactive_result_profile.dart';
import '../application/cockpit_interactive_snapshot_store.dart';
import '../application/cockpit_query_development_session_service.dart';
import '../application/cockpit_read_errors_service.dart';
import '../application/cockpit_read_logs_service.dart';
import '../application/cockpit_read_network_service.dart';
import '../application/cockpit_read_remote_snapshot_service.dart';
import '../application/cockpit_read_session_logs_service.dart';
import '../application/cockpit_run_batch_service.dart';
import '../application/cockpit_run_command_service.dart';
import '../application/cockpit_run_shell_service.dart';
import '../application/cockpit_session_registry.dart';
import '../application/cockpit_start_recording_service.dart';
import '../application/cockpit_stop_recording_service.dart';
import '../application/cockpit_wait_idle_service.dart';
import '../system_control/cockpit_system_control_action_service.dart';
import 'cockpit_worker_application_support.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_process_manager.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_resource_identity.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_system_action_parameters.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

typedef CockpitWorkerSessionLogsServiceFactory =
    CockpitReadSessionLogsService Function(CockpitSessionRegistry registry);

final class CockpitWorkerInteractiveOperations {
  factory CockpitWorkerInteractiveOperations({
    required String workspaceId,
    required String workspaceRoot,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerDocumentIndex documents,
    required String producerRoot,
    required CockpitWorkerTargetResolver targets,
    required CockpitWorkerProcessManager processManager,
    CockpitInteractiveSnapshotStore? snapshotStore,
    CockpitInspectUiService? inspectUiService,
    CockpitInspectSurfaceService? inspectSurfaceService,
    CockpitReadLogsService? readLogsService,
    CockpitReadNetworkService? readNetworkService,
    CockpitReadErrorsService? readErrorsService,
    CockpitWorkerSessionLogsServiceFactory? sessionLogsServiceFactory,
    CockpitCaptureScreenshotService? captureScreenshotService,
    CockpitRunCommandService? runCommandService,
    CockpitRunBatchService? runBatchService,
    CockpitRunShellService? runShellService,
    CockpitSystemControlActionService? systemActionService,
    CockpitHotReloadService? hotReloadService,
    CockpitHotRestartService? hotRestartService,
    CockpitWaitIdleService? waitIdleService,
    CockpitStartRecordingService? startRecordingService,
    CockpitStopRecordingService? stopRecordingService,
    CockpitQueryDevelopmentSessionService? queryDevelopmentService,
  }) {
    final snapshots = snapshotStore ?? CockpitInteractiveSnapshotStore();
    final retainedRegistry = CockpitSessionRegistry();
    final executeCommand = CockpitExecuteRemoteCommandService(
      snapshotStore: snapshots,
    );
    final executeBatch = CockpitExecuteRemoteCommandBatchService(
      snapshotStore: snapshots,
    );
    final runCommand =
        runCommandService ??
        CockpitRunCommandService(executeService: executeCommand);
    final runBatch =
        runBatchService ?? CockpitRunBatchService(executeService: executeBatch);
    final inspectUi =
        inspectUiService ??
        CockpitInspectUiService(
          snapshotService: CockpitReadRemoteSnapshotService(
            snapshotStore: snapshots,
          ),
        );
    return CockpitWorkerInteractiveOperations._(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      registry: registry,
      systemActionParameters: CockpitWorkerSystemActionParameters(
        producerRoot: producerRoot,
        documents: documents,
        artifacts: registry,
      ),
      targets: targets,
      inspectUiService: inspectUi,
      inspectSurfaceService:
          inspectSurfaceService ??
          CockpitInspectSurfaceService(inspectUiService: inspectUi),
      readLogsService:
          readLogsService ?? CockpitReadLogsService(registry: retainedRegistry),
      readNetworkService:
          readNetworkService ??
          CockpitReadNetworkService(registry: retainedRegistry),
      readErrorsService:
          readErrorsService ??
          CockpitReadErrorsService(registry: retainedRegistry),
      sessionLogsServiceFactory:
          sessionLogsServiceFactory ??
          (sessionRegistry) =>
              CockpitReadSessionLogsService(registry: sessionRegistry),
      captureScreenshotService:
          captureScreenshotService ??
          CockpitCaptureScreenshotService(runCommandService: runCommand),
      runCommandService: runCommand,
      runBatchService: runBatch,
      runShellService:
          runShellService ??
          CockpitRunShellService(processManager: processManager),
      systemActionService:
          systemActionService ?? CockpitSystemControlActionService(),
      hotReloadService: hotReloadService ?? CockpitHotReloadService(),
      hotRestartService: hotRestartService ?? CockpitHotRestartService(),
      waitIdleService: waitIdleService ?? CockpitWaitIdleService(),
      startRecordingService:
          startRecordingService ?? CockpitStartRecordingService(),
      stopRecordingService:
          stopRecordingService ?? CockpitStopRecordingService(),
      queryDevelopmentService:
          queryDevelopmentService ?? CockpitQueryDevelopmentSessionService(),
    );
  }

  CockpitWorkerInteractiveOperations._({
    required this.workspaceId,
    required this.workspaceRoot,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerSystemActionParameters systemActionParameters,
    required CockpitWorkerTargetResolver targets,
    required CockpitInspectUiService inspectUiService,
    required CockpitInspectSurfaceService inspectSurfaceService,
    required CockpitReadLogsService readLogsService,
    required CockpitReadNetworkService readNetworkService,
    required CockpitReadErrorsService readErrorsService,
    required CockpitWorkerSessionLogsServiceFactory sessionLogsServiceFactory,
    required CockpitCaptureScreenshotService captureScreenshotService,
    required CockpitRunCommandService runCommandService,
    required CockpitRunBatchService runBatchService,
    required CockpitRunShellService runShellService,
    required CockpitSystemControlActionService systemActionService,
    required CockpitHotReloadService hotReloadService,
    required CockpitHotRestartService hotRestartService,
    required CockpitWaitIdleService waitIdleService,
    required CockpitStartRecordingService startRecordingService,
    required CockpitStopRecordingService stopRecordingService,
    required CockpitQueryDevelopmentSessionService queryDevelopmentService,
  }) : _registry = registry,
       _systemActionParameters = systemActionParameters,
       _targets = targets,
       _inspectUi = inspectUiService,
       _inspectSurface = inspectSurfaceService,
       _readLogs = readLogsService,
       _readNetwork = readNetworkService,
       _readErrors = readErrorsService,
       _sessionLogsServiceFactory = sessionLogsServiceFactory,
       _captureScreenshot = captureScreenshotService,
       _runCommand = runCommandService,
       _runBatch = runBatchService,
       _runShell = runShellService,
       _systemAction = systemActionService,
       _hotReload = hotReloadService,
       _hotRestart = hotRestartService,
       _waitIdle = waitIdleService,
       _startRecording = startRecordingService,
       _stopRecording = stopRecordingService,
       _queryDevelopment = queryDevelopmentService;

  static const Set<String> kinds = <String>{
    'ui.inspect',
    'surface.inspect',
    'logs.read',
    'network.read',
    'errors.read',
    'session.logs.read',
    'evidence.screenshot.capture',
    'command.run',
    'command.batch',
    'shell.run',
    'system.action',
    'app.reload',
    'app.restart',
    'ui.waitIdle',
    'recording.start',
    'recording.stop',
  };

  final String workspaceId;
  final String workspaceRoot;
  final CockpitWorkerRuntimeRegistry _registry;
  final CockpitWorkerSystemActionParameters _systemActionParameters;
  final CockpitWorkerTargetResolver _targets;
  final CockpitInspectUiService _inspectUi;
  final CockpitInspectSurfaceService _inspectSurface;
  final CockpitReadLogsService _readLogs;
  final CockpitReadNetworkService _readNetwork;
  final CockpitReadErrorsService _readErrors;
  final CockpitWorkerSessionLogsServiceFactory _sessionLogsServiceFactory;
  final CockpitCaptureScreenshotService _captureScreenshot;
  final CockpitRunCommandService _runCommand;
  final CockpitRunBatchService _runBatch;
  final CockpitRunShellService _runShell;
  final CockpitSystemControlActionService _systemAction;
  final CockpitHotReloadService _hotReload;
  final CockpitHotRestartService _hotRestart;
  final CockpitWaitIdleService _waitIdle;
  final CockpitStartRecordingService _startRecording;
  final CockpitStopRecordingService _stopRecording;
  final CockpitQueryDevelopmentSessionService _queryDevelopment;

  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
    required CockpitWorkerResultSanitizer sanitizer,
  }) => switch (kind) {
    'ui.inspect' => _inspectUiOperation(input, context, grants, sanitizer),
    'surface.inspect' => _inspectSurfaceOperation(
      input,
      context,
      grants,
      sanitizer,
    ),
    'logs.read' => _readLogsOperation(input, context, grants, sanitizer),
    'network.read' => _readNetworkOperation(input, context, grants, sanitizer),
    'errors.read' => _readErrorsOperation(input, context, grants, sanitizer),
    'session.logs.read' => _readSessionLogs(input, context, grants, sanitizer),
    'evidence.screenshot.capture' => _captureScreenshotOperation(
      input,
      context,
      grants,
      sanitizer,
    ),
    'command.run' => _runCommandOperation(input, context, grants, sanitizer),
    'command.batch' => _runBatchOperation(input, context, grants, sanitizer),
    'shell.run' => _runShellOperation(input, context, grants, sanitizer),
    'system.action' => _runSystemAction(input, context, grants, sanitizer),
    'app.reload' => _reloadApp(input, context, grants, sanitizer),
    'app.restart' => _restartApp(input, context, grants, sanitizer),
    'ui.waitIdle' => _waitIdleOperation(input, context, grants, sanitizer),
    'recording.start' => _startRecordingOperation(
      input,
      context,
      grants,
      sanitizer,
    ),
    'recording.stop' => _stopRecordingOperation(
      input,
      context,
      grants,
      sanitizer,
    ),
    _ => throw StateError('Interactive operation routing is inconsistent.'),
  };

  Future<Map<String, Object?>> _inspectUiOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'profile',
        'snapshotOptions',
        'compareAgainstSnapshotRef',
      },
    );
    _requireSessionGrant(pair.binding, context, grants);
    final app = await _registry.requireApp(pair.binding.appId);
    final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
      sessionId: pair.binding.sessionId,
      snapshotRef: pair.input.optionalId('compareAgainstSnapshotRef'),
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _inspectUi.inspect(
        CockpitInspectUiRequest(
          app: app.handle,
          resultProfile: pair.input.profile(
            defaultName: CockpitInteractiveResultProfileName.inspect,
          ),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _inspectSurfaceOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'profile',
        'snapshotOptions',
        'compareAgainstSnapshotRef',
      },
    );
    _requireSessionGrant(pair.binding, context, grants);
    final target = await _targets.requireTarget(
      workspaceId: workspaceId,
      targetId: pair.binding.targetId,
    );
    final handle = target.handle;
    if (handle == null) {
      throw const FormatException('Worker target has no launched handle.');
    }
    final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
      sessionId: pair.binding.sessionId,
      snapshotRef: pair.input.optionalId('compareAgainstSnapshotRef'),
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _inspectSurface.inspect(
        CockpitInspectSurfaceRequest(
          target: handle,
          resultProfile: pair.input.profile(
            defaultName: CockpitInteractiveResultProfileName.inspect,
          ),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _readLogsOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(input, extra: const <String>{'maxLines'});
    _requireSessionGrant(pair.binding, context, grants);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readLogs.read(
        CockpitReadLogsRequest(
          baseUri: pair.binding.remoteHandle.baseUri,
          maxLines:
              pair.input.optionalInteger(
                'maxLines',
                minimum: 1,
                maximum: 5000,
              ) ??
              200,
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _readNetworkOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'maxEntries',
        'maxEndpointSummaries',
        'includeEntries',
        'method',
        'uriContains',
        'onlyFailures',
        'statusCodeAtLeast',
      },
    );
    _requireSessionGrant(pair.binding, context, grants);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readNetwork.read(
        CockpitReadNetworkRequest(
          baseUri: pair.binding.remoteHandle.baseUri,
          maxEntries:
              pair.input.optionalInteger(
                'maxEntries',
                minimum: 1,
                maximum: 1000,
              ) ??
              8,
          maxEndpointSummaries:
              pair.input.optionalInteger(
                'maxEndpointSummaries',
                minimum: 1,
                maximum: 1000,
              ) ??
              8,
          includeEntries: pair.input.boolean('includeEntries'),
          method: pair.input.optionalString('method', maximum: 32),
          uriContains: pair.input.optionalString('uriContains', maximum: 512),
          onlyFailures: pair.input.boolean('onlyFailures'),
          statusCodeAtLeast: pair.input.optionalInteger(
            'statusCodeAtLeast',
            minimum: 100,
            maximum: 599,
          ),
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _readErrorsOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(input, extra: const <String>{'maxErrors'});
    _requireSessionGrant(pair.binding, context, grants);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readErrors.read(
        CockpitReadErrorsRequest(
          baseUri: pair.binding.remoteHandle.baseUri,
          maxErrors:
              pair.input.optionalInteger(
                'maxErrors',
                minimum: 1,
                maximum: 1000,
              ) ??
              20,
          includeSessions: false,
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _readSessionLogs(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(input, extra: const <String>{'maxLines'});
    _requireSessionGrant(pair.binding, context, grants);
    final handle = pair.binding.developmentHandle;
    if (handle == null) {
      throw const FormatException(
        'Session logs require a development session.',
      );
    }
    final app = await _registry.requireApp(pair.binding.appId);
    final query = await runWorkerApplicationOperation(
      context: context,
      operation: () => _queryDevelopment.query(
        CockpitQueryDevelopmentSessionRequest(sessionHandle: handle),
      ),
    );
    final retainedRegistry = CockpitSessionRegistry()
      ..recordDevelopmentSession(
        handle: query.sessionHandle ?? handle,
        status: query.status,
        supervisorLogPath: app.handle.supervisorLogPath,
      );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _sessionLogsServiceFactory(retainedRegistry).read(
        CockpitReadSessionLogsRequest(
          developmentSessionId: handle.developmentSessionId,
          maxLines:
              pair.input.optionalInteger(
                'maxLines',
                minimum: 1,
                maximum: 5000,
              ) ??
              200,
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _captureScreenshotOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'name',
        'reason',
        'includeSnapshot',
        'attachToStep',
        'captureProfile',
        'allowFallback',
        'profile',
        'timeoutMs',
      },
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.capture,
      resourceId: pair.binding.resourceId,
    );
    final app = await _registry.requireApp(pair.binding.appId);
    final captureProfile = pair.input.optionalString(
      'captureProfile',
      maximum: 32,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _captureScreenshot.capture(
        CockpitCaptureScreenshotRequest(
          app: app.handle,
          name: pair.input.optionalString('name', maximum: 128) ?? 'screenshot',
          reason: CockpitScreenshotReason.fromJson(
            pair.input.optionalString('reason', maximum: 32) ?? 'acceptance',
          ),
          includeSnapshot: pair.input.boolean('includeSnapshot'),
          attachToStep: pair.input.boolean('attachToStep', defaultValue: true),
          captureProfile: captureProfile == null
              ? null
              : CockpitCaptureProfile.fromJson(captureProfile),
          allowFallback: input['allowFallback'] == null
              ? null
              : pair.input.boolean('allowFallback'),
          resultProfile: pair.input.profile(),
          defaultCommandTimeout: _commandTimeout(pair.input, context),
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _runCommandOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'command',
        'timeoutMs',
        'profile',
        'snapshotOptions',
        'compareAgainstSnapshotRef',
      },
      required: const <String>{'command'},
    );
    _requireSessionGrant(pair.binding, context, grants);
    final app = await _registry.requireApp(pair.binding.appId);
    final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
      sessionId: pair.binding.sessionId,
      snapshotRef: pair.input.optionalId('compareAgainstSnapshotRef'),
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _runCommand.run(
        CockpitRunCommandRequest(
          app: app.handle,
          command: CockpitCommand.fromJson(pair.input.object('command')),
          resultProfile: pair.input.profile(),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
          defaultCommandTimeout: _commandTimeout(pair.input, context),
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _runBatchOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{
        'commands',
        'timeoutMs',
        'profile',
        'failFast',
        'recording',
        'finalSnapshotProfile',
        'finalSnapshotOptions',
      },
      required: const <String>{'commands'},
    );
    _requireSessionGrant(pair.binding, context, grants);
    final commands = await _batchCommands(pair.input, pair.binding.sessionId);
    final app = await _registry.requireApp(pair.binding.appId);
    final recordingJson = pair.input.optionalObject('recording');
    final finalProfile = pair.input.optionalString(
      'finalSnapshotProfile',
      maximum: 32,
    );
    final finalOptions = pair.input.optionalObject('finalSnapshotOptions');
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _runBatch.run(
        CockpitRunBatchRequest(
          app: app.handle,
          commands: commands,
          defaultResultProfile: pair.input.profile(),
          failFast: pair.input.boolean('failFast', defaultValue: true),
          recording: recordingJson == null
              ? null
              : CockpitRecordingRequest.fromJson(recordingJson),
          finalSnapshotProfile: finalProfile == null
              ? null
              : CockpitInteractiveResultProfile.preset(
                  CockpitInteractiveResultProfileName.fromJson(finalProfile),
                ),
          finalSnapshotOptions: finalOptions == null
              ? null
              : CockpitSnapshotOptions.fromJson(finalOptions),
          defaultCommandTimeout: _commandTimeout(pair.input, context),
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _runShellOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'command', 'timeoutMs'},
      required: const <String>{'command'},
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.workspaceMutation,
      resourceId: cockpitCanonicalWorkspaceResourceId(workspaceId),
    );
    final raw = values.list('command', maximum: 128);
    if (raw.isEmpty) throw const FormatException('Shell command is empty.');
    final command = <String>[];
    for (var index = 0; index < raw.length; index += 1) {
      final value = workerString(
        raw[index],
        '\$.input.command[$index]',
        maximum: 4096,
      );
      if (p.isAbsolute(value) || value == '..' || value.startsWith('../')) {
        throw const FormatException(
          'Shell command cannot contain direct filesystem paths.',
        );
      }
      command.add(value);
    }
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _runShell.run(
        CockpitRunShellRequest(
          command: command,
          workingDirectory: workspaceRoot,
          timeout: boundedWorkerDuration(
            context: context,
            requestedMilliseconds: values.optionalInteger(
              'timeoutMs',
              minimum: 1,
              maximum: 300000,
            ),
            defaultValue: const Duration(seconds: 30),
            maximum: const Duration(minutes: 5),
          ),
        ),
      ),
    );
    return sanitizer.sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _runSystemAction(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'targetId', 'action', 'parameters', 'timeoutMs'},
      required: const <String>{'targetId', 'action'},
    );
    final targetId = values.id('targetId');
    final target = await _targets.requireTarget(
      workspaceId: workspaceId,
      targetId: targetId,
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.device,
      resourceId: target.deviceResourceId,
    );
    final app = await _registry.latestAppForTarget(targetId);
    final action = CockpitSystemControlAction.fromJson(
      values.string('action', maximum: 64),
    );
    final preparedParameters = await _systemActionParameters.prepare(
      action: action,
      platform: target.registration.platform,
      idempotencyKey: context.idempotencyKey,
      parameters:
          values.optionalObject('parameters') ?? const <String, Object?>{},
    );
    final sessionId = preparedParameters.producedPath == null
        ? null
        : await _requireArtifactOwnerSession(app);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _systemAction.run(
        CockpitSystemControlActionRequest(
          platform: target.registration.platform,
          deviceId: target.registration.deviceId,
          appId: app?.handle.platformAppId ?? target.registration.appId,
          processId: app?.handle.processId,
          metadata: <String, Object?>{
            if (target.registration.wdaUrl != null)
              'wdaUrl': target.registration.wdaUrl,
          },
          action: action,
          parameters: preparedParameters.parameters,
          timeout: boundedWorkerDuration(
            context: context,
            requestedMilliseconds: values.optionalInteger(
              'timeoutMs',
              minimum: 1,
              maximum: 120000,
            ),
            defaultValue: const Duration(seconds: 15),
            maximum: const Duration(minutes: 2),
          ),
        ),
      ),
    );
    final json = result.toJson();
    if (result.success && preparedParameters.producedPath != null) {
      json.putIfAbsent('sourceFilePath', () => preparedParameters.producedPath);
    }
    return sanitizer.sanitize(
      json,
      targetId: targetId,
      appId: app?.appId,
      sessionId: sessionId,
    );
  }

  Future<String> _requireArtifactOwnerSession(
    CockpitWorkerAppBinding? app,
  ) async {
    if (app == null) {
      throw const CockpitApplicationServiceException(
        code: 'workerSessionNotFound',
        message: 'Artifact-producing system actions require an active app.',
      );
    }
    return _registry.sessionIdForApp(app.appId);
  }

  Future<Map<String, Object?>> _reloadApp(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) => _reloadOrRestart(input, context, grants, sanitizer, restart: false);

  Future<Map<String, Object?>> _restartApp(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) => _reloadOrRestart(input, context, grants, sanitizer, restart: true);

  Future<Map<String, Object?>> _reloadOrRestart(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer, {
    required bool restart,
  }) async {
    final pair = await _session(input);
    _requireSessionGrant(pair.binding, context, grants);
    final app = await _registry.requireApp(pair.binding.appId);
    if (restart) {
      final result = await runWorkerApplicationOperation(
        context: context,
        operation: () =>
            _hotRestart.restart(CockpitHotRestartRequest(app: app.handle)),
      );
      await _registry.updateDevelopmentSession(
        pair.binding.sessionId,
        result.app.developmentSession!,
      );
      return _sanitize(result.toJson(), pair.binding, sanitizer);
    }
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () =>
          _hotReload.reload(CockpitHotReloadRequest(app: app.handle)),
    );
    await _registry.updateDevelopmentSession(
      pair.binding.sessionId,
      result.app.developmentSession!,
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _waitIdleOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{'quietWindowMs', 'timeoutMs', 'includeNetworkIdle'},
    );
    _requireSessionGrant(pair.binding, context, grants);
    final app = await _registry.requireApp(pair.binding.appId);
    final timeout = boundedWorkerDuration(
      context: context,
      requestedMilliseconds: pair.input.optionalInteger(
        'timeoutMs',
        minimum: 1,
        maximum: 30000,
      ),
      defaultValue: const Duration(milliseconds: 1600),
      maximum: const Duration(seconds: 30),
    );
    final quietWindow = Duration(
      milliseconds:
          pair.input.optionalInteger(
            'quietWindowMs',
            minimum: 1,
            maximum: 5000,
          ) ??
          96,
    );
    if (quietWindow > timeout) {
      throw const FormatException('UI quiet window exceeds wait timeout.');
    }
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _waitIdle.wait(
        CockpitWaitIdleRequest(
          app: app.handle,
          quietWindow: quietWindow,
          timeout: timeout,
          includeNetworkIdle: pair.input.boolean(
            'includeNetworkIdle',
            defaultValue: true,
          ),
        ),
      ),
    );
    return _sanitize(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _startRecordingOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(input, extra: const <String>{'recording'});
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.recording,
      resourceId: pair.binding.resourceId,
    );
    final app = await _registry.requireApp(pair.binding.appId);
    final recordingJson = pair.input.optionalObject('recording');
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _startRecording.start(
        CockpitStartRecordingRequest(
          app: app.handle,
          recording: recordingJson == null
              ? const CockpitRecordingRequest(
                  purpose: CockpitRecordingPurpose.repro,
                  name: 'worker-recording',
                )
              : CockpitRecordingRequest.fromJson(recordingJson),
        ),
      ),
    );
    final recording = await _registry.recordRecording(
      sessionId: pair.binding.sessionId,
    );
    final sanitized = await _sanitize(
      result.toJson(),
      pair.binding,
      sanitizer,
      recordingId: recording.recordingId,
    );
    return sanitized..['recordingId'] = recording.recordingId;
  }

  Future<Map<String, Object?>> _stopRecordingOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'recordingId'},
      required: const <String>{'recordingId'},
    );
    final recording = await _registry.requireRecording(
      values.id('recordingId'),
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.recording,
      resourceId: recording.resourceId,
    );
    final session = await _registry.requireSession(recording.sessionId);
    final app = await _registry.requireApp(recording.appId);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () =>
          _stopRecording.stop(CockpitStopRecordingRequest(app: app.handle)),
    );
    await _registry.removeRecording(recording.recordingId);
    final sanitized = await _sanitize(result.toJson(), session, sanitizer);
    return sanitized..['recordingId'] = recording.recordingId;
  }

  Future<_SessionInput> _session(
    Map<String, Object?> input, {
    Set<String> extra = const <String>{},
    Set<String> required = const <String>{},
  }) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: <String>{'sessionId', ...extra},
      required: <String>{'sessionId', ...required},
    );
    return _SessionInput(
      values,
      await _registry.requireSession(values.id('sessionId')),
    );
  }

  Future<List<CockpitRunBatchCommand>> _batchCommands(
    CockpitWorkerApplicationInput input,
    String sessionId,
  ) async {
    final raw = input.list('commands', maximum: 1000);
    if (raw.isEmpty) throw const FormatException('Command batch is empty.');
    final commands = <CockpitRunBatchCommand>[];
    for (var index = 0; index < raw.length; index += 1) {
      commands.add(await _batchCommand(raw[index], index, sessionId));
    }
    return commands;
  }

  Future<CockpitRunBatchCommand> _batchCommand(
    Object? value,
    int index,
    String sessionId,
  ) async {
    final path = '\$.input.commands[$index]';
    final json = workerObject(value, path);
    workerKeys(
      json,
      const <String>{
        'command',
        'profile',
        'snapshotOptions',
        'compareAgainstSnapshotRef',
      },
      path,
      required: const <String>{'command'},
    );
    final values = CockpitWorkerApplicationInput(
      json,
      allowed: const <String>{
        'command',
        'profile',
        'snapshotOptions',
        'compareAgainstSnapshotRef',
      },
      required: const <String>{'command'},
    );
    return CockpitRunBatchCommand(
      command: CockpitCommand.fromJson(values.object('command')),
      resultProfile: json['profile'] == null ? null : values.profile(),
      snapshotOptions: values.optionalSnapshotOptions(),
      compareAgainstSnapshotRef: await _registry.resolveSnapshotRef(
        sessionId: sessionId,
        snapshotRef: values.optionalId('compareAgainstSnapshotRef'),
      ),
    );
  }

  Duration _commandTimeout(
    CockpitWorkerApplicationInput input,
    CockpitWorkspaceOperationContext context,
  ) => boundedWorkerDuration(
    context: context,
    requestedMilliseconds: input.optionalInteger(
      'timeoutMs',
      minimum: 1,
      maximum: 300000,
    ),
    defaultValue: const Duration(seconds: 30),
    maximum: const Duration(minutes: 5),
  );

  void _requireSessionGrant(
    CockpitWorkerSessionBinding session,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
  ) {
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
  }

  Future<Map<String, Object?>> _sanitize(
    Map<String, Object?> result,
    CockpitWorkerSessionBinding session,
    CockpitWorkerResultSanitizer sanitizer, {
    String? recordingId,
  }) => sanitizer.sanitize(
    result,
    sessionId: session.sessionId,
    appId: session.appId,
    targetId: session.targetId,
    recordingId: recordingId,
  );
}

final class _SessionInput {
  const _SessionInput(this.input, this.binding);

  final CockpitWorkerApplicationInput input;
  final CockpitWorkerSessionBinding binding;
}
