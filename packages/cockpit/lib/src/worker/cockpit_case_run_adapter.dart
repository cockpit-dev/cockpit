import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_ids.dart';
import '../application/cockpit_application_service_exception.dart';
import '../adapters/cockpit_automation_adapter.dart';
import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../runner/cockpit_case_execution_control.dart';
import '../runner/cockpit_case_runner.dart';
import '../test/cockpit_test_document_compiler.dart';
import '../test/cockpit_test_action_lowerer.dart';
import '../test/cockpit_test_execution_plan.dart';
import '../test/cockpit_test_safety_policy.dart';
import '../test/cockpit_test_secret_resolver.dart';
import '../test/cockpit_test_variable_binder.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_artifact_publisher.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_case_run_store.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_worker_run_event_store.dart';
import 'cockpit_workspace_operation_registry.dart';

abstract interface class CockpitWorkerCaseIndex {
  Future<CockpitCompiledTestCase> resolve(
    CockpitIndexedCaseReference reference,
  );
}

final class CockpitWorkerHealthySession {
  const CockpitWorkerHealthySession({
    required this.sessionId,
    required this.targetId,
    required this.deviceResourceId,
    required this.resourceId,
    required this.environment,
    required this.automationAdapter,
    required this.healthCheck,
    this.captureAdapter,
    this.recordingAdapter,
    this.lowerer = const CockpitTestActionLowerer(),
    this.isolate,
    this.forceAbort,
  });

  final String sessionId;
  final String targetId;
  final String deviceResourceId;
  final String resourceId;
  final CockpitTestTargetEnvironment environment;
  final CockpitAutomationAdapter automationAdapter;
  final CockpitCaptureAdapter? captureAdapter;
  final CockpitRecordingAdapter? recordingAdapter;
  final CockpitTestActionLowerer lowerer;
  final Future<bool> Function() healthCheck;
  final Future<void> Function(
    CockpitTestSuiteIsolation isolation,
    DateTime deadline,
  )?
  isolate;
  final Future<void> Function()? forceAbort;
}

abstract interface class CockpitWorkerSessionProvider {
  Future<CockpitWorkerHealthySession> selectHealthySession({
    required String? targetId,
    required CockpitTestTargetRequirements requirements,
    String? preferredResourceId,
  });
}

typedef CockpitWorkerCaseResultSanitizer =
    Future<Map<String, Object?>> Function(
      Map<String, Object?> value, {
      required String runId,
      required String? committedBundleRoot,
    });

final class CockpitCaseAttemptRedactionScanner {
  CockpitCaseAttemptRedactionScanner({
    required String runStateRoot,
    required CockpitWorkerLogRedactor redactor,
    DateTime? deadline,
    bool Function()? isCancelled,
    DateTime Function()? utcNow,
    this.maximumEntities = 100000,
    this.maximumDepth = 128,
    this.maximumFileBytes = 16 * 1024 * 1024 * 1024,
    this.maximumAggregateBytes = 64 * 1024 * 1024 * 1024,
  }) : _runStateRoot = p.normalize(runStateRoot),
       _redactor = redactor,
       _deadline = deadline?.toUtc(),
       _isCancelled = isCancelled,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    if (!p.isAbsolute(runStateRoot) ||
        p.normalize(runStateRoot) != runStateRoot) {
      throw const FormatException(
        'Case attempt redaction root must be absolute and normalized.',
      );
    }
    if (maximumEntities <= 0 ||
        maximumDepth <= 0 ||
        maximumFileBytes <= 0 ||
        maximumAggregateBytes <= 0) {
      throw const FormatException(
        'Case attempt redaction budgets must be positive.',
      );
    }
  }

  final String _runStateRoot;
  final CockpitWorkerLogRedactor _redactor;
  final DateTime? _deadline;
  final bool Function()? _isCancelled;
  final DateTime Function() _utcNow;
  final int maximumEntities;
  final int maximumDepth;
  final int maximumFileBytes;
  final int maximumAggregateBytes;

  String get _runsRoot => p.join(_runStateRoot, 'runs');

  Future<CockpitTestError?> validateForPublication(String stagingRoot) async {
    try {
      if (!await _containsSensitiveData(stagingRoot)) return null;
      return CockpitTestError(
        code: CockpitTestErrorCode.bundlePublicationFailed,
        message: 'Case output contained a plaintext secret.',
        details: const <String, Object?>{'reason': 'plaintextSecretRejected'},
      );
    } on Object {
      return CockpitTestError(
        code: CockpitTestErrorCode.bundlePublicationFailed,
        message: 'Case output could not be verified for safe publication.',
        details: const <String, Object?>{'reason': 'caseOutputRedactionFailed'},
      );
    }
  }

  Future<void> verify(String attemptRoot) => _verify(attemptRoot);

  Future<void> _verifyAfterSuccessfulRun(
    String attemptRoot,
    CockpitTestAttemptResult result,
  ) => _verify(attemptRoot, committedBundleRoot: result.bundlePath);

  Future<void> _verify(
    String attemptRoot, {
    String? committedBundleRoot,
  }) async {
    late final bool containsSensitiveData;
    try {
      containsSensitiveData = await _containsSensitiveData(
        attemptRoot,
        committedBundleRoot: committedBundleRoot,
      );
    } on Object {
      await _deleteAndReject(
        attemptRoot,
        code: 'caseOutputRedactionFailed',
        message: 'Case output could not be verified for safe persistence.',
      );
    }
    if (containsSensitiveData) {
      await _deleteAndReject(
        attemptRoot,
        code: 'plaintextSecretRejected',
        message: 'Case output contained a plaintext secret.',
      );
    }
  }

  Future<bool> _containsSensitiveData(
    String attemptRoot, {
    String? committedBundleRoot,
  }) async {
    _checkOperation();
    final root = p.normalize(attemptRoot);
    if (!p.isAbsolute(attemptRoot) ||
        root != attemptRoot ||
        !p.isWithin(_runsRoot, root)) {
      throw FileSystemException(
        'Case attempt root escapes its persistence authority.',
        attemptRoot,
      );
    }
    await _validateCanonicalEntity(
      root,
      expectedType: FileSystemEntityType.directory,
      authorityRoot: root,
      allowAuthorityRoot: true,
    );
    final skipRoot = await _validatedSkipRoot(root, committedBundleRoot);
    if (_redactor.containsSensitiveValue(p.relative(root, from: _runsRoot))) {
      return true;
    }

    final byteScanner = _redactor.sensitiveByteScanner();
    final budget = _CockpitCaseAttemptScanBudget();
    final pending = <_CockpitCaseAttemptDirectory>[
      _CockpitCaseAttemptDirectory(path: root, depth: 0),
    ];
    var skippedCommittedBundle = skipRoot == null;
    while (pending.isNotEmpty) {
      _checkOperation();
      final current = pending.removeLast();
      await for (final entity in Directory(
        current.path,
      ).list(followLinks: false)) {
        _checkOperation();
        budget.entities += 1;
        if (budget.entities > maximumEntities) {
          throw const FormatException(
            'Case output entity scan budget was exceeded.',
          );
        }
        final depth = current.depth + 1;
        if (depth > maximumDepth) {
          throw const FormatException(
            'Case output directory depth budget was exceeded.',
          );
        }
        final path = p.normalize(entity.path);
        if (!p.isAbsolute(entity.path) ||
            path != entity.path ||
            !p.isWithin(root, path)) {
          throw FileSystemException(
            'Case output entity escapes its attempt root.',
            entity.path,
          );
        }
        final relativePath = p.relative(path, from: root);
        if (p.isAbsolute(relativePath) ||
            relativePath == '..' ||
            relativePath.startsWith('../')) {
          throw FileSystemException(
            'Case output entity has an invalid relative name.',
            entity.path,
          );
        }
        if (_redactor.containsSensitiveValue(relativePath)) return true;

        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await _validateCanonicalEntity(
            path,
            expectedType: FileSystemEntityType.directory,
            authorityRoot: root,
          );
          if (skipRoot != null && p.equals(path, skipRoot)) {
            skippedCommittedBundle = true;
            continue;
          }
          pending.add(_CockpitCaseAttemptDirectory(path: path, depth: depth));
          continue;
        }
        if (type != FileSystemEntityType.file) {
          throw FileSystemException(
            'Case output contains an unsupported filesystem entity.',
            path,
          );
        }
        await _validateCanonicalEntity(
          path,
          expectedType: FileSystemEntityType.file,
          authorityRoot: root,
        );
        if (await byteScanner.contains(_scanFile(File(path), budget))) {
          return true;
        }
        await _validateCanonicalEntity(
          path,
          expectedType: FileSystemEntityType.file,
          authorityRoot: root,
        );
      }
    }
    if (!skippedCommittedBundle) {
      throw FileSystemException(
        'Committed case bundle was not found in its attempt root.',
        skipRoot,
      );
    }
    _checkOperation();
    await _validateCanonicalEntity(
      root,
      expectedType: FileSystemEntityType.directory,
      authorityRoot: root,
      allowAuthorityRoot: true,
    );
    return false;
  }

  Future<String?> _validatedSkipRoot(
    String attemptRoot,
    String? committedBundleRoot,
  ) async {
    if (committedBundleRoot == null) return null;
    _checkOperation();
    final normalized = p.normalize(committedBundleRoot);
    if (!p.isAbsolute(committedBundleRoot) ||
        normalized != committedBundleRoot ||
        !p.isWithin(attemptRoot, normalized)) {
      throw FileSystemException(
        'Committed case bundle escapes its attempt root.',
        committedBundleRoot,
      );
    }
    await _validateCanonicalEntity(
      normalized,
      expectedType: FileSystemEntityType.directory,
      authorityRoot: attemptRoot,
    );
    return normalized;
  }

  Stream<List<int>> _scanFile(
    File file,
    _CockpitCaseAttemptScanBudget budget,
  ) async* {
    var fileBytes = 0;
    await for (final chunk in file.openRead()) {
      _checkOperation();
      fileBytes += chunk.length;
      budget.aggregateBytes += chunk.length;
      if (fileBytes > maximumFileBytes) {
        throw const FormatException(
          'Case output file scan budget was exceeded.',
        );
      }
      if (budget.aggregateBytes > maximumAggregateBytes) {
        throw const FormatException(
          'Case output aggregate scan budget was exceeded.',
        );
      }
      yield chunk;
    }
  }

  void _checkOperation() {
    if (_isCancelled?.call() ?? false) {
      throw const CockpitRpcCancelledException();
    }
    final deadline = _deadline;
    if (deadline != null && !_utcNow().toUtc().isBefore(deadline)) {
      throw TimeoutException('Case output redaction scan deadline expired.');
    }
  }

  Future<void> _validateCanonicalEntity(
    String path, {
    required FileSystemEntityType expectedType,
    required String authorityRoot,
    bool allowAuthorityRoot = false,
  }) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != expectedType ||
        !(allowAuthorityRoot && p.equals(path, authorityRoot) ||
            p.isWithin(authorityRoot, path))) {
      throw FileSystemException(
        'Case output entity has an invalid authority or type.',
        path,
      );
    }
    final canonical = p.normalize(
      expectedType == FileSystemEntityType.directory
          ? await Directory(path).resolveSymbolicLinks()
          : await File(path).resolveSymbolicLinks(),
    );
    if (!p.equals(canonical, path) ||
        !(allowAuthorityRoot && p.equals(canonical, authorityRoot) ||
            p.isWithin(authorityRoot, canonical))) {
      throw FileSystemException(
        'Case output entity resolves outside its attempt root.',
        path,
      );
    }
  }

  Future<Never> _deleteAndReject(
    String attemptRoot, {
    required String code,
    required String message,
  }) async {
    try {
      await _deleteAttemptRoot(attemptRoot);
    } on Object {
      throw const CockpitApplicationServiceException(
        code: 'caseOutputPersistenceFailed',
        message: 'Unsafe case output could not be removed.',
      );
    }
    throw CockpitApplicationServiceException(code: code, message: message);
  }

  Future<void> _deleteAttemptRoot(String attemptRoot) async {
    final root = p.normalize(attemptRoot);
    if (!p.isAbsolute(attemptRoot) ||
        root != attemptRoot ||
        !p.isWithin(_runsRoot, root)) {
      throw FileSystemException(
        'Case attempt cleanup escaped its persistence authority.',
        attemptRoot,
      );
    }
    final type = await FileSystemEntity.type(root, followLinks: false);
    switch (type) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.directory:
        await Directory(root).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(root).delete();
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        await File(root).delete();
    }
  }
}

final class _CockpitCaseAttemptDirectory {
  const _CockpitCaseAttemptDirectory({required this.path, required this.depth});

  final String path;
  final int depth;
}

final class _CockpitCaseAttemptScanBudget {
  var entities = 0;
  var aggregateBytes = 0;
}

final class CockpitCaseRunAdapterFactory {
  CockpitCaseRunAdapterFactory({
    required this.workspaceId,
    required this.projectId,
    required this.engineVersion,
    required this.runStateRoot,
    required CockpitWorkerCaseIndex caseIndex,
    required CockpitWorkerSessionProvider sessions,
    required CockpitTestSecretResolver secretResolver,
    required CockpitTestSafetyPolicy safetyPolicy,
    CockpitWorkerLogRedactor? redactor,
    CockpitTokenGenerator? tokenGenerator,
    CockpitWorkerCaseRunStore? runStore,
    CockpitWorkerRunEventStore? eventStore,
    CockpitWorkerArtifactPublisher? artifactPublisher,
    CockpitWorkerCaseResultSanitizer? resultSanitizer,
    DateTime Function()? utcNow,
  }) : _caseIndex = caseIndex,
       _sessions = sessions,
       _secretResolver = secretResolver,
       _safetyPolicy = safetyPolicy,
       _redactor = redactor ?? CockpitWorkerLogRedactor(),
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _runStore =
           runStore ??
           CockpitWorkerCaseRunStore.memory(workspaceId: workspaceId),
       _eventStore = eventStore,
       _artifactPublisher = artifactPublisher,
       _resultSanitizer = resultSanitizer,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final String workspaceId;
  final String projectId;
  final String engineVersion;
  final String runStateRoot;
  final CockpitWorkerCaseIndex _caseIndex;
  final CockpitWorkerSessionProvider _sessions;
  final CockpitTestSecretResolver _secretResolver;
  final CockpitTestSafetyPolicy _safetyPolicy;
  final CockpitWorkerLogRedactor _redactor;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitWorkerCaseRunStore _runStore;
  final CockpitWorkerRunEventStore? _eventStore;
  final CockpitWorkerArtifactPublisher? _artifactPublisher;
  final CockpitWorkerCaseResultSanitizer? _resultSanitizer;
  final DateTime Function() _utcNow;

  CockpitWorkspaceOperationAdapter validationAdapter() =>
      CockpitWorkspaceOperationAdapter(
        kind: 'case.validate',
        mutationClass: CockpitMutationClass.readOnly,
        resourceKinds: const <String>['workspace.documents'],
        prepare: (context, input) {
          final request = CockpitDocumentValidationRequest.fromJson(input);
          return CockpitPreparedWorkspaceOperation(
            resources: const <CockpitWorkerResourceRequest>[],
            execute: (_) async => _validate(request).toJson(),
          );
        },
      );

  CockpitWorkspaceOperationAdapter
  runAdapter() => CockpitWorkspaceOperationAdapter(
    kind: 'case.run',
    mutationClass: CockpitMutationClass.mutating,
    resourceKinds: const <String>['workspace.runs'],
    prepare: (context, input) async {
      final submission = CockpitRunSubmission.fromJson(input);
      final source = submission.source;
      if (source is! CockpitCaseSubmissionSource) {
        throw const FormatException('Case run requires a case source.');
      }
      if (submission.workspaceId != workspaceId) {
        throw const FormatException('Case run workspace mismatch.');
      }
      if (submission.idempotencyKey.value != context.idempotencyKey) {
        throw const CockpitApplicationServiceException(
          code: 'idempotencyConflict',
          message: 'Case run idempotency identities do not match.',
        );
      }
      final missingInvocationFeatures = submission.requiredFeatures
          .where((feature) => !context.requiredFeatures.contains(feature))
          .toList(growable: false);
      if (missingInvocationFeatures.isNotEmpty) {
        throw CockpitApplicationServiceException(
          code: 'requiredFeatureMissing',
          message:
              'Case submission features are absent from the operation envelope.',
          details: <String, Object?>{
            'missingFeatures': missingInvocationFeatures..sort(),
          },
        );
      }
      final compiled = await _compiled(source);
      final plan = CockpitTestVariableBinder().bind(
        compiled,
        inputs: submission.inputs,
      );
      final reservation = await _runStore.reserve(
        idempotencyKey: context.idempotencyKey,
        requestFingerprint: _requestFingerprint(submission, compiled),
        caseId: compiled.testCase.id,
        proposedRunId: 'run_${context.requestId}',
        proposedAttemptId: _newId('attempt'),
        now: _utcNow(),
      );
      if (reservation.replayed) {
        return CockpitPreparedWorkspaceOperation(
          resources: const <CockpitWorkerResourceRequest>[],
          isIdempotentReplay: true,
          execute: (grants) async {
            if (grants.isNotEmpty) {
              throw StateError('Idempotent replay received resource grants.');
            }
            return Map<String, Object?>.from(reservation.completedOutput!);
          },
        );
      }
      final runId = reservation.runId;
      final attemptId = reservation.attemptId;
      final attemptRoot = _attemptRoot(runId, attemptId);
      late final CockpitWorkerHealthySession session;
      try {
        await _appendEvent(
          runId,
          CockpitWorkerEventDraft(
            kind: 'run.queued',
            entityKind: CockpitRunEventEntityKind.run,
            lifecycle: CockpitRunLifecycle.queued,
          ),
        );
        await _appendEvent(
          runId,
          CockpitWorkerEventDraft(
            kind: 'case.queued',
            entityKind: CockpitRunEventEntityKind.testCase,
            caseId: compiled.testCase.id,
          ),
        );
        await _appendEvent(
          runId,
          CockpitWorkerEventDraft(
            kind: 'attempt.prepared',
            entityKind: CockpitRunEventEntityKind.attempt,
            caseId: compiled.testCase.id,
            attemptId: attemptId,
          ),
        );
        await _persistPreparation(
          submission: submission,
          compiled: compiled,
          resolvedInputs: plan.resolvedInputs,
          runId: runId,
          attemptId: attemptId,
          attemptRoot: attemptRoot,
        );
        session = await _sessions.selectHealthySession(
          targetId: submission.targetId,
          requirements: compiled.testCase.target,
        );
      } on Object catch (error, stackTrace) {
        try {
          await _appendInterrupted(
            runId: runId,
            caseId: compiled.testCase.id,
            attemptId: attemptId,
            error: error,
            cancelled: context.cancellation.isCancelled,
          );
          await _runStore.markInterrupted(
            idempotencyKey: context.idempotencyKey,
            runId: runId,
            attemptId: attemptId,
            now: _utcNow(),
          );
        } on Object {
          Error.throwWithStackTrace(error, stackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return CockpitPreparedWorkspaceOperation(
        resources: <CockpitWorkerResourceRequest>[
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.device,
            resourceId: session.deviceResourceId,
            ttl: _resourceTtl(context.deadline),
          ),
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.session,
            resourceId: session.resourceId,
            ttl: _resourceTtl(context.deadline),
          ),
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.capture,
            resourceId: session.resourceId,
            ttl: _resourceTtl(context.deadline),
          ),
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.recording,
            resourceId: session.resourceId,
            ttl: _resourceTtl(context.deadline),
          ),
        ],
        execute: (grants) => _execute(
          context: context,
          compiled: compiled,
          plan: plan,
          runId: runId,
          attemptId: attemptId,
          attemptRoot: attemptRoot,
          session: session,
          grants: grants,
        ),
      );
    },
  );

  CockpitDocumentValidationResult _validate(
    CockpitDocumentValidationRequest request,
  ) {
    final result = const CockpitTestDocumentCompiler().compile(
      request.sourceText,
    );
    final compiled = result.compiled;
    final sourceHash =
        compiled?.sourceSha256 ?? _sourceHash(request.sourceText);
    return CockpitDocumentValidationResult(
      valid: compiled != null,
      sourceSha256: sourceHash,
      document: compiled?.document,
      diagnostics: result.diagnostics,
      sourceMap: compiled == null
          ? const <CockpitTestSourceMapEntry>[]
          : <CockpitTestSourceMapEntry>[
              for (final entry in compiled.sourceMap.entries)
                CockpitTestSourceMapEntry(
                  path: entry.key,
                  location: entry.value,
                ),
            ],
    );
  }

  Future<CockpitCompiledTestCase> _compiled(
    CockpitCaseSubmissionSource source,
  ) => switch (source) {
    CockpitInlineCaseSource() => Future<CockpitCompiledTestCase>.value(
      CockpitCompiledTestCase(
        testCase: source.testCase,
        sourceSha256: source.sourceSha256,
        sourceMap: const <String, CockpitTestSourceLocation>{},
      ),
    ),
    CockpitIndexedCaseSource() => _caseIndex.resolve(source.reference),
  };

  Future<Map<String, Object?>> _execute({
    required CockpitWorkspaceOperationContext context,
    required CockpitCompiledTestCase compiled,
    required CockpitTestExecutionPlan plan,
    required String runId,
    required String attemptId,
    required String attemptRoot,
    required CockpitWorkerHealthySession session,
    required List<CockpitWorkerResourceGrant> grants,
  }) async {
    var terminalEventsAppended = false;
    var completionIntentPersisted = false;
    try {
      for (final kind in const <CockpitLeaseResourceKind>[
        CockpitLeaseResourceKind.device,
        CockpitLeaseResourceKind.session,
        CockpitLeaseResourceKind.capture,
        CockpitLeaseResourceKind.recording,
      ]) {
        final grant = grants.singleWhere(
          (candidate) => candidate.resourceKind == kind,
        );
        if (grant.workspaceId != workspaceId ||
            grant.resourceId !=
                (kind == CockpitLeaseResourceKind.device
                    ? session.deviceResourceId
                    : session.resourceId) ||
            !grant.expiresAt.isAfter(_utcNow())) {
          throw const FormatException('Case run resource grant is invalid.');
        }
      }
      if (!await session.healthCheck()) {
        throw const FormatException(
          'Worker-owned automation session is unhealthy.',
        );
      }
      await _appendEvent(
        runId,
        CockpitWorkerEventDraft(
          kind: 'run.running',
          entityKind: CockpitRunEventEntityKind.run,
          lifecycle: CockpitRunLifecycle.running,
          targetId: session.targetId,
          requestedPlane: compiled.testCase.target.plane,
        ),
      );
      await _appendEvent(
        runId,
        CockpitWorkerEventDraft(
          kind: 'case.running',
          entityKind: CockpitRunEventEntityKind.testCase,
          caseId: compiled.testCase.id,
          attemptId: attemptId,
          targetId: session.targetId,
          requestedPlane: compiled.testCase.target.plane,
        ),
      );
      await _appendEvent(
        runId,
        CockpitWorkerEventDraft(
          kind: 'attempt.running',
          entityKind: CockpitRunEventEntityKind.attempt,
          caseId: compiled.testCase.id,
          attemptId: attemptId,
          targetId: session.targetId,
          requestedPlane: compiled.testCase.target.plane,
        ),
      );
      await _runStore.markRunning(
        idempotencyKey: context.idempotencyKey,
        runId: runId,
        attemptId: attemptId,
        now: _utcNow(),
      );
      final control = CockpitCaseExecutionControl(
        forceAbort: session.forceAbort,
      );
      if (session.forceAbort case final forceAbort?) {
        context.cancellation.registerForceAbort(forceAbort);
      }
      unawaited(
        context.cancellation.whenCancelled.then((_) => control.cancel()),
      );
      final redactionScanner = CockpitCaseAttemptRedactionScanner(
        runStateRoot: runStateRoot,
        redactor: _redactor,
        deadline: context.deadline,
        isCancelled: () => context.cancellation.isCancelled,
        utcNow: _utcNow,
      );
      final runner = CockpitCaseRunner(
        automationAdapter: session.automationAdapter,
        captureAdapter: session.captureAdapter,
        recordingAdapter: session.recordingAdapter,
        lowerer: session.lowerer,
        secretResolver: _secretResolver,
        safetyPolicy: _safetyPolicy,
        bundlePrePublicationValidator: redactionScanner.validateForPublication,
      );
      CockpitTestAttemptResult? successfulResult;
      try {
        successfulResult = await runner.run(
          compiled: compiled,
          preparedPlan: plan,
          context: CockpitTestRunContext(
            projectId: projectId,
            workspaceId: workspaceId,
            runId: runId,
            caseId: compiled.testCase.id,
            attemptId: attemptId,
            engineVersion: engineVersion,
          ),
          targetId: session.targetId,
          targetEnvironment: session.environment,
          reportRoot: attemptRoot,
          control: control,
        );
      } finally {
        final completedResult = successfulResult;
        if (completedResult == null) {
          await redactionScanner.verify(attemptRoot);
        } else {
          await redactionScanner._verifyAfterSuccessfulRun(
            attemptRoot,
            completedResult,
          );
        }
      }
      final result = successfulResult;
      var artifacts = const <CockpitArtifactResource>[];
      Object? artifactPublicationError;
      final artifactPublisher = _artifactPublisher;
      if (artifactPublisher != null && result.bundlePath != null) {
        try {
          artifacts = await artifactPublisher.publishAttemptBundle(
            runId: runId,
            caseId: compiled.testCase.id,
            attemptId: attemptId,
            bundleRoot: result.bundlePath!,
            deadline: context.deadline,
            cancellation: context.cancellation,
          );
        } on Object catch (error) {
          if (result.primaryError == null) rethrow;
          artifactPublicationError = error;
        }
      }
      var json = Map<String, Object?>.from(
        _redactor.redact(result.toJson()) as Map<String, Object?>,
      );
      final resultSanitizer = _resultSanitizer;
      if (resultSanitizer == null) {
        json.remove('bundlePath');
      } else {
        json = await resultSanitizer(
          json,
          runId: runId,
          committedBundleRoot: result.bundlePath,
        );
      }
      final output = <String, Object?>{
        'runId': runId,
        'attemptId': attemptId,
        'result': json,
      };
      final terminalDrafts = _resultEventDrafts(
        result,
        artifacts: artifacts,
        artifactPublicationError: artifactPublicationError,
      );
      final eventStore = _eventStore;
      if (eventStore == null) {
        for (final draft in terminalDrafts) {
          await _appendEvent(runId, draft);
        }
        terminalEventsAppended = true;
        await _runStore.markCompleted(
          idempotencyKey: context.idempotencyKey,
          runId: runId,
          attemptId: attemptId,
          output: output,
          now: _utcNow(),
        );
      } else {
        final intent = await eventStore.appendCompletionBatch(
          runId: runId,
          drafts: terminalDrafts,
          persistIntent: (events) async {
            completionIntentPersisted = true;
            final durableIntent = await _runStore.prepareCompletionIntent(
              idempotencyKey: context.idempotencyKey,
              runId: runId,
              attemptId: attemptId,
              intentId: _newId('completion'),
              output: output,
              events: events,
              now: _utcNow(),
            );
            return durableIntent;
          },
        );
        terminalEventsAppended = true;
        await _runStore.commitCompletionIntent(intent: intent, now: _utcNow());
        await eventStore.publishRun(runId);
      }
      return output;
    } on Object catch (error, stackTrace) {
      try {
        if (!terminalEventsAppended && !completionIntentPersisted) {
          await _appendInterrupted(
            runId: runId,
            caseId: compiled.testCase.id,
            attemptId: attemptId,
            error: error,
            cancelled: context.cancellation.isCancelled,
          );
        }
        if (!terminalEventsAppended && !completionIntentPersisted) {
          await _runStore.markInterrupted(
            idempotencyKey: context.idempotencyKey,
            runId: runId,
            attemptId: attemptId,
            now: _utcNow(),
          );
        }
      } on Object {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _appendEvent(String runId, CockpitWorkerEventDraft draft) async {
    final events = _eventStore;
    if (events == null) return;
    await events.append(runId, draft);
  }

  Future<void> _appendInterrupted({
    required String runId,
    required String caseId,
    required String attemptId,
    required Object error,
    required bool cancelled,
  }) async {
    final outcome = cancelled
        ? CockpitRunOutcome.cancelled
        : CockpitRunOutcome.interrupted;
    final kind = cancelled ? 'cancelled' : 'interrupted';
    final failure = CockpitFailure(
      primary: CockpitApiError(
        code: cancelled
            ? CockpitErrorCode.cancelled
            : CockpitErrorCode.interrupted,
        category: cancelled
            ? CockpitErrorCategory.cancelled
            : CockpitErrorCategory.interrupted,
        message: '$error',
        retryable: !cancelled,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
    );
    await _appendEvent(
      runId,
      CockpitWorkerEventDraft(
        kind: 'attempt.$kind',
        entityKind: CockpitRunEventEntityKind.attempt,
        caseId: caseId,
        attemptId: attemptId,
        outcome: outcome,
        failure: failure,
      ),
    );
    await _appendEvent(
      runId,
      CockpitWorkerEventDraft(
        kind: 'case.$kind',
        entityKind: CockpitRunEventEntityKind.testCase,
        caseId: caseId,
        attemptId: attemptId,
        outcome: outcome,
        stability: CockpitRunStability.unknown,
        failure: failure,
      ),
    );
    await _appendEvent(
      runId,
      CockpitWorkerEventDraft(
        kind: 'run.$kind',
        entityKind: CockpitRunEventEntityKind.run,
        lifecycle: CockpitRunLifecycle.completed,
        outcome: outcome,
        stability: CockpitRunStability.unknown,
        failure: failure,
      ),
    );
  }

  List<CockpitWorkerEventDraft> _resultEventDrafts(
    CockpitTestAttemptResult result, {
    required List<CockpitArtifactResource> artifacts,
    required Object? artifactPublicationError,
  }) {
    final caseId = result.context.caseId;
    final attemptId = result.context.attemptId;
    final drafts = <CockpitWorkerEventDraft>[];
    for (final step in result.steps) {
      final stepArtifacts = artifacts
          .where((artifact) => artifact.stepExecutionId == step.executionId)
          .map((artifact) => artifact.reference)
          .toList(growable: false);
      final stepFailure = step.error == null
          ? null
          : CockpitFailure(primary: _apiError(step.error!));
      drafts.add(
        CockpitWorkerEventDraft(
          kind: 'step.${step.status.name}',
          entityKind: CockpitRunEventEntityKind.step,
          caseId: caseId,
          attemptId: attemptId,
          stepExecutionId: step.executionId,
          stepStatus: step.status,
          sourceLocation: step.sourceLocation,
          targetId: result.targetId,
          requestedPlane: step.requestedPlane ?? result.requestedPlane,
          actualPlane: step.actualPlane ?? result.actualPlane,
          driverId: step.driverId,
          locatorSummary:
              step.locatorResolution?.toJson() ?? const <String, Object?>{},
          degradation: step.degradationReason,
          failure: stepFailure,
          artifacts: stepArtifacts,
        ),
      );
    }
    final outcome = _runOutcome(result.outcome);
    final stability = _runStability(result.stability);
    final failure = result.primaryError == null
        ? null
        : CockpitFailure(
            primary: _apiError(result.primaryError!),
            warnings: <CockpitApiWarning>[
              for (final warning in result.cleanupErrors)
                CockpitApiWarning(
                  stage: CockpitWarningStage.cleanup,
                  error: _apiError(warning),
                ),
              if (artifactPublicationError != null)
                CockpitApiWarning(
                  stage: CockpitWarningStage.evidence,
                  error: CockpitApiError(
                    code: CockpitErrorCode.evidenceFailed,
                    category: CockpitErrorCategory.evidence,
                    message: '$artifactPublicationError',
                    retryable: true,
                    responsibleLayer: CockpitResponsibleLayer.worker,
                  ),
                ),
            ],
          );
    final terminalArtifacts = artifacts
        .where((artifact) => artifact.kind == 'attempt.manifest')
        .map((artifact) => artifact.reference)
        .toList(growable: false);
    for (final entity in const <String>['attempt', 'case', 'run']) {
      final entityKind = switch (entity) {
        'attempt' => CockpitRunEventEntityKind.attempt,
        'case' => CockpitRunEventEntityKind.testCase,
        'run' => CockpitRunEventEntityKind.run,
        _ => throw StateError('Unknown terminal event entity.'),
      };
      drafts.add(
        CockpitWorkerEventDraft(
          kind: '$entity.completed',
          entityKind: entityKind,
          caseId: entityKind == CockpitRunEventEntityKind.run ? null : caseId,
          attemptId: entityKind == CockpitRunEventEntityKind.run
              ? null
              : attemptId,
          lifecycle: entityKind == CockpitRunEventEntityKind.run
              ? CockpitRunLifecycle.completed
              : null,
          outcome: outcome,
          stability:
              entityKind == CockpitRunEventEntityKind.run ||
                  entityKind == CockpitRunEventEntityKind.testCase
              ? stability
              : null,
          targetId: result.targetId,
          requestedPlane: result.requestedPlane,
          actualPlane: result.actualPlane,
          failure: failure,
          artifacts: terminalArtifacts,
        ),
      );
    }
    return List<CockpitWorkerEventDraft>.unmodifiable(drafts);
  }

  CockpitApiError _apiError(CockpitTestError error) => CockpitApiError(
    code: _apiErrorCode(error.code),
    category: _apiErrorCategory(error.code),
    message: error.message,
    retryable: const <CockpitTestErrorCode>{
      CockpitTestErrorCode.timeout,
      CockpitTestErrorCode.hardShutdown,
      CockpitTestErrorCode.driverFailed,
      CockpitTestErrorCode.recordingFailed,
      CockpitTestErrorCode.evidenceFailed,
      CockpitTestErrorCode.bundlePublicationFailed,
      CockpitTestErrorCode.bundleIntegrityFailed,
    }.contains(error.code),
    responsibleLayer: switch (error.code) {
      CockpitTestErrorCode.driverFailed ||
      CockpitTestErrorCode.recordingFailed => CockpitResponsibleLayer.driver,
      _ => CockpitResponsibleLayer.worker,
    },
    redactedDetails: <String, Object?>{
      ...error.details,
      if (error.path != null) 'path': error.path,
      if (error.stepId != null) 'stepId': error.stepId,
      if (error.location != null) 'location': error.location!.toJson(),
    },
  );

  String _apiErrorCode(CockpitTestErrorCode code) => switch (code) {
    CockpitTestErrorCode.assertionFailed => CockpitErrorCode.assertionFailed,
    CockpitTestErrorCode.cancelled => CockpitErrorCode.cancelled,
    CockpitTestErrorCode.driverFailed ||
    CockpitTestErrorCode.hardShutdown => CockpitErrorCode.driverUnavailable,
    CockpitTestErrorCode.evidenceFailed ||
    CockpitTestErrorCode.recordingFailed ||
    CockpitTestErrorCode.bundlePublicationFailed ||
    CockpitTestErrorCode.bundleIntegrityFailed =>
      CockpitErrorCode.evidenceFailed,
    CockpitTestErrorCode.unsupportedAction ||
    CockpitTestErrorCode.unsupportedLocator ||
    CockpitTestErrorCode.schemaUnsupported =>
      CockpitErrorCode.unsupportedOperation,
    CockpitTestErrorCode.targetMismatch => CockpitErrorCode.staleReference,
    CockpitTestErrorCode.internalFailure => CockpitErrorCode.internalError,
    _ => CockpitErrorCode.invalidRequest,
  };

  CockpitErrorCategory _apiErrorCategory(
    CockpitTestErrorCode code,
  ) => switch (code) {
    CockpitTestErrorCode.assertionFailed => CockpitErrorCategory.assertion,
    CockpitTestErrorCode.cancelled => CockpitErrorCategory.cancelled,
    CockpitTestErrorCode.driverFailed ||
    CockpitTestErrorCode.hardShutdown => CockpitErrorCategory.driver,
    CockpitTestErrorCode.evidenceFailed ||
    CockpitTestErrorCode.recordingFailed ||
    CockpitTestErrorCode.bundlePublicationFailed ||
    CockpitTestErrorCode.bundleIntegrityFailed => CockpitErrorCategory.evidence,
    CockpitTestErrorCode.unsupportedAction ||
    CockpitTestErrorCode.unsupportedLocator ||
    CockpitTestErrorCode.schemaUnsupported => CockpitErrorCategory.unsupported,
    CockpitTestErrorCode.targetMismatch => CockpitErrorCategory.environment,
    CockpitTestErrorCode.internalFailure => CockpitErrorCategory.internal,
    _ => CockpitErrorCategory.invalidInput,
  };

  CockpitRunOutcome _runOutcome(CockpitTestOutcome outcome) =>
      switch (outcome) {
        CockpitTestOutcome.passed => CockpitRunOutcome.passed,
        CockpitTestOutcome.failed => CockpitRunOutcome.failed,
        CockpitTestOutcome.blocked => CockpitRunOutcome.blocked,
        CockpitTestOutcome.skipped => CockpitRunOutcome.skipped,
        CockpitTestOutcome.cancelled => CockpitRunOutcome.cancelled,
        CockpitTestOutcome.interrupted => CockpitRunOutcome.interrupted,
        CockpitTestOutcome.internalError => CockpitRunOutcome.internalError,
      };

  CockpitRunStability _runStability(CockpitTestStability stability) =>
      switch (stability) {
        CockpitTestStability.stable => CockpitRunStability.stable,
        CockpitTestStability.flaky => CockpitRunStability.flaky,
        CockpitTestStability.unknown => CockpitRunStability.unknown,
      };

  Future<void> _persistPreparation({
    required CockpitRunSubmission submission,
    required CockpitCompiledTestCase compiled,
    required Map<String, Object?> resolvedInputs,
    required String runId,
    required String attemptId,
    required String attemptRoot,
  }) async {
    final directory = Directory(attemptRoot);
    await directory.create(recursive: true);
    final preparation = <String, Object?>{
      'schemaVersion': 'cockpit.worker.case-preparation/v2',
      'workspaceId': workspaceId,
      'projectId': projectId,
      'runId': runId,
      'caseId': compiled.testCase.id,
      'attemptId': attemptId,
      'sourceSha256': compiled.sourceSha256,
      'case': compiled.testCase.toJson(),
      'sourceMap': <String, Object?>{
        for (final entry in compiled.sourceMap.entries)
          entry.key: entry.value.toJson(),
      },
      'resolvedInputs': resolvedInputs,
      'secretReferences': <String, Object?>{
        for (final entry in compiled.testCase.variables.entries)
          if (entry.value.source == CockpitTestVariableSource.secret)
            entry.key: entry.value.secretReference,
      },
      'targetRequirements': compiled.testCase.target.toJson(),
      if (submission.targetId != null) 'targetId': submission.targetId,
    };
    final target = File('$attemptRoot/preparation.json');
    final temporary = File('$attemptRoot/.preparation.${_newId('write')}.tmp');
    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    sink.write(jsonEncode(preparation));
    await sink.flush();
    await sink.close();
    await temporary.rename(target.path);
  }

  String _attemptRoot(String runId, String attemptId) =>
      '$runStateRoot/runs/$runId/cases/$attemptId';

  String _requestFingerprint(
    CockpitRunSubmission submission,
    CockpitCompiledTestCase compiled,
  ) {
    final requiredFeatures = submission.requiredFeatures.toList()..sort();
    final normalized = _canonicalJsonValue(<String, Object?>{
      'workspaceId': submission.workspaceId,
      'sourceSha256': compiled.sourceSha256,
      'case': compiled.testCase.toJson(),
      'inputs': submission.inputs,
      if (submission.targetId != null) 'targetId': submission.targetId,
      'requiredFeatures': requiredFeatures,
    });
    return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
  }

  String _newId(String prefix) =>
      '${prefix}_${_tokenGenerator.nextToken(byteLength: 16)}';

  Duration _resourceTtl(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    return remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
  }
}

String _sourceHash(String source) {
  return sha256.convert(utf8.encode(source)).toString();
}

Object? _canonicalJsonValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => () {
    final keys = map.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(map[key]),
    };
  }(),
  List<Object?> list => list.map(_canonicalJsonValue).toList(growable: false),
  _ => value,
};
