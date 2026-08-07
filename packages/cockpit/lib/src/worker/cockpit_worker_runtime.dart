import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../development/cockpit_development_session_status.dart';
import '../development/cockpit_vm_network_profiler.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../test/cockpit_test_safety_policy.dart';
import 'cockpit_case_run_adapter.dart';
import 'cockpit_suite_run_adapter.dart';
import 'cockpit_worker_case_completion.dart';
import 'cockpit_worker_case_run_store.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_retained_workspace_application_backend.dart';
import 'cockpit_rpc_forwarded_port_handoff.dart';
import 'cockpit_rpc_resource_authority_client.dart';
import 'cockpit_worker_application_support.dart';
import 'cockpit_worker_artifact_publisher.dart';
import 'cockpit_worker_artifact_retainer.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_development_session_runtime.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_worker_operation_journal.dart';
import 'cockpit_worker_operation_router.dart';
import 'cockpit_worker_process_manager.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_run_event_store.dart';
import 'cockpit_worker_secret_resolver.dart';
import 'cockpit_worker_suite_run_store.dart';
import 'cockpit_worker_server.dart';
import 'cockpit_worker_target_registration_dispatcher.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_application_adapters.dart';
import 'cockpit_workspace_operation_registry.dart';
import 'cockpit_workspace_tooling_adapters.dart';

final class CockpitWorkerRuntimeConfiguration {
  CockpitWorkerRuntimeConfiguration({
    required this.workspaceId,
    required this.projectId,
    required this.engineVersion,
    required this.workspaceRoot,
    required this.stateRoot,
    required this.workerOwnerId,
    required this.processStartIdentity,
    required this.authorizationMode,
    required Iterable<String> supportedFeatures,
    required Iterable<String> allowedEnvironmentSecretNames,
    Iterable<CockpitTestTargetEnvironment> allowedTargetEnvironments =
        const <CockpitTestTargetEnvironment>[],
    Iterable<CockpitTestSafetyEffect> allowedSafetyEffects =
        const <CockpitTestSafetyEffect>[],
  }) : supportedFeatures = List<String>.unmodifiable(supportedFeatures),
       allowedEnvironmentSecretNames = List<String>.unmodifiable(
         allowedEnvironmentSecretNames,
       ),
       allowedTargetEnvironments =
           Set<CockpitTestTargetEnvironment>.unmodifiable(
             allowedTargetEnvironments,
           ),
       allowedSafetyEffects = Set<CockpitTestSafetyEffect>.unmodifiable(
         allowedSafetyEffects,
       ) {
    workerId(workspaceId, r'$.workspaceId');
    workerId(projectId, r'$.projectId');
    workerId(engineVersion, r'$.engineVersion');
    workerId(workerOwnerId, r'$.workerOwnerId');
    workerString(processStartIdentity, r'$.processStartIdentity', maximum: 512);
    _validateAbsolutePath(workspaceRoot, 'workspaceRoot');
    _validateAbsolutePath(stateRoot, 'stateRoot');
    _validateUniqueIds(this.supportedFeatures, 'supportedFeatures');
    _validateEnvironmentNames(this.allowedEnvironmentSecretNames);
    final yolo = authorizationMode == CockpitAuthorizationMode.yolo;
    if (yolo &&
        (this.allowedTargetEnvironments.length !=
                CockpitTestTargetEnvironment.values.length ||
            !this.allowedTargetEnvironments.containsAll(
              CockpitTestTargetEnvironment.values,
            ) ||
            this.allowedSafetyEffects.length !=
                CockpitTestSafetyEffect.values.length ||
            !this.allowedSafetyEffects.containsAll(
              CockpitTestSafetyEffect.values,
            ))) {
      throw const FormatException(
        'Worker authorization capabilities do not match its mode.',
      );
    }
  }

  factory CockpitWorkerRuntimeConfiguration.parse(List<String> arguments) {
    final parser = ArgParser(allowTrailingOptions: false)
      ..addOption('workspace-id', mandatory: true)
      ..addOption('project-id', mandatory: true)
      ..addOption('engine-version', mandatory: true)
      ..addOption('workspace-root', mandatory: true)
      ..addOption('state-root', mandatory: true)
      ..addOption('worker-owner-id', mandatory: true)
      ..addOption('process-start-identity', mandatory: true)
      ..addOption(
        'auth',
        mandatory: true,
        allowed: CockpitAuthorizationMode.values.map((value) => value.name),
      )
      ..addMultiOption('feature')
      ..addMultiOption('allow-env-secret')
      ..addMultiOption('allow-target-environment')
      ..addMultiOption('allow-safety-effect');
    final parsed = parser.parse(arguments);
    return CockpitWorkerRuntimeConfiguration(
      workspaceId: parsed.option('workspace-id')!,
      projectId: parsed.option('project-id')!,
      engineVersion: parsed.option('engine-version')!,
      workspaceRoot: parsed.option('workspace-root')!,
      stateRoot: parsed.option('state-root')!,
      workerOwnerId: parsed.option('worker-owner-id')!,
      processStartIdentity: parsed.option('process-start-identity')!,
      authorizationMode: CockpitAuthorizationMode.values.byName(
        parsed.option('auth')!,
      ),
      supportedFeatures: parsed.multiOption('feature'),
      allowedEnvironmentSecretNames: parsed.multiOption('allow-env-secret'),
      allowedTargetEnvironments: _parseEnumAllowlist(
        parsed.multiOption('allow-target-environment'),
        CockpitTestTargetEnvironment.values,
        'allow-target-environment',
      ),
      allowedSafetyEffects: _parseEnumAllowlist(
        parsed.multiOption('allow-safety-effect'),
        CockpitTestSafetyEffect.values,
        'allow-safety-effect',
      ),
    );
  }

  final String workspaceId;
  final String projectId;
  final String engineVersion;
  final String workspaceRoot;
  final String stateRoot;
  final String workerOwnerId;
  final String processStartIdentity;
  final CockpitAuthorizationMode authorizationMode;
  final List<String> supportedFeatures;
  final List<String> allowedEnvironmentSecretNames;
  final Set<CockpitTestTargetEnvironment> allowedTargetEnvironments;
  final Set<CockpitTestSafetyEffect> allowedSafetyEffects;
}

final class CockpitWorkerRuntime {
  CockpitWorkerRuntime({
    required this.configuration,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
    Map<String, String>? environment,
    CockpitPermissionHardener? permissionHardener,
    CockpitDirectorySyncer? directorySyncer,
    CockpitWorkerLogger? logger,
    CockpitWorkerCaseCompletionObserver? completionObserver,
  }) : _input = input ?? stdin,
       _output = output ?? stdout,
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _permissionHardener = permissionHardener ?? _systemPermissionHardener(),
       _directorySyncer = directorySyncer ?? _systemDirectorySyncer(),
       _logger = logger ?? CockpitWorkerLogger(),
       _completionObserver = completionObserver;

  final CockpitWorkerRuntimeConfiguration configuration;
  final Stream<List<int>> _input;
  final StreamSink<List<int>> _output;
  final Map<String, String> _environment;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitWorkerLogger _logger;
  final CockpitWorkerCaseCompletionObserver? _completionObserver;

  Future<void> run() async {
    final roots = await _prepareRoots();
    final caseRunStore = CockpitWorkerCaseRunStore.file(
      workspaceId: configuration.workspaceId,
      path: p.join(roots.stateRoot, 'case_runs'),
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
      completionObserver: _completionObserver,
    );
    final operationJournal = CockpitFileWorkerOperationJournal(
      path: p.join(roots.stateRoot, 'operations'),
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
      recoveryPolicies: const <String, CockpitWorkerOperationRecoveryPolicy>{
        'case.run': CockpitWorkerOperationRecoveryPolicy.retryPrepared,
        'suite.run': CockpitWorkerOperationRecoveryPolicy.retryPrepared,
      },
    );
    final networkProfiler = CockpitVmNetworkProfiler();
    final developmentRuntime = CockpitWorkerDevelopmentSessionRuntime(
      networkProfiler: networkProfiler,
      logger: (message) => _logger.log(
        'info',
        'Development session runtime.',
        fields: <String, Object?>{
          'workspaceId': configuration.workspaceId,
          'detail': message,
        },
      ),
    );
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: configuration.workspaceId,
      workspaceRoot: roots.workspaceRoot,
      stateRoot: roots.stateRoot,
      stateStore: CockpitFileWorkerRuntimeStateStore(
        root: p.join(roots.stateRoot, 'runtime'),
        permissionHardener: _permissionHardener,
        directorySyncer: _directorySyncer,
      ),
      runOwnershipAuthority: caseRunStore,
      developmentSessionAborter: developmentRuntime.forceStop,
      developmentSessionRestarter: (handle) async =>
          (await developmentRuntime.reload(
            handle,
            CockpitDevelopmentReloadMode.hotRestart,
          )).handle,
    );
    final documents = CockpitWorkerDocumentIndex(
      workspaceId: configuration.workspaceId,
      workspaceRoot: roots.workspaceRoot,
      stateRoot: roots.stateRoot,
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
    );
    late CockpitWorkerServer server;
    final peer = CockpitJsonRpcPeer(
      input: _input,
      output: _output,
      requestHandler: (request, cancellation) =>
          server.handle(request, cancellation),
      cancellationGrace: const Duration(minutes: 5),
      onProtocolError: (error, stackTrace) => _logger.log(
        'error',
        'Worker protocol error.',
        fields: <String, Object?>{
          'workspaceId': configuration.workspaceId,
          'errorType': error.runtimeType.toString(),
          'error': '$error',
          'stackTrace': '$stackTrace',
        },
      ),
    );
    final resourceAuthority = CockpitRpcResourceAuthorityClient(
      workspaceId: configuration.workspaceId,
      peer: peer,
    );
    final portHandoff = CockpitRpcWorkerForwardedPortHandoff(
      workspaceId: configuration.workspaceId,
      peer: peer,
      logger: _logger,
    );
    final eventStore = CockpitWorkerRunEventStore(
      projectId: configuration.projectId,
      workspaceId: configuration.workspaceId,
      stateRoot: roots.stateRoot,
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
      redactor: (value) => _logger.redactor.redact(value),
      completionObserver: _completionObserver,
      publisher: CockpitRpcWorkerEventPublisher(
        workspaceId: configuration.workspaceId,
        peer: peer,
      ),
    );
    await eventStore.initialize();
    await caseRunStore.recover(
      now: DateTime.now().toUtc(),
      reconcileCompletion: eventStore.reconcileCompletionIntent,
      beforeInterrupt: (attempt) => eventStore.recoverInterruptedAttempt(
        runId: attempt.runId,
        caseId: attempt.caseId,
        attemptId: attempt.attemptId,
      ),
    );
    await operationJournal.recover(now: DateTime.now().toUtc());
    final childProcessManager = CockpitWorkerProcessManager();
    final artifactRetainer = CockpitWorkerArtifactRetainer(
      stateRoot: roots.stateRoot,
      producerRoot: roots.producerRoot,
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
    );
    final artifactPublisher = CockpitDurableWorkerArtifactPublisher(
      workspaceId: configuration.workspaceId,
      stateRoot: roots.stateRoot,
      peer: peer,
      events: eventStore,
      artifactRetainer: artifactRetainer,
      permissionHardener: _permissionHardener,
      directorySyncer: _directorySyncer,
      redactor: (value) => _logger.redactor.redact(value),
    );
    final resultSanitizer = CockpitWorkerResultSanitizer(
      workspaceRoot: roots.workspaceRoot,
      registry: registry,
      artifactRetainer: artifactRetainer,
    );
    final backend = CockpitRetainedWorkspaceApplicationBackend(
      workspaceId: configuration.workspaceId,
      workspaceRoot: roots.workspaceRoot,
      registry: registry,
      documents: documents,
      producerRoot: roots.producerRoot,
      portHandoff: portHandoff,
      developmentRuntime: developmentRuntime,
      processManager: childProcessManager,
      resultSanitizer: resultSanitizer,
      networkProfiler: networkProfiler,
    );
    final secretResolver = _secretResolver(_logger.redactor);
    final caseAdapters = CockpitCaseRunAdapterFactory(
      workspaceId: configuration.workspaceId,
      projectId: configuration.projectId,
      engineVersion: configuration.engineVersion,
      authorizationMode: configuration.authorizationMode,
      runStateRoot: roots.stateRoot,
      caseIndex: documents,
      sessions: registry,
      secretResolver: secretResolver,
      safetyPolicy: CockpitConfiguredSafetyPolicy(
        environments: configuration.allowedTargetEnvironments,
        allowedEffects: configuration.allowedSafetyEffects,
      ),
      redactor: _logger.redactor,
      runStore: caseRunStore,
      eventStore: eventStore,
      artifactPublisher: artifactPublisher,
      resultSanitizer:
          (value, {required runId, required committedBundleRoot}) =>
              resultSanitizer.sanitize(
                value,
                runId: runId,
                committedBundleRoot: committedBundleRoot,
              ),
    );
    final suiteAdapters = CockpitSuiteRunAdapterFactory(
      workspaceId: configuration.workspaceId,
      projectId: configuration.projectId,
      engineVersion: configuration.engineVersion,
      authorizationMode: configuration.authorizationMode,
      runStateRoot: roots.stateRoot,
      documents: documents,
      sessions: registry,
      resourceAuthority: resourceAuthority,
      secretResolver: secretResolver,
      safetyPolicy: CockpitConfiguredSafetyPolicy(
        environments: configuration.allowedTargetEnvironments,
        allowedEffects: configuration.allowedSafetyEffects,
      ),
      redactor: _logger.redactor,
      logger: _logger,
      eventStore: eventStore,
      runStore: CockpitWorkerSuiteRunStore(
        workspaceId: configuration.workspaceId,
        path: p.join(roots.stateRoot, 'suite_runs', 'runs.json'),
        permissionHardener: _permissionHardener,
        directorySyncer: _directorySyncer,
      ),
      artifactPublisher: artifactPublisher,
    );
    final targetRegistration = CockpitWorkerTargetRegistrationDispatcher(
      workspaceId: configuration.workspaceId,
      workspaceRoot: roots.workspaceRoot,
      registrar: registry,
      documents: documents,
      operationJournal: operationJournal,
      terminateUnsafeWorker: peer.close,
    );
    final adapters = <CockpitWorkspaceOperationAdapter>[
      documents.operationAdapter(),
      documents.listOperationAdapter(),
      targetRegistration.workspaceAdapter(),
      ...CockpitWorkspaceToolingAdapters(
        workspaceId: configuration.workspaceId,
        workspaceRoot: roots.workspaceRoot,
        documents: documents,
        processManager: childProcessManager,
      ).create(),
      ...CockpitWorkspaceApplicationAdapters(
        workspaceId: configuration.workspaceId,
        backend: backend,
        resourceResolver: registry,
      ).create(),
      caseAdapters.validationAdapter(),
      caseAdapters.runAdapter(),
      suiteAdapters.runAdapter(),
    ];
    final operations = CockpitWorkspaceOperationRegistry(
      workspaceId: configuration.workspaceId,
      workspaceRoot: roots.workspaceRoot,
      adapters: adapters,
      resourceAuthority: resourceAuthority,
      operationJournal: operationJournal,
      terminateUnsafeWorker: peer.close,
      redactor: _logger.redactor,
      logger: _logger,
    );
    final router = CockpitWorkerOperationRouter(
      workspaceOperations: operations,
      internalDispatchers: <CockpitWorkerInternalOperationDispatcher>[
        portHandoff,
        targetRegistration,
      ],
    );
    Future<void> shutdownRuntime() async {
      await developmentRuntime.dispose().timeout(const Duration(seconds: 3));
    }

    server = CockpitWorkerServer(
      workspaceId: configuration.workspaceId,
      engineVersion: configuration.engineVersion,
      workspaceRoot: roots.workspaceRoot,
      supportedFeatures: configuration.supportedFeatures,
      operations: router,
      events: eventStore,
      artifacts: registry,
      onInitialized: () async {
        await eventStore.resume();
        unawaited(
          Future<void>.delayed(Duration.zero)
              .then((_) => artifactPublisher.resume())
              .catchError((Object error, StackTrace stackTrace) {
                _logger.log(
                  'error',
                  'Worker artifact recovery failed.',
                  fields: <String, Object?>{
                    'workspaceId': configuration.workspaceId,
                    'errorType': error.runtimeType.toString(),
                    'error': '$error',
                    'stackTrace': '$stackTrace',
                  },
                );
              }),
        );
      },
      onShutdown: shutdownRuntime,
    );
    server.bindPeer(peer);
    _logger.log(
      'info',
      'Workspace worker started.',
      fields: <String, Object?>{
        'workspaceId': configuration.workspaceId,
        'engineVersion': configuration.engineVersion,
        'operationCount': operations.operationKinds.length,
      },
    );
    peer.start();
    try {
      await peer.done;
    } finally {
      await shutdownRuntime();
      _logger.log(
        'info',
        'Workspace worker stopped.',
        fields: <String, Object?>{'workspaceId': configuration.workspaceId},
      );
    }
  }

  CockpitAllowedWorkerSecretResolver _secretResolver(
    CockpitWorkerLogRedactor redactor,
  ) {
    final allowedNames = configuration.allowedEnvironmentSecretNames;
    return CockpitAllowedWorkerSecretResolver(
      providers: <CockpitWorkerSecretProvider>[
        if (allowedNames.isNotEmpty)
          CockpitEnvironmentSecretProvider(
            allowedNames: allowedNames,
            allowAllNames: false,
            environment: _environment,
          ),
      ],
      allowedProviderIds: allowedNames.isEmpty
          ? const <String>[]
          : const <String>['env'],
      redactor: redactor,
    );
  }

  Future<_PreparedWorkerRoots> _prepareRoots() async {
    final workspaceDirectory = Directory(configuration.workspaceRoot);
    if (!await workspaceDirectory.exists()) {
      throw const FileSystemException('Worker workspace root is unavailable.');
    }
    final canonicalWorkspace = p.normalize(
      await workspaceDirectory.resolveSymbolicLinks(),
    );
    if (!p.equals(
      canonicalWorkspace,
      p.normalize(configuration.workspaceRoot),
    )) {
      throw const FileSystemException(
        'Worker workspace root must be canonical.',
      );
    }
    final stateDirectory = Directory(configuration.stateRoot);
    await stateDirectory.create(recursive: true);
    await _permissionHardener.hardenDirectory(stateDirectory);
    final canonicalState = p.normalize(
      await stateDirectory.resolveSymbolicLinks(),
    );
    if (!p.equals(canonicalState, p.normalize(configuration.stateRoot))) {
      throw const FileSystemException('Worker state root must be canonical.');
    }
    if (p.equals(canonicalWorkspace, canonicalState) ||
        p.isWithin(canonicalWorkspace, canonicalState) ||
        p.isWithin(canonicalState, canonicalWorkspace)) {
      throw const FileSystemException(
        'Worker state root must be separate from the workspace root.',
      );
    }
    final producerDirectory = await Directory(
      p.join(canonicalState, 'producer_artifacts'),
    ).create(recursive: true);
    await _permissionHardener.hardenDirectory(producerDirectory);
    final producerRoot = p.normalize(
      await producerDirectory.resolveSymbolicLinks(),
    );
    final temporaryDirectory = await Directory(
      p.join(producerRoot, 'tmp'),
    ).create(recursive: true);
    await _permissionHardener.hardenDirectory(temporaryDirectory);
    return _PreparedWorkerRoots(
      canonicalWorkspace,
      canonicalState,
      producerRoot,
    );
  }
}

Future<int> runCockpitWorker(
  List<String> arguments, {
  Stream<List<int>>? input,
  StreamSink<List<int>>? output,
  Map<String, String>? environment,
  CockpitPermissionHardener? permissionHardener,
  CockpitDirectorySyncer? directorySyncer,
  CockpitWorkerLogger? logger,
  CockpitWorkerCaseCompletionObserver? completionObserver,
}) async {
  final effectiveLogger = logger ?? CockpitWorkerLogger();
  try {
    final configuration = CockpitWorkerRuntimeConfiguration.parse(arguments);
    await CockpitWorkerRuntime(
      configuration: configuration,
      input: input,
      output: output,
      environment: environment,
      permissionHardener: permissionHardener,
      directorySyncer: directorySyncer,
      logger: effectiveLogger,
      completionObserver: completionObserver,
    ).run();
    return 0;
  } on Object catch (error) {
    effectiveLogger.log(
      'error',
      'Workspace worker failed.',
      fields: <String, Object?>{'error': '$error'},
    );
    return 1;
  }
}

final class _PreparedWorkerRoots {
  const _PreparedWorkerRoots(
    this.workspaceRoot,
    this.stateRoot,
    this.producerRoot,
  );

  final String workspaceRoot;
  final String stateRoot;
  final String producerRoot;
}

void _validateAbsolutePath(String value, String name) {
  if (value.isEmpty || !p.isAbsolute(value) || p.normalize(value) != value) {
    throw FormatException('$name must be an absolute normalized path.');
  }
}

void _validateUniqueIds(Iterable<String> values, String name) {
  final unique = <String>{};
  for (final value in values) {
    workerId(value, '\$.$name[]');
    if (!unique.add(value)) throw FormatException('$name contains duplicates.');
  }
}

void _validateEnvironmentNames(Iterable<String> values) {
  final unique = <String>{};
  final pattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$');
  for (final value in values) {
    if (!pattern.hasMatch(value) || !unique.add(value)) {
      throw const FormatException(
        'Allowed environment secret names must be unique and valid.',
      );
    }
  }
}

Set<T> _parseEnumAllowlist<T extends Enum>(
  Iterable<String> values,
  List<T> allowed,
  String option,
) {
  final result = <T>{};
  for (final value in values) {
    final matches = allowed.where((candidate) => candidate.name == value);
    if (matches.length != 1 || !result.add(matches.single)) {
      throw FormatException(
        '--$option contains an invalid or duplicate value.',
      );
    }
  }
  return Set<T>.unmodifiable(result);
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
