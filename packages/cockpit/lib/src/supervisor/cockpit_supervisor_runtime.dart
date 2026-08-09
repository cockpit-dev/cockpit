import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_create_project_service.dart';
import '../application/cockpit_list_launch_targets_service.dart';
import '../application/cockpit_pub_dev_search_service.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../foundation/cockpit_storage_key.dart';
import '../foundation/cockpit_version.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../registry/cockpit_registry_models.dart';
import '../registry/cockpit_workspace_registry.dart';
import '../system_control/cockpit_system_control_service.dart';
import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_protocol_request.dart';
import '../worker/cockpit_worker_logger.dart';
import '../worker/cockpit_worker_value_reader.dart';
import 'cockpit_lease_support.dart';
import 'cockpit_lease_registry.dart';
import 'cockpit_local_worker_launcher.dart';
import 'cockpit_loopback_port_cleanup_probe.dart';
import 'cockpit_supervisor_resource_registry.dart';
import 'cockpit_supervisor_run_event_source.dart';
import 'cockpit_supervisor_run_admission_store.dart';
import 'cockpit_supervisor_run_projection.dart';
import 'cockpit_supervisor_authorization.dart';
import 'cockpit_supervisor_operation_catalog.dart';
import 'cockpit_supervisor_operation_schema.dart';
import 'cockpit_worker_pool.dart';
import 'cockpit_worker_resource_authority.dart';

const cockpitSupervisorEngineVersion = cockpitVersion;

final class CockpitDevelopmentArtifactFile {
  const CockpitDevelopmentArtifactFile({
    required this.artifactId,
    required this.mediaType,
    required this.file,
    required this.sizeBytes,
    required this.sha256,
  });

  final String artifactId;
  final String mediaType;
  final File file;
  final int sizeBytes;
  final String sha256;
}

final cockpitSupervisorFeatures = <CockpitFeatureDescriptor>[
  CockpitFeatureDescriptor(
    id: 'standaloneCaseRuns',
    revision: 1,
    minimumApiMinor: 0,
  ),
  CockpitFeatureDescriptor(id: 'suiteRuns', revision: 1, minimumApiMinor: 0),
  CockpitFeatureDescriptor(
    id: 'durableSuiteResume',
    revision: 1,
    minimumApiMinor: 0,
  ),
  CockpitFeatureDescriptor(
    id: 'automationTargets',
    revision: 1,
    minimumApiMinor: 0,
  ),
  CockpitFeatureDescriptor(
    id: 'durableRunEvents',
    revision: 1,
    minimumApiMinor: 0,
  ),
  CockpitFeatureDescriptor(
    id: 'digestCheckedArtifacts',
    revision: 1,
    minimumApiMinor: 0,
  ),
];

final class CockpitSupervisorRuntime
    implements CockpitSupervisorRunEventSource {
  CockpitSupervisorRuntime._({
    required this.resources,
    required this.workerPool,
    required this.authorization,
    required this.permissionHardener,
    required this.directorySyncer,
    required CockpitListLaunchTargetsService listLaunchTargets,
    required CockpitSystemControlService systemControl,
    required CockpitCreateProjectService createProject,
    required CockpitPubDevSearchService packageSearch,
    required this.runAdmissions,
    required Map<String, CockpitSupervisorRunProjection> projections,
  }) : _listLaunchTargets = listLaunchTargets,
       _systemControl = systemControl,
       _createProject = createProject,
       _packageSearch = packageSearch,
       _projections = projections;

  final CockpitSupervisorResourceRegistry resources;
  final CockpitWorkerPool workerPool;
  final CockpitSupervisorAuthorizationPolicy authorization;
  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final CockpitListLaunchTargetsService _listLaunchTargets;
  final CockpitSystemControlService _systemControl;
  final CockpitCreateProjectService _createProject;
  final CockpitPubDevSearchService _packageSearch;
  final CockpitSupervisorRunAdmissionStore runAdmissions;
  final Map<String, CockpitSupervisorRunProjection> _projections;
  final Map<String, Future<void>> _workerInitialization = {};
  final Map<String, _ActiveRun> _activeRuns = {};
  final Map<String, String> _validatedRunOwners = {};
  bool _draining = false;

  static Future<CockpitSupervisorRuntime> initialize({
    required CockpitHomeResolver homeResolver,
    required String dartExecutable,
    required String workerEntrypoint,
    String? packageConfigPath,
    CockpitSupervisorAuthorizationPolicy? authorization,
    CockpitWorkerLogger? logger,
  }) async {
    final policy = authorization ?? CockpitSupervisorAuthorizationPolicy();
    final hardener = homeResolver.platform == CockpitHostPlatform.windows
        ? const CockpitWindowsAclPermissionHardener()
        : const CockpitPosixPermissionHardener();
    final syncer = CockpitSystemDirectorySyncer(homeResolver.platform);
    final cleanup = _CockpitProductionCleanupProbeResolver();
    final resources = await CockpitSupervisorResourceRegistry.initialize(
      cleanupProbes: cleanup,
      homeResolver: homeResolver,
      permissionHardener: hardener,
      directorySyncer: syncer,
    );
    final runAdmissions = CockpitSupervisorRunAdmissionStore(
      paths: resources.identity.homePaths,
      permissionHardener: hardener,
      directorySyncer: syncer,
    );
    final projections = <String, CockpitSupervisorRunProjection>{};
    final ports = resources.createPortAllocator();
    late final CockpitLocalWorkerLauncher launcher;
    launcher = CockpitLocalWorkerLauncher(
      dartExecutable: dartExecutable,
      workerEntrypoint: workerEntrypoint,
      packageConfigPath: packageConfigPath,
      retentionIndex: CockpitScopedSupervisorRunRetentionIndex(
        resources.identity.references,
      ),
      permissionHardener: hardener,
      directorySyncer: syncer,
      logger: logger,
      eventExchangeFactory: (spec) => projections.putIfAbsent(
        spec.key.workspaceId,
        () => CockpitSupervisorRunProjection(
          workspaceId: spec.key.workspaceId,
          stateRoot: spec.stateRoot,
          permissionHardener: hardener,
          directorySyncer: syncer,
          retentionIndex: CockpitScopedSupervisorRunRetentionIndex(
            resources.identity.references,
          ),
          admissionValidator:
              ({required runId, required projectId, required caseId}) =>
                  runAdmissions.validateOwner(
                    workspaceId: spec.key.workspaceId,
                    runId: runId,
                    projectId: projectId,
                    caseId: caseId,
                  ),
        ),
      ),
      resourceAuthorityFactory: (spec, bridge) =>
          CockpitLeaseWorkerResourceAuthority(
            workspaceId: spec.key.workspaceId,
            leases: resources.leases,
            ports: ports,
            portBridge: bridge,
          ),
      environment: cockpitMinimumChildEnvironment(
        environment: <String, String>{
          for (final name in policy.allowedEnvironmentSecretNames)
            name: ?Platform.environment[name],
        },
      ),
      allowedEnvironmentSecretNames: policy.allowedEnvironmentSecretNames,
    );
    return CockpitSupervisorRuntime._(
      resources: resources,
      workerPool: CockpitWorkerPool(launcher: launcher),
      authorization: policy,
      permissionHardener: hardener,
      directorySyncer: syncer,
      listLaunchTargets: CockpitListLaunchTargetsService(),
      systemControl: CockpitSystemControlService(),
      createProject: CockpitCreateProjectService(),
      packageSearch: CockpitPubDevSearchService(),
      runAdmissions: runAdmissions,
      projections: projections,
    );
  }

  CockpitServerInfo serverInfo({
    required String instanceId,
    DateTime? startedAt,
  }) => CockpitServerInfo(
    instanceId: instanceId,
    apiVersion: CockpitApiVersion(major: 2, minor: 0),
    engineVersion: cockpitSupervisorEngineVersion,
    startedAt: startedAt ?? DateTime.now().toUtc(),
    features: cockpitSupervisorFeatures,
  );

  Future<CockpitCapabilityDocument> capabilities() async {
    final workspaces = await resources.identity.workspaces.list();
    final operations = <String, CockpitOperationDescriptor>{
      for (final descriptor
          in CockpitSupervisorOperationCatalog.supervisorOperations)
        descriptor.kind: descriptor,
    };
    for (final workspace in workspaces.where(
      (item) => item.state == CockpitWorkspaceState.active,
    )) {
      for (final descriptor in await workspaceOperations(
        workspace.workspaceId,
      )) {
        operations[descriptor.kind] = descriptor;
      }
    }
    return CockpitCapabilityDocument(
      apiVersion: CockpitApiVersion(major: 2, minor: 0),
      features: cockpitSupervisorFeatures,
      operations: operations.values.toList()
        ..sort((a, b) => a.kind.compareTo(b.kind)),
      resources: cockpitSupervisorResourceDescriptors,
    );
  }

  Future<List<CockpitRootResource>> roots() => resources.identity.roots.list();

  List<CockpitOperationDescriptor> supervisorOperations() =>
      CockpitSupervisorOperationCatalog.supervisorOperations;

  Map<String, Object?> operationSchema() =>
      CockpitSupervisorOperationSchema.document();

  Future<CockpitOperationResult> executeSupervisorOperation(
    CockpitOperationInvocation invocation,
  ) async {
    _requireAccepting();
    final metadata = CockpitSupervisorOperationCatalog.require(invocation.kind);
    final descriptor = metadata.descriptor;
    if (descriptor.scope == CockpitOperationScope.workspace) {
      throw _apiError(
        CockpitErrorCode.unsupportedOperation,
        CockpitErrorCategory.unsupported,
        'Workspace operations must use a workspace operation route.',
      );
    }
    if (descriptor.scope == CockpitOperationScope.supervisor &&
        (invocation.rootId != null || invocation.workspaceId != null)) {
      throw const FormatException('Supervisor operation scope mismatch.');
    }
    if (descriptor.scope == CockpitOperationScope.root &&
        (invocation.rootId == null || invocation.workspaceId != null)) {
      throw const FormatException('Root operation scope mismatch.');
    }
    if (descriptor.idempotency == CockpitIdempotencyBehavior.required &&
        invocation.idempotencyKey == null) {
      throw const FormatException('Operation requires an idempotency key.');
    }
    final submittedAt = DateTime.now().toUtc();
    final deadline = _resolveOperationDeadline(
      metadata.descriptor,
      submittedAt: submittedAt,
      requestedDeadline: invocation.deadline,
    );
    final normalizedInvocation = CockpitOperationInvocation(
      kind: invocation.kind,
      input: invocation.input,
      rootId: invocation.rootId,
      workspaceId: invocation.workspaceId,
      idempotencyKey: invocation.idempotencyKey,
      deadline: deadline,
      requiredFeatures: invocation.requiredFeatures,
    );
    authorization.authorizeOperation(metadata, normalizedInvocation);
    final outputFuture = switch (normalizedInvocation.kind) {
      'target.discover' => _discoverTargets(normalizedInvocation.input),
      'lease.list' => _listLeases(normalizedInvocation.input),
      'lease.recover' => _recoverLease(normalizedInvocation.input),
      'system.capabilities' => _systemCapabilities(normalizedInvocation.input),
      'system.diagnostics' => _systemDiagnostics(normalizedInvocation.input),
      'project.create' => _createRootProject(normalizedInvocation),
      'package.search' => _searchPackages(normalizedInvocation),
      _ => throw _apiError(
        CockpitErrorCode.unsupportedOperation,
        CockpitErrorCategory.unsupported,
        'Operation ${normalizedInvocation.kind} is not implemented.',
      ),
    };
    late final Map<String, Object?> output;
    try {
      output = await outputFuture.timeout(deadline.difference(submittedAt));
    } on TimeoutException {
      throw _apiError(
        'deadlineExceeded',
        CockpitErrorCategory.cancelled,
        'Operation deadline has expired.',
      );
    }
    final finishedAt = DateTime.now().toUtc();
    return CockpitOperationResult(
      operationId: 'op-${CockpitSecureTokenGenerator().nextIdToken()}',
      kind: invocation.kind,
      rootId: invocation.rootId,
      lifecycle: CockpitOperationLifecycle.completed,
      outcome: CockpitOperationOutcome.succeeded,
      submittedAt: submittedAt,
      startedAt: submittedAt,
      finishedAt: finishedAt,
      output: output,
    );
  }

  Future<Map<String, Object?>> _listLeases(Map<String, Object?> input) async {
    _requireKeys(input, const <String>{
      'workspaceId',
      'resourceKind',
      'resourceId',
      'state',
    });
    final workspaceId = _optionalString(input, 'workspaceId');
    final resourceKind = _optionalLeaseResourceKind(input, 'resourceKind');
    final resourceId = _optionalString(input, 'resourceId');
    final state = _optionalLeaseState(input, 'state');
    final leases = await resources.leases.list(
      workspaceId: workspaceId,
      resourceKind: resourceKind,
      resourceId: resourceId,
    );
    return <String, Object?>{
      'items': <Object?>[
        for (final lease in leases)
          if (state == null || lease.state == state) lease.toJson(),
      ],
    };
  }

  Future<Map<String, Object?>> _recoverLease(Map<String, Object?> input) async {
    _requireKeys(input, const <String>{
      'leaseId',
      'workspaceId',
      'resourceKind',
      'resourceId',
      'holderId',
      'forceRelease',
    });
    final leaseId = _requiredLeaseId(input, 'leaseId');
    final workspaceId = _requiredLeaseId(input, 'workspaceId');
    final resourceKind = _requiredLeaseResourceKind(input, 'resourceKind');
    final resourceId = _requiredString(input, 'resourceId');
    final holderId = _requiredLeaseId(input, 'holderId');
    if (resourceId.length > 512) {
      throw const FormatException('resourceId must not exceed 512 characters.');
    }
    final forceRelease = input['forceRelease'];
    if (forceRelease is! bool) {
      throw const FormatException('forceRelease must be a boolean.');
    }
    final before = await resources.leases.get(leaseId);
    _requireLeaseIdentity(
      before,
      workspaceId: workspaceId,
      resourceKind: resourceKind,
      resourceId: resourceId,
      holderId: holderId,
    );
    if (before.state != CockpitLeaseState.quarantined &&
        before.state != CockpitLeaseState.released) {
      throw CockpitLeaseException(
        code: 'leaseNotQuarantined',
        message: 'Only a quarantined lease can be recovered.',
        lease: before,
      );
    }
    if (before.state == CockpitLeaseState.quarantined) {
      await resources.leases.recoverResource(resourceKind, resourceId);
    }
    var after = await resources.leases.get(leaseId);
    final cleanupVerified = after.state == CockpitLeaseState.released;
    var forceReleased = false;
    if (!cleanupVerified && forceRelease) {
      final release = await resources.leases.forceReleaseQuarantined(
        leaseId: leaseId,
        workspaceId: workspaceId,
        resourceKind: resourceKind,
        resourceId: resourceId,
        holderId: holderId,
      );
      after = release.after;
      forceReleased = release.forceReleased;
    }
    return <String, Object?>{
      'leaseId': leaseId,
      'workspaceId': workspaceId,
      'resourceKind': resourceKind.name,
      'resourceId': resourceId,
      'holderId': holderId,
      'beforeState': before.state.name,
      'afterState': after.state.name,
      'cleanupVerified': cleanupVerified,
      'forceReleased': forceReleased,
      'lease': after.toJson(),
    };
  }

  Future<CockpitRootResource> registerRoot(CockpitRootRegistration request) {
    _requireAccepting();
    return resources.identity.roots.register(request.path);
  }

  Future<CockpitRetirementResult> removeRoot(
    String rootId,
    CockpitRootRemoval request,
  ) => resources.identity.roots.remove(
    rootId,
    policy: _removalPolicy(request.force),
    drainTimeout: Duration(milliseconds: request.drainTimeoutMs),
  );

  Future<List<CockpitWorkspaceResource>> workspaces() =>
      resources.identity.workspaces.list();

  Future<CockpitWorkspaceResource> registerWorkspace(
    CockpitWorkspaceRegistration request,
  ) async {
    _requireAccepting();
    final result = await resources.identity.workspaces.register(
      rootId: request.rootId,
      path: request.path,
    );
    return resources.identity.workspaces.get(result.workspaceId);
  }

  Future<CockpitWorkspaceResource> rebindWorkspace(
    String workspaceId,
    CockpitWorkspaceRebind request,
  ) async {
    _requireAccepting();
    final current = await resources.identity.workspaces.get(workspaceId);
    await resources.identity.workspaces.explicitRebind(
      workspaceId: workspaceId,
      expectedCheckoutId: request.expectedCheckoutId,
      rootId: current.rootId,
      path: request.path,
    );
    return resources.identity.workspaces.get(workspaceId);
  }

  Future<CockpitRetirementResult> removeWorkspace(
    String workspaceId,
    CockpitWorkspaceRemoval request,
  ) async {
    await workerPool.shutdownWorkspace(
      CockpitWorkspaceWorkerKey(
        workspaceId: workspaceId,
        engineVersion: cockpitSupervisorEngineVersion,
      ),
      grace: Duration(milliseconds: request.drainTimeoutMs),
      force: request.force,
    );
    return resources.identity.workspaces.unregister(
      workspaceId,
      policy: _removalPolicy(request.force),
      drainTimeout: Duration(milliseconds: request.drainTimeoutMs),
    );
  }

  Future<List<CockpitOperationDescriptor>> workspaceOperations(
    String workspaceId,
  ) async {
    final spec = await _workerSpec(workspaceId);
    await _initializeWorker(spec);
    final result = CockpitWorkerCapabilitiesResult.fromJson(
      await workerPool.call(
        spec,
        method: 'capabilities',
        idempotencyKey: 'capabilities-$workspaceId',
        deadline: _deadline(),
      ),
    );
    return CockpitSupervisorOperationCatalog.workspaceDescriptors(
      result.operationKinds,
    );
  }

  Future<CockpitOperationResult> executeWorkspaceOperation(
    String workspaceId,
    CockpitOperationInvocation invocation, {
    Duration? defaultTimeout,
  }) async {
    _requireAccepting();
    if (invocation.workspaceId != workspaceId || invocation.rootId != null) {
      throw const FormatException('Workspace operation scope mismatch.');
    }
    final metadata = CockpitSupervisorOperationCatalog.require(invocation.kind);
    if (metadata.descriptor.scope != CockpitOperationScope.workspace) {
      throw const FormatException('Workspace operation scope mismatch.');
    }
    authorization.authorizeOperation(metadata, invocation);
    if (invocation.kind == 'case.run' || invocation.kind == 'suite.run') {
      return _submitRunOperation(
        workspaceId,
        invocation,
        metadata.descriptor,
        defaultTimeout: defaultTimeout,
      );
    }
    final spec = await _workerSpec(workspaceId);
    await _initializeWorker(spec);
    final key =
        invocation.idempotencyKey?.value ??
        'ro-${CockpitSecureTokenGenerator().nextIdToken()}';
    final submittedAt = DateTime.now().toUtc();
    final deadline = _resolveOperationDeadline(
      metadata.descriptor,
      submittedAt: submittedAt,
      requestedDeadline: invocation.deadline,
      defaultTimeout: defaultTimeout,
    );
    final workerInvocation = CockpitOperationInvocation(
      kind: invocation.kind,
      input: invocation.input,
      rootId: invocation.rootId,
      workspaceId: invocation.workspaceId,
      idempotencyKey: invocation.idempotencyKey ?? CockpitIdempotencyKey(key),
      deadline: deadline,
      requiredFeatures: invocation.requiredFeatures,
    );
    final result = CockpitWorkerOperationResult.fromJson(
      await workerPool.call(
        spec,
        method: 'operation',
        idempotencyKey: key,
        deadline: deadline,
        params: <String, Object?>{'invocation': workerInvocation.toJson()},
      ),
    );
    return result.result;
  }

  Future<CockpitOperationResult> _submitRunOperation(
    String workspaceId,
    CockpitOperationInvocation invocation,
    CockpitOperationDescriptor descriptor, {
    required Duration? defaultTimeout,
  }) async {
    final submittedAt = DateTime.now().toUtc();
    _resolveOperationDeadline(
      descriptor,
      submittedAt: submittedAt,
      requestedDeadline: invocation.deadline,
      defaultTimeout: defaultTimeout,
    );
    final idempotencyKey = invocation.idempotencyKey;
    if (idempotencyKey == null) {
      throw const FormatException('Run operations require idempotency.');
    }
    final input = invocation.input;
    _requireKeys(input, const <String>{
      'source',
      'inputs',
      'targetId',
      'timeoutMs',
    });
    final rawInputs = input['inputs'];
    if (rawInputs != null &&
        (rawInputs is! Map<Object?, Object?> ||
            rawInputs.keys.any((key) => key is! String))) {
      throw const FormatException('inputs must be a JSON object.');
    }
    final submission = CockpitRunSubmission(
      workspaceId: workspaceId,
      source: CockpitRunSubmissionSource.fromJson(input['source']),
      idempotencyKey: idempotencyKey,
      inputs: rawInputs == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawInputs as Map<Object?, Object?>),
      targetId: _optionalString(input, 'targetId'),
      timeoutMs: _optionalInteger(
        input,
        'timeoutMs',
        minimum: 1,
        maximum: descriptor.maximumTimeoutMs,
      ),
      requiredFeatures: invocation.requiredFeatures,
    );
    final expectedKind =
        submission.source.documentKind == CockpitRunDocumentKind.testCase
        ? 'case.run'
        : 'suite.run';
    if (invocation.kind != expectedKind) {
      throw FormatException(
        '${invocation.kind} cannot submit a ${submission.source.documentKind.name} source.',
      );
    }
    final accepted = await submitRun(submission);
    final finishedAt = DateTime.now().toUtc();
    return CockpitOperationResult(
      operationId: 'op-${CockpitSecureTokenGenerator().nextResourceIdToken()}',
      kind: invocation.kind,
      workspaceId: workspaceId,
      lifecycle: CockpitOperationLifecycle.completed,
      outcome: CockpitOperationOutcome.succeeded,
      submittedAt: submittedAt,
      startedAt: submittedAt,
      finishedAt: finishedAt,
      output: accepted.toJson(),
    );
  }

  Future<CockpitDevelopmentArtifactFile> developmentArtifactFile(
    String workspaceId,
    String sessionId,
    String artifactId,
  ) async {
    workerId(workspaceId, r'$.workspaceId');
    workerId(sessionId, r'$.sessionId');
    workerId(artifactId, r'$.artifactId');
    final spec = await _workerSpec(workspaceId);
    await _initializeWorker(spec);
    final raw = await workerPool.call(
      spec,
      method: 'readSessionArtifact',
      idempotencyKey: 'read-session-artifact-$sessionId-$artifactId',
      deadline: _deadline(),
      params: <String, Object?>{
        'sessionId': sessionId,
        'artifactId': artifactId,
      },
    );
    final result = CockpitWorkerReadSessionArtifactResult.fromJson(raw);
    if (result.sessionId != sessionId || result.artifactId != artifactId) {
      throw const FormatException('Session artifact ownership is invalid.');
    }
    final stateRoot = p.normalize(
      await Directory(spec.stateRoot).resolveSymbolicLinks(),
    );
    final file = File(result.retainedPath);
    final canonicalFile = p.normalize(await file.resolveSymbolicLinks());
    if (!p.isWithin(stateRoot, canonicalFile)) {
      throw const FormatException('Session artifact escaped worker state.');
    }
    final stat = await File(canonicalFile).stat();
    final digest = (await sha256.bind(File(canonicalFile).openRead()).first)
        .toString();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != result.sizeBytes ||
        digest != result.sha256) {
      throw _apiError(
        CockpitErrorCode.evidenceFailed,
        CockpitErrorCategory.evidence,
        'Session artifact changed before it could be downloaded.',
      );
    }
    return CockpitDevelopmentArtifactFile(
      artifactId: result.artifactId,
      mediaType: result.mediaType,
      file: File(canonicalFile),
      sizeBytes: result.sizeBytes,
      sha256: result.sha256,
    );
  }

  Future<List<CockpitDocumentResource>> documents(
    String workspaceId, {
    CockpitIndexedDocumentKind? kind,
    String? relativePath,
  }) async {
    final documents = <CockpitDocumentResource>[];
    var offset = 0;
    var refreshIndex = true;
    while (true) {
      final page = await documentPage(
        workspaceId,
        kind: switch (kind) {
          null => null,
          CockpitIndexedDocumentKind.testCase => 'case',
          _ => kind.name,
        },
        relativePath: relativePath,
        offset: offset,
        limit: 100,
        refreshIndex: refreshIndex,
      );
      refreshIndex = false;
      documents.addAll(page.items);
      offset += page.items.length;
      if (offset >= page.totalCount) return documents;
      if (page.items.isEmpty) {
        throw const FormatException('Document page made no progress.');
      }
    }
  }

  Future<({List<CockpitDocumentResource> items, int totalCount})> documentPage(
    String workspaceId, {
    String? kind,
    String? relativePath,
    required int offset,
    required int limit,
    required bool refreshIndex,
  }) async {
    if (refreshIndex) {
      final indexed = await executeWorkspaceOperation(
        workspaceId,
        CockpitOperationInvocation(
          kind: 'document.index',
          workspaceId: workspaceId,
          input: const <String, Object?>{},
          idempotencyKey: CockpitIdempotencyKey(
            'document-index-${DateTime.now().microsecondsSinceEpoch}',
          ),
        ),
        defaultTimeout: const Duration(minutes: 5),
      );
      _throwIfWorkspaceOperationFailed(indexed);
      if (indexed.output?['documentCount'] is! int) {
        throw const FormatException('Invalid document index summary.');
      }
    }
    final listed = await executeWorkspaceOperation(
      workspaceId,
      CockpitOperationInvocation(
        kind: 'document.list',
        workspaceId: workspaceId,
        input: <String, Object?>{
          'kind': ?kind,
          'relativePath': ?relativePath,
          'offset': offset,
          'limit': limit,
        },
      ),
    );
    _throwIfWorkspaceOperationFailed(listed);
    final raw = listed.output?['documents'];
    if (raw is! List<Object?>) {
      throw const FormatException('Invalid document page.');
    }
    final totalCount = listed.output?['totalCount'];
    if (totalCount is! int || totalCount < raw.length) {
      throw const FormatException('Invalid document page count.');
    }
    return (
      items: <CockpitDocumentResource>[
        for (var index = 0; index < raw.length; index++)
          CockpitDocumentResource.fromJson(switch (raw[index]) {
            final Map<Object?, Object?> document => <String, Object?>{
              'documentId': document['documentId'],
              'workspaceId': document['workspaceId'],
              'relativePath': document['relativePath'],
              'sha256': document['sha256'],
              'modifiedAt': document['modifiedAt'],
              'kind': document['kind'],
              'authoredId': document['authoredId'],
              'title': document['title'],
              'cases': document['cases'],
            },
            _ => raw[index],
          }, path: '\$.documents[$index]'),
      ],
      totalCount: totalCount,
    );
  }

  Future<List<CockpitAutomationTargetResource>> targets(
    String workspaceId,
  ) async {
    final result = await executeWorkspaceOperation(
      workspaceId,
      CockpitOperationInvocation(kind: 'target.list', workspaceId: workspaceId),
    );
    _throwIfWorkspaceOperationFailed(result);
    final raw = result.output?['targets'];
    if (raw is! List<Object?>) {
      throw const FormatException('Invalid target index.');
    }
    return <CockpitAutomationTargetResource>[
      for (var index = 0; index < raw.length; index += 1)
        CockpitAutomationTargetResource.fromJson(
          raw[index],
          path: '\$.targets[$index]',
        ),
    ];
  }

  Future<CockpitAutomationTargetResource> target(
    String workspaceId,
    String targetId,
  ) async {
    final result = await executeWorkspaceOperation(
      workspaceId,
      CockpitOperationInvocation(
        kind: 'target.get',
        workspaceId: workspaceId,
        input: <String, Object?>{'targetId': targetId},
      ),
    );
    _throwIfWorkspaceOperationFailed(result);
    return CockpitAutomationTargetResource.fromJson(result.output?['target']);
  }

  Future<CockpitDocumentValidationResult> validateDocument(
    String workspaceId,
    CockpitDocumentValidationRequest request,
  ) async {
    final result = await executeWorkspaceOperation(
      workspaceId,
      CockpitOperationInvocation(
        kind: 'case.validate',
        workspaceId: workspaceId,
        input: request.toJson(),
      ),
    );
    _throwIfWorkspaceOperationFailed(result);
    return CockpitDocumentValidationResult.fromJson(result.output);
  }

  void _throwIfWorkspaceOperationFailed(CockpitOperationResult result) {
    if (result.outcome == CockpitOperationOutcome.succeeded) return;
    final failure = result.failure;
    if (failure != null) throw CockpitApiException(failure.primary);
    throw _apiError(
      CockpitErrorCode.internalError,
      CockpitErrorCategory.internal,
      'Workspace operation completed without a valid result.',
    );
  }

  Future<CockpitRunAccepted> submitRun(CockpitRunSubmission submission) async {
    _requireAccepting();
    final runKind =
        submission.source.documentKind == CockpitRunDocumentKind.testCase
        ? 'case.run'
        : 'suite.run';
    final descriptor = CockpitSupervisorOperationCatalog.require(
      runKind,
    ).descriptor;
    _runTimeout(submission, descriptor);
    final workspace = await _activeWorkspace(submission.workspaceId);
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(submission.toJson())))
        .toString();
    CockpitSupervisorRunAdmissionResult admitted;
    try {
      admitted = await runAdmissions.admit(
        workspaceId: submission.workspaceId,
        idempotencyKey: submission.idempotencyKey.value,
        fingerprint: fingerprint,
        projectId: workspace.projectId,
        documentKind: submission.source.documentKind,
        documentId: submission.source.documentId,
        sourceSha256: submission.source.sourceSha256,
        submittedAt: DateTime.now().toUtc(),
      );
    } on CockpitSupervisorRunAdmissionConflict {
      throw _apiError(
        'idempotencyConflict',
        CockpitErrorCategory.invalidInput,
        'Run idempotency key was reused with different input.',
      );
    }
    final admission = admitted.admission;
    final run = _ActiveRun(
      workspaceId: admission.workspaceId,
      projectId: admission.projectId,
      runId: admission.runId,
      documentKind: admission.documentKind,
      documentId: admission.documentId,
      sourceSha256: admission.sourceSha256,
      idempotencyKey: admission.idempotencyKey,
      fingerprint: admission.fingerprint,
      requestId: admission.requestId,
      submittedAt: admission.submittedAt,
    );
    final active = _activeRuns.putIfAbsent(run.runId, () => run);
    if (identical(active, run)) {
      unawaited(_dispatchRun(active, submission));
    }
    return active.accepted(
      replayed: admitted.replayed || !identical(active, run),
    );
  }

  Future<void> _dispatchRun(
    _ActiveRun run,
    CockpitRunSubmission submission,
  ) async {
    CockpitOperationResult? operation;
    Object? dispatchError;
    try {
      final existing = await _projection(
        run.workspaceId,
      ).readEvents(run.runId, afterSequence: 0, maximumEvents: 4096);
      if (_terminalEvent(existing.events) != null) {
        run.terminal = true;
        return;
      }
      final spec = await _workerSpec(run.workspaceId);
      await _initializeWorker(spec);
      final kind = run.documentKind == CockpitRunDocumentKind.testCase
          ? 'case.run'
          : 'suite.run';
      final descriptor = CockpitSupervisorOperationCatalog.require(
        kind,
      ).descriptor;
      final deadline = DateTime.now().toUtc().add(
        _runTimeout(submission, descriptor),
      );
      final invocation = CockpitOperationInvocation(
        kind: kind,
        workspaceId: run.workspaceId,
        idempotencyKey: submission.idempotencyKey,
        deadline: deadline,
        requiredFeatures: submission.requiredFeatures,
        input: submission.toJson(),
      );
      final call = workerPool.startCall(
        spec,
        method: 'operation',
        idempotencyKey: run.idempotencyKey,
        deadline: deadline,
        requestId: run.requestId,
        params: <String, Object?>{'invocation': invocation.toJson()},
      );
      if (call.requestId != run.requestId ||
          run.runId != 'rn-${call.requestId}') {
        throw StateError('Worker request identity diverged from admission.');
      }
      operation = CockpitWorkerOperationResult.fromJson(
        await call.result,
      ).result;
    } on Object catch (error) {
      dispatchError = error;
    }
    try {
      await _ensureTerminalRunTruth(
        run,
        operation: operation,
        dispatchError: dispatchError,
      );
    } finally {
      run.terminal = true;
    }
  }

  Future<void> _ensureTerminalRunTruth(
    _ActiveRun run, {
    required CockpitOperationResult? operation,
    required Object? dispatchError,
  }) async {
    final projection = _projection(run.workspaceId);
    final replay = await projection.readEvents(
      run.runId,
      afterSequence: 0,
      maximumEvents: 4096,
    );
    if (_terminalEvent(replay.events) != null) return;
    final operationFailure = operation?.failure;
    final outcome = operationFailure == null
        ? CockpitRunOutcome.interrupted
        : switch (operation!.outcome) {
            CockpitOperationOutcome.failed => CockpitRunOutcome.failed,
            CockpitOperationOutcome.blocked => CockpitRunOutcome.blocked,
            CockpitOperationOutcome.cancelled => CockpitRunOutcome.cancelled,
            CockpitOperationOutcome.interrupted =>
              CockpitRunOutcome.interrupted,
            CockpitOperationOutcome.succeeded ||
            null => CockpitRunOutcome.interrupted,
          };
    final failure =
        operationFailure ??
        CockpitFailure(
          primary: CockpitApiError(
            code: dispatchError == null
                ? CockpitErrorCode.internalError
                : 'workerUnavailable',
            category: dispatchError == null
                ? CockpitErrorCategory.internal
                : CockpitErrorCategory.environment,
            message: dispatchError == null
                ? 'Worker completed without publishing terminal run truth.'
                : 'Worker became unavailable before publishing run events.',
            retryable: dispatchError != null,
            responsibleLayer: CockpitResponsibleLayer.supervisor,
          ),
        );
    final sequence = replay.events.lastOrNull?.sequence ?? 0;
    final eventDigest = sha256
        .convert(utf8.encode('${run.runId}:${sequence + 1}:terminal'))
        .toString();
    final event = CockpitRunEvent(
      eventId: 'event_${eventDigest.substring(0, 32)}',
      sequence: sequence + 1,
      timestamp: DateTime.now().toUtc(),
      kind: 'run.${outcome.name}',
      entityKind: CockpitRunEventEntityKind.run,
      projectId: run.projectId,
      workspaceId: run.workspaceId,
      runId: run.runId,
      lifecycle: CockpitRunLifecycle.completed,
      outcome: outcome,
      stability: CockpitRunStability.unknown,
      failure: failure,
    );
    await projection.publish(
      CockpitWorkerPublishEventBatchRequest(
        protocolVersion: cockpitWorkerProtocolVersion,
        workspaceId: run.workspaceId,
        requestId: 'supervisor-terminal-${eventDigest.substring(0, 32)}',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
        idempotencyKey: 'terminal-${eventDigest.substring(0, 32)}',
        runId: run.runId,
        afterSequence: sequence,
        events: <CockpitRunEvent>[event],
      ),
    );
  }

  @override
  Future<CockpitRunResource> run(String runId) async {
    final active = _activeRuns[runId];
    final admission = await runAdmissions.findRun(runId);
    if (admission == null) {
      throw _apiError(
        CockpitErrorCode.notFound,
        CockpitErrorCategory.resource,
        'Run was not found.',
      );
    }
    if (active != null && active.workspaceId != admission.workspaceId) {
      throw StateError('Active run ownership conflicts with admission truth.');
    }
    final owner = admission.workspaceId;
    await _validateProjectedOwner(runId, owner);
    final replay = await _projection(
      owner,
    ).readEvents(runId, afterSequence: 0, maximumEvents: 4096);
    final events = replay.events;
    final terminal = events
        .where(
          (event) =>
              event.entityKind == CockpitRunEventEntityKind.run &&
              event.lifecycle == CockpitRunLifecycle.completed,
        )
        .lastOrNull;
    final running = events
        .where(
          (event) =>
              event.entityKind == CockpitRunEventEntityKind.run &&
              event.lifecycle == CockpitRunLifecycle.running,
        )
        .lastOrNull;
    final attempts = events
        .map((event) => event.attemptId)
        .whereType<String>()
        .toSet()
        .toList();
    return CockpitRunResource(
      projectId: admission.projectId,
      workspaceId: owner,
      runId: runId,
      documentKind: admission.documentKind,
      documentId: admission.documentId,
      sourceSha256: admission.sourceSha256,
      lifecycle:
          terminal?.lifecycle ??
          running?.lifecycle ??
          CockpitRunLifecycle.queued,
      outcome: terminal?.outcome,
      stability: terminal?.stability,
      submittedAt: admission.submittedAt,
      startedAt: running?.timestamp,
      finishedAt: terminal?.timestamp,
      caseIds: <String>{
        if (admission.documentKind == CockpitRunDocumentKind.testCase)
          admission.documentId,
        ...events.map((event) => event.caseId).whereType<String>(),
      },
      activeAttemptIds: terminal == null && attempts.isNotEmpty
          ? <String>[attempts.last]
          : const <String>[],
      failure: terminal?.failure,
    );
  }

  Future<CockpitRunCancellation> cancelRun(
    String runId,
    CockpitRunCancellationRequest request,
  ) async {
    final active = _activeRuns[runId];
    if (active == null || active.terminal) {
      await run(runId);
      return CockpitRunCancellation(
        runId: runId,
        requestedAt: DateTime.now().toUtc(),
        replayed: true,
      );
    }
    final spec = await _workerSpec(active.workspaceId);
    final result = await workerPool.cancel(
      spec,
      targetRequestId: active.requestId,
      deadline: _deadline(),
    );
    return CockpitRunCancellation(
      runId: runId,
      requestedAt: DateTime.now().toUtc(),
      replayed: result.alreadyTerminal,
    );
  }

  @override
  Future<CockpitSupervisorEventReplay> events(
    String runId,
    int afterSequence,
  ) async {
    final workspaceId = await _findRunOwner(runId);
    return _projection(
      workspaceId,
    ).readEvents(runId, afterSequence: afterSequence, maximumEvents: 4096);
  }

  Future<CockpitArtifactResource> artifact(
    String runId,
    String artifactId,
  ) async {
    final workspaceId = await _findRunOwner(runId);
    return _projection(workspaceId).requireArtifact(runId, artifactId);
  }

  Future<List<CockpitArtifactResource>> artifacts(String runId) async {
    final workspaceId = await _findRunOwner(runId);
    return _projection(workspaceId).artifacts(runId);
  }

  Future<({CockpitArtifactResource resource, File file})> artifactFile(
    String runId,
    String artifactId,
  ) async {
    final workspaceId = await _findRunOwner(runId);
    return _projection(workspaceId).requireArtifactFile(runId, artifactId);
  }

  Future<CockpitTestSuiteReport> report(String runId) async {
    final workspaceId = await _findRunOwner(runId);
    return _projection(workspaceId).requireSuiteReport(runId);
  }

  @override
  Future<int> sequenceForEventId(String runId, String eventId) async {
    final replay = await events(runId, 0);
    final matches = replay.events.where((event) => event.eventId == eventId);
    if (matches.isEmpty) {
      throw CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.staleReference,
          category: CockpitErrorCategory.invalidInput,
          message: 'Last-Event-ID is outside the retained replay window.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
          redactedDetails: <String, Object?>{
            if (replay.boundary != null)
              'replayBoundary': replay.boundary!.toJson(),
          },
        ),
      );
    }
    return matches.single.sequence;
  }

  Future<Map<String, Object?>> _discoverTargets(
    Map<String, Object?> input,
  ) async {
    _requireKeys(input, const <String>{'timeoutMs'});
    final timeoutMs = _optionalInteger(
      input,
      'timeoutMs',
      minimum: 1,
      maximum: 300000,
    );
    return (await _listLaunchTargets.list(
      timeout: timeoutMs == null ? null : Duration(milliseconds: timeoutMs),
    )).toJson();
  }

  Future<Map<String, Object?>> _systemCapabilities(
    Map<String, Object?> input,
  ) async {
    _requireKeys(input, const <String>{
      'platform',
      'deviceId',
      'appId',
      'processId',
      'metadata',
    });
    final platform = _requiredString(input, 'platform');
    final rawMetadata = input['metadata'];
    if (rawMetadata != null && rawMetadata is! Map<String, Object?>) {
      throw const FormatException('metadata must be a JSON object.');
    }
    final metadata = rawMetadata == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(rawMetadata as Map<String, Object?>);
    return (await _systemControl.describe(
      CockpitSystemControlDescribeRequest(
        platform: platform,
        deviceId: _optionalString(input, 'deviceId'),
        appId: _optionalString(input, 'appId'),
        processId: _optionalInteger(
          input,
          'processId',
          minimum: 1,
          maximum: 0x7fffffff,
        ),
        metadata: metadata,
      ),
    )).toJson();
  }

  Future<Map<String, Object?>> _systemDiagnostics(
    Map<String, Object?> input,
  ) async {
    _requireKeys(input, const <String>{});
    final roots = await resources.identity.roots.list();
    final workspaces = await resources.identity.workspaces.list();
    return <String, Object?>{
      'engineVersion': cockpitSupervisorEngineVersion,
      'draining': _draining,
      'rootCount': roots.length,
      'activeRootCount': roots
          .where((root) => root.state == CockpitRootState.active)
          .length,
      'workspaceCount': workspaces.length,
      'activeWorkspaceCount': workspaces
          .where((workspace) => workspace.state == CockpitWorkspaceState.active)
          .length,
      'activeWorkerCount': workerPool.activeKeys.length,
      'projectionCount': _projections.length,
      'permissionPolicy': permissionHardener.policy.name,
    };
  }

  Future<Map<String, Object?>> _createRootProject(
    CockpitOperationInvocation invocation,
  ) async {
    final root = await _activeRoot(invocation.rootId!);
    final input = invocation.input;
    _requireKeys(input, const <String>{
      'parentDirectory',
      'projectName',
      'template',
      'organization',
      'platforms',
      'timeoutMs',
    });
    final requestedParent = _optionalString(input, 'parentDirectory');
    final parentDirectory = await _confinedRootPath(
      root.canonicalPath,
      requestedParent ?? root.canonicalPath,
    );
    final projectName = _requiredString(input, 'projectName');
    if (!RegExp(r'^[a-z][a-z0-9_]{0,127}$').hasMatch(projectName)) {
      throw const FormatException('projectName is invalid.');
    }
    final template = switch (_requiredString(input, 'template')) {
      'dartCli' || 'dart_cli' => CockpitProjectTemplate.dartCli,
      'flutterApp' || 'flutter_app' => CockpitProjectTemplate.flutterApp,
      _ => throw const FormatException('template is invalid.'),
    };
    final platforms = _optionalStringList(input, 'platforms', maximum: 16);
    final timeoutMs = _optionalInteger(
      input,
      'timeoutMs',
      minimum: 1,
      maximum: 600000,
    );
    final result = await _createProject.create(
      CockpitCreateProjectRequest(
        parentDirectory: parentDirectory,
        projectName: projectName,
        template: template,
        organization: _optionalString(input, 'organization'),
        platforms: platforms,
        allowedRoots: <String>[root.canonicalPath],
        timeout: Duration(milliseconds: timeoutMs ?? 300000),
      ),
    );
    await _confinedRootPath(root.canonicalPath, result.projectDirectory);
    return result.toJson();
  }

  Future<Map<String, Object?>> _searchPackages(
    CockpitOperationInvocation invocation,
  ) async {
    await _activeRoot(invocation.rootId!);
    final input = invocation.input;
    _requireKeys(input, const <String>{'query', 'maxResults', 'timeoutMs'});
    final maxResults = _optionalInteger(
      input,
      'maxResults',
      minimum: 1,
      maximum: 50,
    );
    final timeoutMs = _optionalInteger(
      input,
      'timeoutMs',
      minimum: 1,
      maximum: 120000,
    );
    return (await _packageSearch.search(
      CockpitPubDevSearchRequest(
        query: _requiredString(input, 'query'),
        maxResults: maxResults ?? 5,
        timeout: Duration(milliseconds: timeoutMs ?? 20000),
      ),
    )).toJson();
  }

  Future<CockpitRootResource> _activeRoot(String rootId) async {
    final root = await resources.identity.roots.get(rootId);
    if (root.state != CockpitRootState.active) {
      throw _apiError(
        CockpitErrorCode.conflict,
        CockpitErrorCategory.resource,
        'Root $rootId is not active.',
      );
    }
    return root;
  }

  Future<String> _confinedRootPath(String rootPath, String candidate) async {
    if (!p.isAbsolute(candidate)) {
      throw const FormatException('Root-scoped paths must be absolute.');
    }
    final normalizedRoot = p.normalize(rootPath);
    final normalizedCandidate = p.normalize(candidate);
    if (normalizedCandidate != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedCandidate)) {
      throw _apiError(
        CockpitErrorCode.conflict,
        CockpitErrorCategory.resource,
        'Path is outside the selected root.',
      );
    }
    var existing = normalizedCandidate;
    final suffix = <String>[];
    while (!await FileSystemEntity.isDirectory(existing)) {
      if (await FileSystemEntity.isFile(existing)) {
        throw const FormatException(
          'Root-scoped parent path is not a directory.',
        );
      }
      final parent = p.dirname(existing);
      if (parent == existing) {
        throw const FormatException('Path has no existing ancestor.');
      }
      suffix.insert(0, p.basename(existing));
      existing = parent;
    }
    final resolvedAncestor = p.normalize(
      await Directory(existing).resolveSymbolicLinks(),
    );
    final resolvedCandidate = p.normalize(
      p.joinAll(<String>[resolvedAncestor, ...suffix]),
    );
    if (resolvedCandidate != normalizedRoot &&
        !p.isWithin(normalizedRoot, resolvedCandidate)) {
      throw _apiError(
        CockpitErrorCode.conflict,
        CockpitErrorCategory.resource,
        'Path resolves outside the selected root.',
      );
    }
    return resolvedCandidate;
  }

  Future<void> shutdown({required bool cancel, required bool emergency}) async {
    _draining = true;
    if (cancel) {
      for (final run in _activeRuns.values.toList()) {
        try {
          await workerPool.cancel(
            await _workerSpec(run.workspaceId),
            targetRequestId: run.requestId,
            deadline: _deadline(),
          );
        } on Object {
          // Forced pool shutdown below remains the final cleanup boundary.
        }
      }
    }
    await workerPool.close(
      grace: emergency ? Duration.zero : const Duration(seconds: 10),
    );
  }

  Future<CockpitWorkspaceWorkerSpec> _workerSpec(String workspaceId) async {
    final workspace = await _activeWorkspace(workspaceId);
    return CockpitWorkspaceWorkerSpec(
      key: CockpitWorkspaceWorkerKey(
        workspaceId: workspaceId,
        engineVersion: cockpitSupervisorEngineVersion,
      ),
      projectId: workspace.projectId,
      workspaceRoot: workspace.canonicalPath,
      stateRoot: _workspaceStateRoot(workspaceId),
      supportedFeatures: cockpitSupervisorFeatures.map((item) => item.id),
      authorizationMode: authorization.mode,
      allowedTargetEnvironments:
          authorization.effectiveAllowedTargetEnvironments,
      allowedSafetyEffects: authorization.effectiveAllowedSafetyEffects,
    );
  }

  Future<void> _initializeWorker(CockpitWorkspaceWorkerSpec spec) {
    final workspaceId = spec.key.workspaceId;
    return _workerInitialization.putIfAbsent(workspaceId, () async {
      try {
        await workerPool.call(
          spec,
          method: 'initialize',
          idempotencyKey: 'initialize-$workspaceId',
          deadline: _workerInitializationDeadline(),
          params: <String, Object?>{
            'engineVersion': spec.key.engineVersion,
            'workspaceRoot': spec.workspaceRoot,
            'supportedFeatures': spec.supportedFeatures,
          },
        );
      } on Object {
        _workerInitialization.remove(workspaceId);
        rethrow;
      }
    });
  }

  Future<CockpitWorkspaceResource> _activeWorkspace(String workspaceId) async {
    final workspace = await resources.identity.workspaces.get(workspaceId);
    final root = await resources.identity.roots.get(workspace.rootId);
    if (workspace.state != CockpitWorkspaceState.active ||
        root.state != CockpitRootState.active) {
      throw const FormatException('Workspace does not grant active authority.');
    }
    return workspace;
  }

  CockpitSupervisorRunProjection _projection(String workspaceId) =>
      _projections.putIfAbsent(
        workspaceId,
        () => CockpitSupervisorRunProjection(
          workspaceId: workspaceId,
          stateRoot: _workspaceStateRoot(workspaceId),
          permissionHardener: permissionHardener,
          directorySyncer: directorySyncer,
          retentionIndex: CockpitScopedSupervisorRunRetentionIndex(
            resources.identity.references,
          ),
          admissionValidator:
              ({required runId, required projectId, required caseId}) =>
                  runAdmissions.validateOwner(
                    workspaceId: workspaceId,
                    runId: runId,
                    projectId: projectId,
                    caseId: caseId,
                  ),
        ),
      );

  String _workspaceStateRoot(String workspaceId) => p.join(
    resources.identity.homePaths.home,
    'w',
    cockpitStorageKey(workspaceId),
  );

  Future<String> _findRunOwner(String runId) async {
    final validatedOwner = _validatedRunOwners[runId];
    if (validatedOwner != null) return validatedOwner;

    final admission = await runAdmissions.findRun(runId);
    if (admission == null) {
      throw _apiError(
        CockpitErrorCode.notFound,
        CockpitErrorCategory.resource,
        'Run was not found.',
      );
    }
    await _validateProjectedOwner(runId, admission.workspaceId);
    _validatedRunOwners[runId] = admission.workspaceId;
    return admission.workspaceId;
  }

  Future<void> _validateProjectedOwner(
    String runId,
    String admittedOwner,
  ) async {
    for (final workspace in await resources.identity.workspaces.list()) {
      if (await _projection(workspace.workspaceId).containsRun(runId)) {
        if (workspace.workspaceId != admittedOwner) {
          throw StateError(
            'Projected run ownership conflicts with admission truth.',
          );
        }
      }
    }
  }

  CockpitRunEvent? _terminalEvent(Iterable<CockpitRunEvent> events) => events
      .where(
        (event) =>
            event.entityKind == CockpitRunEventEntityKind.run &&
            event.lifecycle == CockpitRunLifecycle.completed,
      )
      .lastOrNull;

  void _requireAccepting() {
    if (_draining) throw const FormatException('Supervisor is draining.');
  }
}

final class _ActiveRun {
  _ActiveRun({
    required this.workspaceId,
    required this.projectId,
    required this.runId,
    required this.documentKind,
    required this.documentId,
    required this.sourceSha256,
    required this.idempotencyKey,
    required this.fingerprint,
    required this.requestId,
    required this.submittedAt,
  });
  final String workspaceId;
  final String projectId;
  final String runId;
  final CockpitRunDocumentKind documentKind;
  final String documentId;
  final String sourceSha256;
  final String idempotencyKey;
  final String fingerprint;
  final String requestId;
  final DateTime submittedAt;
  bool terminal = false;
  CockpitRunAccepted accepted({required bool replayed}) => CockpitRunAccepted(
    workspaceId: workspaceId,
    runId: runId,
    statusUrl: '/api/v2/runs/$runId',
    eventsUrl: '/api/v2/runs/$runId/events',
    submittedAt: submittedAt,
    replayed: replayed,
  );
}

final class _CockpitProductionCleanupProbeResolver
    implements CockpitLeaseCleanupProbeResolver {
  const _CockpitProductionCleanupProbeResolver();
  @override
  CockpitLeaseCleanupProbe resolve(CockpitLeaseResourceKind resourceKind) =>
      resourceKind == CockpitLeaseResourceKind.forwardedPort
      ? const CockpitLoopbackPortCleanupProbe()
      : const _CockpitLogicalResourceCleanupProbe();
}

final class _CockpitLogicalResourceCleanupProbe
    implements CockpitLeaseCleanupProbe {
  const _CockpitLogicalResourceCleanupProbe();

  @override
  Future<CockpitLeaseCleanupResult> cleanupAndVerify(
    CockpitLeaseCleanupContext context,
  ) async => const CockpitLeaseCleanupResult.restored();
}

CockpitRemovalPolicy _removalPolicy(bool force) =>
    force ? CockpitRemovalPolicy.force : CockpitRemovalPolicy.drain;
DateTime _resolveOperationDeadline(
  CockpitOperationDescriptor descriptor, {
  required DateTime submittedAt,
  required DateTime? requestedDeadline,
  Duration? defaultTimeout,
}) {
  final maximum = Duration(milliseconds: descriptor.maximumTimeoutMs);
  final fallback =
      defaultTimeout ?? Duration(milliseconds: descriptor.defaultTimeoutMs);
  if (fallback <= Duration.zero || fallback > maximum) {
    throw ArgumentError.value(defaultTimeout, 'defaultTimeout');
  }
  final deadline = requestedDeadline?.toUtc() ?? submittedAt.add(fallback);
  final requested = deadline.difference(submittedAt);
  if (requested <= Duration.zero) {
    throw const FormatException('Operation deadline has expired.');
  }
  if (requested > maximum) {
    throw FormatException(
      'Operation timeout exceeds the ${descriptor.maximumTimeoutMs} ms '
      'maximum for ${descriptor.kind}.',
    );
  }
  return deadline;
}

Duration _runTimeout(
  CockpitRunSubmission submission,
  CockpitOperationDescriptor descriptor,
) {
  final timeoutMs = submission.timeoutMs ?? descriptor.defaultTimeoutMs;
  if (timeoutMs > descriptor.maximumTimeoutMs) {
    throw FormatException(
      'Run timeout exceeds the ${descriptor.maximumTimeoutMs} ms maximum '
      'for ${descriptor.kind}.',
    );
  }
  return Duration(milliseconds: timeoutMs);
}

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 30));

DateTime _workerInitializationDeadline() =>
    DateTime.now().toUtc().add(const Duration(minutes: 2));

void _requireKeys(Map<String, Object?> input, Set<String> allowed) {
  final unknown = input.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown operation input field ${unknown.first}.');
  }
}

String _requiredString(Map<String, Object?> input, String key) {
  final value = _optionalString(input, key);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

String? _optionalString(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > 32768) {
    throw FormatException('$key must be a non-empty bounded string.');
  }
  return value;
}

String _requiredLeaseId(Map<String, Object?> input, String key) {
  final value = _requiredString(input, key);
  if (!cockpitIsValidSupervisorId(value)) {
    throw FormatException('$key must be a valid Cockpit identifier.');
  }
  return value;
}

CockpitLeaseResourceKind _requiredLeaseResourceKind(
  Map<String, Object?> input,
  String key,
) {
  final value = _optionalLeaseResourceKind(input, key);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

CockpitLeaseResourceKind? _optionalLeaseResourceKind(
  Map<String, Object?> input,
  String key,
) {
  final value = _optionalString(input, key);
  if (value == null) return null;
  return CockpitLeaseResourceKind.values
          .where((candidate) => candidate.name == value)
          .firstOrNull ??
      (throw FormatException('$key contains an unknown resource kind.'));
}

CockpitLeaseState? _optionalLeaseState(Map<String, Object?> input, String key) {
  final value = _optionalString(input, key);
  if (value == null) return null;
  return CockpitLeaseState.values
          .where((candidate) => candidate.name == value)
          .firstOrNull ??
      (throw FormatException('$key contains an unknown lease state.'));
}

void _requireLeaseIdentity(
  CockpitLeaseResource lease, {
  required String workspaceId,
  required CockpitLeaseResourceKind resourceKind,
  required String resourceId,
  required String holderId,
}) {
  if (lease.workspaceId != workspaceId ||
      lease.resourceKind != resourceKind ||
      lease.resourceId != resourceId ||
      lease.holderId != holderId) {
    throw CockpitLeaseException(
      code: 'leaseIdentityMismatch',
      message: 'Lease identity does not match the quarantined resource.',
      lease: lease,
    );
  }
}

int? _optionalInteger(
  Map<String, Object?> input,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final value = input[key];
  if (value == null) return null;
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('$key must be between $minimum and $maximum.');
  }
  return value;
}

List<String> _optionalStringList(
  Map<String, Object?> input,
  String key, {
  required int maximum,
}) {
  final value = input[key];
  if (value == null) return const <String>[];
  if (value is! List<Object?> || value.length > maximum) {
    throw FormatException('$key must be a bounded string list.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty || item.length > 128) {
      throw FormatException('$key must contain non-empty bounded strings.');
    }
    result.add(item);
  }
  if (result.toSet().length != result.length) {
    throw FormatException('$key must not contain duplicates.');
  }
  return List<String>.unmodifiable(result);
}

CockpitApiException _apiError(
  String code,
  CockpitErrorCategory category,
  String message,
) => CockpitApiException(
  CockpitApiError(
    code: code,
    category: category,
    message: message,
    retryable: false,
    responsibleLayer: CockpitResponsibleLayer.supervisor,
  ),
);

final List<CockpitResourceDescriptor> cockpitSupervisorResourceDescriptors =
    List<CockpitResourceDescriptor>.unmodifiable(<CockpitResourceDescriptor>[
      CockpitResourceDescriptor(
        kind: 'supervisor.roots',
        scope: CockpitOperationScope.supervisor,
        uriTemplate: '/api/v2/roots',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'supervisor.workspaces',
        scope: CockpitOperationScope.supervisor,
        uriTemplate: '/api/v2/workspaces',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'supervisor.operations',
        scope: CockpitOperationScope.supervisor,
        uriTemplate: '/api/v2/operations',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'supervisor.operationSchema',
        scope: CockpitOperationScope.supervisor,
        uriTemplate: '/api/v2/operations/schema',
        mediaType: 'application/schema+json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.documents',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/documents',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.targets',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/targets',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.operations',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/operations',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.target',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/targets/{targetId}',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.cases',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/cases',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'workspace.runs',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/workspaces/{workspaceId}/runs',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'run.events',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/runs/{runId}/events',
        mediaType: 'text/event-stream',
      ),
      CockpitResourceDescriptor(
        kind: 'run.artifacts',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/runs/{runId}/artifacts',
        mediaType: 'application/json',
      ),
      CockpitResourceDescriptor(
        kind: 'run.artifact',
        scope: CockpitOperationScope.workspace,
        uriTemplate: '/api/v2/runs/{runId}/artifacts/{artifactId}',
        mediaType: 'application/octet-stream',
      ),
    ]);
