import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_app_temp_store.dart';
import '../application/cockpit_collect_remote_snapshot_service.dart';
import '../application/cockpit_execute_remote_command_batch_service.dart';
import '../application/cockpit_execute_remote_command_service.dart';
import '../application/cockpit_interactive_result_profile.dart';
import '../application/cockpit_interactive_snapshot_store.dart';
import '../application/cockpit_launch_remote_session_service.dart';
import '../application/cockpit_query_remote_session_service.dart';
import '../application/cockpit_read_remote_snapshot_service.dart';
import '../application/cockpit_read_remote_status_service.dart';
import '../application/cockpit_stop_app_service.dart';
import '../application/cockpit_wait_remote_ui_idle_service.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../targets/cockpit_target_handle.dart';
import 'cockpit_worker_application_support.dart';
import 'cockpit_worker_forwarded_port_handoff.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkerRemoteOperations {
  factory CockpitWorkerRemoteOperations({
    required String workspaceId,
    required String producerRoot,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerTargetResolver targets,
    required CockpitWorkerForwardedPortHandoff portHandoff,
    required CockpitAppTempStore appTempStore,
    CockpitInteractiveSnapshotStore? snapshotStore,
    CockpitLaunchRemoteSessionService? launchService,
    CockpitStopAppService? stopAppService,
    CockpitQueryRemoteSessionService? queryService,
    CockpitReadRemoteStatusService? statusService,
    CockpitReadRemoteSnapshotService? readSnapshotService,
    CockpitCollectRemoteSnapshotService? collectSnapshotService,
    CockpitExecuteRemoteCommandService? executeCommandService,
    CockpitExecuteRemoteCommandBatchService? executeBatchService,
    CockpitWaitRemoteUiIdleService? waitIdleService,
  }) {
    final snapshots = snapshotStore ?? CockpitInteractiveSnapshotStore();
    final artifactTempFileFactory = cockpitWorkerArtifactTempFileFactory(
      producerRoot,
    );
    return CockpitWorkerRemoteOperations._(
      workspaceId: workspaceId,
      registry: registry,
      targets: targets,
      portHandoff: portHandoff,
      launchService:
          launchService ??
          CockpitLaunchRemoteSessionService(appTempStore: appTempStore),
      stopAppService:
          stopAppService ?? CockpitStopAppService(appTempStore: appTempStore),
      queryService: queryService ?? CockpitQueryRemoteSessionService(),
      statusService:
          statusService ??
          CockpitReadRemoteStatusService(snapshotStore: snapshots),
      readSnapshotService:
          readSnapshotService ??
          CockpitReadRemoteSnapshotService(
            snapshotStore: snapshots,
            artifactTempFileFactory: artifactTempFileFactory,
          ),
      collectSnapshotService:
          collectSnapshotService ?? CockpitCollectRemoteSnapshotService(),
      executeCommandService:
          executeCommandService ??
          CockpitExecuteRemoteCommandService(
            snapshotStore: snapshots,
            artifactTempFileFactory: artifactTempFileFactory,
          ),
      executeBatchService:
          executeBatchService ??
          CockpitExecuteRemoteCommandBatchService(
            snapshotStore: snapshots,
            artifactTempFileFactory: artifactTempFileFactory,
          ),
      waitIdleService: waitIdleService ?? CockpitWaitRemoteUiIdleService(),
    );
  }

  CockpitWorkerRemoteOperations._({
    required this.workspaceId,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerTargetResolver targets,
    required CockpitWorkerForwardedPortHandoff portHandoff,
    required CockpitLaunchRemoteSessionService launchService,
    required CockpitStopAppService stopAppService,
    required CockpitQueryRemoteSessionService queryService,
    required CockpitReadRemoteStatusService statusService,
    required CockpitReadRemoteSnapshotService readSnapshotService,
    required CockpitCollectRemoteSnapshotService collectSnapshotService,
    required CockpitExecuteRemoteCommandService executeCommandService,
    required CockpitExecuteRemoteCommandBatchService executeBatchService,
    required CockpitWaitRemoteUiIdleService waitIdleService,
  }) : _registry = registry,
       _targets = targets,
       _portHandoff = portHandoff,
       _launch = launchService,
       _stopApp = stopAppService,
       _query = queryService,
       _status = statusService,
       _readSnapshot = readSnapshotService,
       _collectSnapshot = collectSnapshotService,
       _executeCommand = executeCommandService,
       _executeBatch = executeBatchService,
       _waitIdle = waitIdleService;

  static const Set<String> kinds = <String>{
    'session.remote.launch',
    'session.remote.get',
    'session.remote.status',
    'snapshot.remote.read',
    'snapshot.remote.collect',
    'command.remote.execute',
    'command.remote.batch',
    'ui.remote.waitIdle',
  };

  final String workspaceId;
  final CockpitWorkerRuntimeRegistry _registry;
  final CockpitWorkerTargetResolver _targets;
  final CockpitWorkerForwardedPortHandoff _portHandoff;
  final CockpitLaunchRemoteSessionService _launch;
  final CockpitStopAppService _stopApp;
  final CockpitQueryRemoteSessionService _query;
  final CockpitReadRemoteStatusService _status;
  final CockpitReadRemoteSnapshotService _readSnapshot;
  final CockpitCollectRemoteSnapshotService _collectSnapshot;
  final CockpitExecuteRemoteCommandService _executeCommand;
  final CockpitExecuteRemoteCommandBatchService _executeBatch;
  final CockpitWaitRemoteUiIdleService _waitIdle;

  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
    required CockpitWorkerResultSanitizer sanitizer,
  }) => switch (kind) {
    'session.remote.launch' => _launchSession(
      input,
      context,
      grants,
      sanitizer,
    ),
    'session.remote.get' => _querySession(input, context, grants, sanitizer),
    'session.remote.status' => _readStatus(input, context, grants, sanitizer),
    'snapshot.remote.read' => _readRemoteSnapshot(
      input,
      context,
      grants,
      sanitizer,
    ),
    'snapshot.remote.collect' => _collectRemoteSnapshot(
      input,
      context,
      grants,
      sanitizer,
    ),
    'command.remote.execute' => _executeRemoteCommand(
      input,
      context,
      grants,
      sanitizer,
    ),
    'command.remote.batch' => _executeRemoteBatch(
      input,
      context,
      grants,
      sanitizer,
    ),
    'ui.remote.waitIdle' => _waitRemoteIdle(input, context, grants, sanitizer),
    _ => throw StateError('Remote operation routing is inconsistent.'),
  };

  Future<Map<String, Object?>> _launchSession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{
        'targetId',
        'launchTimeoutMs',
        'launchConfiguration',
      },
      required: const <String>{'targetId'},
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
    final portGrant = requireForwardedPortGrant(
      workspaceId: workspaceId,
      grants: grants,
      deadline: context.deadline,
    );
    final timeout = boundedWorkerDuration(
      context: context,
      requestedMilliseconds: values.optionalInteger(
        'launchTimeoutMs',
        minimum: 1,
        maximum: 1800000,
      ),
      defaultValue: const Duration(minutes: 2),
      maximum: const Duration(minutes: 30),
    );
    final launchConfigurationJson = values.optionalObject(
      'launchConfiguration',
    );
    final launchConfiguration = launchConfigurationJson == null
        ? CockpitFlutterLaunchConfiguration.empty
        : CockpitFlutterLaunchConfiguration.fromJson(launchConfigurationJson);
    return runWorkerTransactionalPortLaunch<
      CockpitLaunchRemoteSessionResult,
      Map<String, Object?>
    >(
      handoff: _portHandoff,
      grant: portGrant,
      deadline: context.deadline,
      launch: (port) => runWorkerApplicationOperation(
        context: context,
        operation: () => _launch.launch(
          CockpitLaunchRemoteSessionRequest(
            projectDir: target.projectDir,
            target: target.launchEntrypoint,
            flavor: target.registration.flavor,
            platform: target.registration.platform,
            deviceId: target.registration.deviceId,
            sessionPort: port,
            launchTimeout: timeout,
            allowSessionPortFallback: false,
            launchConfiguration: launchConfiguration,
          ),
        ),
      ),
      commit: (result) async {
        final app = CockpitAppHandle.fromRemoteSession(result.sessionHandle);
        final appBinding = await _registry.recordLaunchedApp(
          targetId: targetId,
          targetHandle: CockpitTargetHandle.fromAppHandle(app),
          appHandle: app,
        );
        try {
          final sessionId = await _registry.sessionIdForApp(appBinding.appId);
          return await sanitizer.sanitize(
            <String, Object?>{
              'sessionId': sessionId,
              'appId': appBinding.appId,
              'targetId': targetId,
              'health': result.health.toJson(),
            },
            sessionId: sessionId,
            appId: appBinding.appId,
            targetId: targetId,
          );
        } on Object catch (primary, primaryStackTrace) {
          try {
            await _registry.removeApp(appBinding.appId);
          } on Object catch (cleanupError) {
            throw CockpitWorkerOperationRollbackException(
              primary: primary,
              cleanupError: cleanupError,
              warningCode: 'runtimeRegistrationRollbackFailed',
              warningMessage:
                  'Failed to remove a partially registered application.',
            );
          }
          Error.throwWithStackTrace(primary, primaryStackTrace);
        }
      },
      rollback: (result) async {
        await _stopApp.stop(
          CockpitStopAppRequest(
            app: CockpitAppHandle.fromRemoteSession(result.sessionHandle),
          ),
        );
      },
    );
  }

  Future<Map<String, Object?>> _querySession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(input);
    _requireSessionGrant(pair.binding, context, grants, allowUnleased: true);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _query.query(
        CockpitQueryRemoteSessionRequest(
          sessionHandle: pair.binding.remoteHandle,
        ),
      ),
    );
    return sanitizer.sanitize(
      <String, Object?>{
        'sessionId': pair.binding.sessionId,
        'appId': pair.binding.appId,
        'targetId': pair.binding.targetId,
        'status': result.status.toJson(),
        'recommendedNextStep': result.recommendedNextStep,
      },
      sessionId: pair.binding.sessionId,
      appId: pair.binding.appId,
      targetId: pair.binding.targetId,
    );
  }

  Future<Map<String, Object?>> _readStatus(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{'profile', 'snapshotOptions'},
    );
    _requireSessionGrant(pair.binding, context, grants, allowUnleased: true);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _status.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: pair.binding.remoteHandle,
          resultProfile: pair.input.profile(
            defaultName: CockpitInteractiveResultProfileName.minimal,
          ),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          deadline: context.deadline,
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _readRemoteSnapshot(
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
    _requireSessionGrant(pair.binding, context, grants, allowUnleased: true);
    final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
      sessionId: pair.binding.sessionId,
      snapshotRef: pair.input.optionalId('compareAgainstSnapshotRef'),
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readSnapshot.read(
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: pair.binding.remoteHandle,
          resultProfile: pair.input.profile(),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
          deadline: context.deadline,
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _collectRemoteSnapshot(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final pair = await _session(
      input,
      extra: const <String>{'snapshotOptions', 'downloadDiagnosticsArtifacts'},
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.capture,
      resourceId: pair.binding.resourceId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _collectSnapshot.collect(
        CockpitCollectRemoteSnapshotRequest(
          sessionHandle: pair.binding.remoteHandle,
          options:
              pair.input.optionalSnapshotOptions() ??
              const CockpitSnapshotOptions.live(),
          downloadDiagnosticsArtifacts: pair.input.boolean(
            'downloadDiagnosticsArtifacts',
          ),
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _executeRemoteCommand(
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
    final timeout = _commandTimeout(pair.input, context);
    final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
      sessionId: pair.binding.sessionId,
      snapshotRef: pair.input.optionalId('compareAgainstSnapshotRef'),
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _executeCommand.execute(
        CockpitExecuteRemoteCommandRequest(
          sessionHandle: pair.binding.remoteHandle,
          command: CockpitCommand.fromJson(pair.input.object('command')),
          defaultCommandTimeout: timeout,
          resultProfile: pair.input.profile(),
          snapshotOptions: pair.input.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _executeRemoteBatch(
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
    final commands = pair.input.list('commands', maximum: 1000);
    if (commands.isEmpty) {
      throw const FormatException('Remote command batch cannot be empty.');
    }
    final parsed = <CockpitInteractiveBatchCommand>[];
    for (var index = 0; index < commands.length; index += 1) {
      final item = workerObject(commands[index], '\$.input.commands[$index]');
      workerKeys(
        item,
        const <String>{
          'command',
          'profile',
          'snapshotOptions',
          'compareAgainstSnapshotRef',
        },
        '\$.input.commands[$index]',
        required: const <String>{'command'},
      );
      final commandInput = CockpitWorkerApplicationInput(
        item,
        allowed: const <String>{
          'command',
          'profile',
          'snapshotOptions',
          'compareAgainstSnapshotRef',
        },
        required: const <String>{'command'},
      );
      final compareAgainstSnapshotRef = await _registry.resolveSnapshotRef(
        sessionId: pair.binding.sessionId,
        snapshotRef: commandInput.optionalId('compareAgainstSnapshotRef'),
      );
      parsed.add(
        CockpitInteractiveBatchCommand(
          command: CockpitCommand.fromJson(commandInput.object('command')),
          resultProfile: item['profile'] == null
              ? null
              : commandInput.profile(),
          snapshotOptions: commandInput.optionalSnapshotOptions(),
          compareAgainstSnapshotRef: compareAgainstSnapshotRef,
        ),
      );
    }
    final finalProfile = pair.input.optionalString(
      'finalSnapshotProfile',
      maximum: 32,
    );
    final recordingJson = pair.input.optionalObject('recording');
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _executeBatch.execute(
        CockpitExecuteRemoteCommandBatchRequest(
          sessionHandle: pair.binding.remoteHandle,
          commands: parsed,
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
          finalSnapshotOptions:
              pair.input.optionalObject('finalSnapshotOptions') == null
              ? null
              : CockpitSnapshotOptions.fromJson(
                  pair.input.object('finalSnapshotOptions'),
                ),
          defaultCommandTimeout: _commandTimeout(pair.input, context),
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
  }

  Future<Map<String, Object?>> _waitRemoteIdle(
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
    final timeout = boundedWorkerDuration(
      context: context,
      requestedMilliseconds: pair.input.optionalInteger(
        'timeoutMs',
        minimum: 1,
        maximum: 300000,
      ),
      defaultValue: const Duration(seconds: 30),
      maximum: const Duration(minutes: 5),
    );
    final quietWindow = Duration(
      milliseconds:
          pair.input.optionalInteger(
            'quietWindowMs',
            minimum: 50,
            maximum: 60000,
          ) ??
          500,
    );
    if (quietWindow > timeout) {
      throw const FormatException('UI quiet window exceeds wait timeout.');
    }
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _waitIdle.wait(
        CockpitWaitRemoteUiIdleRequest(
          sessionHandle: pair.binding.remoteHandle,
          quietWindow: quietWindow,
          timeout: timeout,
          includeNetworkIdle: pair.input.boolean(
            'includeNetworkIdle',
            defaultValue: false,
          ),
        ),
      ),
    );
    return _sanitizeSessionResult(result.toJson(), pair.binding, sanitizer);
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

  void _requireSessionGrant(
    CockpitWorkerSessionBinding session,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants, {
    bool allowUnleased = false,
  }) {
    if (allowUnleased && grants.isEmpty) return;
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
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

  Future<Map<String, Object?>> _sanitizeSessionResult(
    Map<String, Object?> result,
    CockpitWorkerSessionBinding session,
    CockpitWorkerResultSanitizer sanitizer,
  ) => sanitizer.sanitize(
    result,
    sessionId: session.sessionId,
    appId: session.appId,
    targetId: session.targetId,
  );
}

final class _SessionInput {
  const _SessionInput(this.input, this.binding);

  final CockpitWorkerApplicationInput input;
  final CockpitWorkerSessionBinding binding;
}
