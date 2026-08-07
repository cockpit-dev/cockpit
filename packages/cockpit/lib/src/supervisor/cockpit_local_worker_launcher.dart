import 'dart:async';
import 'dart:io';

import '../foundation/cockpit_home.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../worker/cockpit_json_rpc_peer.dart';
import '../worker/cockpit_worker_logger.dart';
import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_server.dart';
import '../worker/cockpit_worker_value_reader.dart';
import 'cockpit_supervisor_run_projection.dart';
import 'cockpit_supervisor_worker_endpoint.dart';
import 'cockpit_supervisor_port_ownership_inspector.dart';
import 'cockpit_supervisor_worker_port_bridge.dart';
import 'cockpit_worker_pool.dart';
import 'cockpit_worker_resource_authority.dart';

typedef CockpitSupervisorEventExchangeFactory =
    CockpitWorkerEventExchange Function(CockpitWorkspaceWorkerSpec spec);
typedef CockpitSupervisorResourceAuthorityFactory =
    CockpitSupervisorWorkerResourceAuthority Function(
      CockpitWorkspaceWorkerSpec spec,
      CockpitSupervisorWorkerPortBridge portBridge,
    );

final class CockpitLocalWorkerLauncher
    implements CockpitWorkspaceWorkerLauncher {
  CockpitLocalWorkerLauncher({
    required this.dartExecutable,
    required this.workerEntrypoint,
    this.packageConfigPath,
    required CockpitSupervisorRunRetentionIndex retentionIndex,
    required CockpitSupervisorResourceAuthorityFactory resourceAuthorityFactory,
    CockpitSupervisorEventExchangeFactory? eventExchangeFactory,
    CockpitPermissionHardener? permissionHardener,
    CockpitDirectorySyncer? directorySyncer,
    CockpitProcessManager processManager = const LocalCockpitProcessManager(),
    CockpitWorkerLogger? logger,
    CockpitTokenGenerator? tokenGenerator,
    Map<String, String>? environment,
    Iterable<String> allowedEnvironmentSecretNames = const <String>[],
  }) : _eventExchangeFactory = eventExchangeFactory,
       _resourceAuthorityFactory = resourceAuthorityFactory,
       _retentionIndex = retentionIndex,
       _permissionHardener = permissionHardener ?? _systemPermissionHardener(),
       _directorySyncer = directorySyncer ?? _systemDirectorySyncer(),
       _processManager = processManager,
       _logger = logger ?? CockpitWorkerLogger(),
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _environment = Map<String, String>.unmodifiable(
         environment ?? cockpitMinimumChildEnvironment(),
       ),
       _allowedEnvironmentSecretNames = List<String>.unmodifiable(
         allowedEnvironmentSecretNames,
       ) {
    if (dartExecutable.isEmpty || workerEntrypoint.isEmpty) {
      throw ArgumentError('Worker executable paths cannot be empty.');
    }
    final uniqueSecretNames = <String>{};
    for (final name in _allowedEnvironmentSecretNames) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$').hasMatch(name) ||
          !uniqueSecretNames.add(name) ||
          !_environment.containsKey(name)) {
        throw ArgumentError(
          'Allowed worker environment secrets must be unique and present.',
        );
      }
    }
  }

  final String dartExecutable;
  final String workerEntrypoint;
  final String? packageConfigPath;
  final CockpitSupervisorEventExchangeFactory? _eventExchangeFactory;
  final CockpitSupervisorResourceAuthorityFactory _resourceAuthorityFactory;
  final CockpitSupervisorRunRetentionIndex _retentionIndex;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitProcessManager _processManager;
  final CockpitWorkerLogger _logger;
  final CockpitTokenGenerator _tokenGenerator;
  final Map<String, String> _environment;
  final List<String> _allowedEnvironmentSecretNames;

  @override
  Future<CockpitWorkspaceWorkerConnection> launch(
    CockpitWorkspaceWorkerSpec spec,
  ) async {
    final workerOwnerId = 'wk-${_tokenGenerator.nextResourceIdToken()}';
    final processStartIdentity = 'pc-${_tokenGenerator.nextResourceIdToken()}';
    final events =
        _eventExchangeFactory?.call(spec) ??
        CockpitSupervisorRunProjection(
          workspaceId: spec.key.workspaceId,
          stateRoot: spec.stateRoot,
          permissionHardener: _permissionHardener,
          directorySyncer: _directorySyncer,
          retentionIndex: _retentionIndex,
        );
    if (events case final CockpitSupervisorRunProjection projection) {
      await projection.resumePendingRetentionReleases();
    }
    final workerTemporaryDirectory =
        await (Platform.isWindows ? Directory.systemTemp : Directory('/tmp'))
            .createTemp('cockpit-worker-');
    try {
      await _permissionHardener.hardenDirectory(workerTemporaryDirectory);
    } on Object {
      await workerTemporaryDirectory.delete(recursive: true);
      rethrow;
    }
    late final Process process;
    try {
      process = await _processManager.start(
        dartExecutable,
        <String>[
          if (packageConfigPath != null) '--packages=$packageConfigPath',
          workerEntrypoint,
          '--workspace-id=${spec.key.workspaceId}',
          '--project-id=${spec.projectId}',
          '--engine-version=${spec.key.engineVersion}',
          '--workspace-root=${spec.workspaceRoot}',
          '--state-root=${spec.stateRoot}',
          '--worker-owner-id=$workerOwnerId',
          '--process-start-identity=$processStartIdentity',
          '--auth=${spec.authorizationMode.name}',
          for (final feature in spec.supportedFeatures) '--feature=$feature',
          for (final name in _allowedEnvironmentSecretNames)
            '--allow-env-secret=$name',
          for (final environment in spec.allowedTargetEnvironments)
            '--allow-target-environment=${environment.name}',
          for (final effect in spec.allowedSafetyEffects)
            '--allow-safety-effect=${effect.name}',
        ],
        workingDirectory: spec.workspaceRoot,
        environment: <String, String>{
          ..._environment,
          'TMPDIR': workerTemporaryDirectory.path,
          'TMP': workerTemporaryDirectory.path,
          'TEMP': workerTemporaryDirectory.path,
        },
        includeParentEnvironment: false,
      );
    } on Object {
      await workerTemporaryDirectory.delete(recursive: true);
      rethrow;
    }
    late final CockpitSystemSupervisorPortOwnershipInspector ownershipInspector;
    try {
      ownershipInspector =
          await CockpitSystemSupervisorPortOwnershipInspector.capture(
            workerProcessId: process.pid,
          );
    } on Object {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      await workerTemporaryDirectory.delete(recursive: true);
      rethrow;
    }
    late final CockpitJsonRpcPeer peer;
    final portBridge = CockpitSupervisorWorkerPortBridge(
      workspaceId: spec.key.workspaceId,
      workerOwnerId: workerOwnerId,
      workerProcessId: process.pid,
      processStartIdentity: processStartIdentity,
      ownershipInspector: ownershipInspector,
      call: ({required method, required params, required deadline}) =>
          peer.call(method: method, params: params, deadline: deadline),
    );
    final endpoint = CockpitSupervisorWorkerEndpoint(
      workspaceId: spec.key.workspaceId,
      events: events,
      artifacts: events is CockpitWorkerArtifactExchange
          ? events as CockpitWorkerArtifactExchange
          : null,
      resourceAuthority: _resourceAuthorityFactory(spec, portBridge),
    );
    peer = CockpitJsonRpcPeer(
      input: process.stdout,
      output: process.stdin,
      requestHandler: endpoint.handle,
      cancellationGrace: const Duration(minutes: 5),
      onProtocolError: (error, stackTrace) {
        _logger.log(
          'error',
          'Worker protocol error.',
          fields: <String, Object?>{
            'workspaceId': spec.key.workspaceId,
            'errorType': error.runtimeType.toString(),
            'error': '$error',
            'stackTrace': '$stackTrace',
          },
        );
      },
    );
    final replayConnectionIdentity = Object();
    endpoint.bindReplayClient(
      connectionIdentity: replayConnectionIdentity,
      replay: ({required runId, required afterSequence, required deadline}) {
        if (peer.isClosed) {
          throw const CockpitJsonRpcPeerClosedException();
        }
        return peer
            .call(
              method: 'replayEvents',
              params: <String, Object?>{
                'protocolVersion': cockpitWorkerProtocolVersion,
                'workspaceId': spec.key.workspaceId,
                'idempotencyKey': 'er-${_tokenGenerator.nextResourceIdToken()}',
                'runId': runId,
                'afterSequence': afterSequence,
              },
              deadline: deadline,
            )
            .then(CockpitWorkerReplayEventsResult.fromJson);
      },
    );
    unawaited(
      peer.done.whenComplete(
        () => endpoint.unbindReplayClient(replayConnectionIdentity),
      ),
    );
    peer.start();
    final stderrSubscription = process.stderr
        .transform(const CockpitBoundedUtf8LineFramer())
        .listen((line) {
          _logger.log(
            'info',
            'Workspace worker stderr.',
            fields: <String, Object?>{
              'workspaceId': spec.key.workspaceId,
              'processId': process.pid,
              'line': line.text,
              'truncated': line.truncated,
            },
          );
        });
    return _LocalWorkerConnection(
      process: process,
      processManager: _processManager,
      peer: peer,
      stderrSubscription: stderrSubscription,
      temporaryDirectory: workerTemporaryDirectory,
      logger: _logger,
      workspaceId: spec.key.workspaceId,
    );
  }
}

final class _LocalWorkerConnection implements CockpitWorkspaceWorkerConnection {
  _LocalWorkerConnection({
    required Process process,
    required CockpitProcessManager processManager,
    required CockpitJsonRpcPeer peer,
    required StreamSubscription<CockpitBoundedLogLine> stderrSubscription,
    required Directory temporaryDirectory,
    required CockpitWorkerLogger logger,
    required String workspaceId,
  }) : _process = process,
       _processManager = processManager,
       _peer = peer,
       _stderrSubscription = stderrSubscription,
       _temporaryDirectory = temporaryDirectory,
       _logger = logger,
       _workspaceId = workspaceId;

  final Process _process;
  final CockpitProcessManager _processManager;
  final CockpitJsonRpcPeer _peer;
  final StreamSubscription<CockpitBoundedLogLine> _stderrSubscription;
  final Directory _temporaryDirectory;
  final CockpitWorkerLogger _logger;
  final String _workspaceId;
  var _terminated = false;
  Future<void>? _termination;

  @override
  int get processId => _process.pid;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool get isClosed => _terminated || _peer.isClosed;

  @override
  Future<Object?> call({
    required String method,
    required Map<String, Object?> params,
    required DateTime deadline,
    String? requestId,
  }) => _peer.call(
    method: method,
    params: params,
    deadline: deadline,
    requestId: requestId,
  );

  @override
  Future<void> terminate({required bool force}) async {
    if (_terminated) return;
    final active = _termination;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _terminate(force: force).whenComplete(() {
      if (identical(_termination, operation)) _termination = null;
    });
    _termination = operation;
    return operation;
  }

  Future<void> _terminate({required bool force}) async {
    if (!force) {
      await _peer.close();
      if (await _waitForExit()) {
        await _stderrSubscription.cancel();
        await _cleanupTemporaryDirectory();
        _terminated = true;
        return;
      }
    }
    final processManager = _processManager;
    if (_process.pid > 1 &&
        processManager is LocalCockpitProcessManager &&
        processManager.usesHostProcessManager) {
      await cockpitKillLocalProcessDescendants(_process.pid);
    }
    _process.kill(ProcessSignal.sigkill);
    if (!await _waitForExit()) {
      throw const CockpitWorkerPoolException(
        'workerTerminationFailed',
        'Worker process did not exit after a forced termination request.',
      );
    }
    // The worker is already confirmed dead. Closing stdin releases the
    // Dart Process handle so the supervisor isolate can terminate cleanly.
    await _peer.close();
    await _stderrSubscription.cancel();
    await _cleanupTemporaryDirectory();
    _terminated = true;
  }

  Future<void> _cleanupTemporaryDirectory() async {
    try {
      if (await _temporaryDirectory.exists()) {
        await _temporaryDirectory.delete(recursive: true);
      }
    } on Object catch (error) {
      _logger.log(
        'warning',
        'Workspace worker temporary directory cleanup failed.',
        fields: <String, Object?>{
          'workspaceId': _workspaceId,
          'error': '$error',
        },
      );
    }
  }

  Future<bool> _waitForExit() => _process.exitCode
      .then((_) => true)
      .timeout(const Duration(seconds: 2), onTimeout: () => false);
}

CockpitPermissionHardener _systemPermissionHardener() => Platform.isWindows
    ? const CockpitWindowsAclPermissionHardener()
    : const CockpitPosixPermissionHardener();

CockpitDirectorySyncer _systemDirectorySyncer() => CockpitSystemDirectorySyncer(
  Platform.isWindows
      ? CockpitHostPlatform.windows
      : Platform.isMacOS
      ? CockpitHostPlatform.macos
      : CockpitHostPlatform.linux,
);
