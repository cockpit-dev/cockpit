import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_application_service_exception.dart';
import '../test/cockpit_test_safety_policy.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_operation_journal.dart';
import 'cockpit_worker_operation_router.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_resource_identity.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkerTargetRegistrationDispatcher
    implements CockpitWorkerInternalOperationDispatcher {
  CockpitWorkerTargetRegistrationDispatcher({
    required this.workspaceId,
    required this.workspaceRoot,
    required CockpitWorkerTargetRegistrar registrar,
    required CockpitWorkerDocumentIndex documents,
    required CockpitWorkerOperationJournal operationJournal,
    required Future<void> Function() terminateUnsafeWorker,
    DateTime Function()? utcNow,
  }) : _registrar = registrar,
       _documents = documents,
       _operationJournal = operationJournal,
       _terminateUnsafeWorker = terminateUnsafeWorker,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  static const String registerKind = 'worker.target.register';

  final String workspaceId;
  final String workspaceRoot;
  final CockpitWorkerTargetRegistrar _registrar;
  final CockpitWorkerDocumentIndex _documents;
  final CockpitWorkerOperationJournal _operationJournal;
  final Future<void> Function() _terminateUnsafeWorker;
  final DateTime Function() _utcNow;

  @override
  Set<String> get internalOperationKinds => const <String>{registerKind};

  CockpitWorkspaceOperationAdapter workspaceAdapter() =>
      CockpitWorkspaceOperationAdapter(
        kind: 'target.register',
        mutationClass: CockpitMutationClass.mutating,
        resourceKinds: const <String>['workspace.targets'],
        prepare: (context, input) async {
          final registration = await _registration(input);
          return CockpitPreparedWorkspaceOperation(
            resources: <CockpitWorkerResourceRequest>[
              CockpitWorkerResourceRequest(
                resourceKind: CockpitLeaseResourceKind.workspaceMutation,
                resourceId: cockpitCanonicalWorkspaceResourceId(workspaceId),
                ttl: _grantTtl(context.deadline),
              ),
            ],
            execute: (_) async => <String, Object?>{
              'targetId': await _registrar.registerTarget(registration),
            },
          );
        },
      );

  @override
  Future<CockpitOperationResult> executeInternal(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  }) async {
    final submittedAt = _utcNow();
    if (invocation.kind != registerKind ||
        invocation.workspaceId != workspaceId ||
        invocation.rootId != null ||
        invocation.idempotencyKey == null ||
        invocation.deadline == null ||
        !invocation.deadline!.isAfter(submittedAt)) {
      throw const FormatException('Worker target registration is invalid.');
    }
    late final CockpitWorkerOperationAdmission admission;
    try {
      admission = await _operationJournal.admit(
        invocation: invocation,
        submittedAt: submittedAt,
      );
    } on FormatException {
      return _failureResult(
        invocation: invocation,
        operationId: requestId,
        submittedAt: submittedAt,
        startedAt: submittedAt,
        code: 'idempotencyConflict',
        category: CockpitErrorCategory.invalidInput,
        message: 'Idempotency key conflicts with another target registration.',
        finishedAt: _utcNow(),
      );
    }
    if (!admission.execute) return admission.replay!;

    var startedAt = submittedAt;
    late final CockpitOperationResult result;
    try {
      cancellation.throwIfCancelled();
      final registration = await _registration(invocation.input);
      cancellation.throwIfCancelled();
      if (!invocation.deadline!.isAfter(_utcNow())) {
        throw const CockpitRpcCancelledException();
      }
      startedAt = _utcNow();
      await _operationJournal.markRunning(
        idempotencyKey: invocation.idempotencyKey!.value,
        startedAt: startedAt,
      );
      final targetId = await _registrar.registerTarget(registration);
      result = CockpitOperationResult(
        operationId: admission.operationId,
        kind: invocation.kind,
        workspaceId: workspaceId,
        lifecycle: CockpitOperationLifecycle.completed,
        outcome: CockpitOperationOutcome.succeeded,
        submittedAt: submittedAt,
        startedAt: startedAt,
        finishedAt: _utcNow(),
        output: <String, Object?>{'targetId': targetId},
      );
    } on Object catch (error) {
      result = _registrationFailure(
        invocation: invocation,
        operationId: admission.operationId,
        submittedAt: submittedAt,
        startedAt: startedAt,
        error: error,
        finishedAt: _utcNow(),
      );
    }
    try {
      await _operationJournal.complete(
        idempotencyKey: invocation.idempotencyKey!.value,
        result: result,
      );
    } on Object {
      await _terminateUnsafeWorker();
      rethrow;
    }
    return result;
  }

  Future<CockpitWorkerTargetRegistration> _registration(
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{
        'platform',
        'deviceId',
        'entrypointDocumentId',
        'flavor',
        'appId',
        'wdaUrl',
        'cdpUrl',
        'targetKind',
        'mode',
        'environment',
      },
      r'$.input',
      required: const <String>{'platform', 'deviceId'},
    );
    String? target;
    String? targetSha256;
    if (input['entrypointDocumentId'] != null) {
      final resolvedTarget = (await _documents.resolveDocuments(<String>[
        workerId(
          input['entrypointDocumentId'],
          r'$.input.entrypointDocumentId',
        ),
      ])).single;
      target = p.relative(resolvedTarget.absolutePath, from: workspaceRoot);
      targetSha256 = resolvedTarget.sourceSha256;
    }
    return CockpitWorkerTargetRegistration(
      workspaceId: workspaceId,
      platform: workerString(
        input['platform'],
        r'$.input.platform',
        maximum: 32,
      ),
      deviceId: workerString(
        input['deviceId'],
        r'$.input.deviceId',
        maximum: 256,
      ),
      entrypoint: target,
      entrypointSha256: targetSha256,
      flavor: input['flavor'] == null
          ? null
          : workerString(input['flavor'], r'$.input.flavor', maximum: 128),
      appId: input['appId'] == null
          ? null
          : workerString(input['appId'], r'$.input.appId', maximum: 512),
      wdaUrl: input['wdaUrl'] == null
          ? null
          : workerString(input['wdaUrl'], r'$.input.wdaUrl', maximum: 2048),
      cdpUrl: input['cdpUrl'] == null
          ? null
          : workerString(input['cdpUrl'], r'$.input.cdpUrl', maximum: 2048),
      targetKind: _enumeration(
        input['targetKind'],
        CockpitTargetKind.values,
        CockpitTargetKind.flutterApp,
      ),
      mode: _enumeration(
        input['mode'],
        CockpitAppMode.values,
        CockpitAppMode.development,
      ),
      environment: _enumeration(
        input['environment'],
        CockpitTestTargetEnvironment.values,
        CockpitTestTargetEnvironment.unknown,
      ),
    );
  }

  Duration _grantTtl(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    return remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
  }
}

CockpitOperationResult _registrationFailure({
  required CockpitOperationInvocation invocation,
  required String operationId,
  required DateTime submittedAt,
  required DateTime startedAt,
  required DateTime finishedAt,
  required Object error,
}) {
  if (error is CockpitRpcCancelledException) {
    return _failureResult(
      invocation: invocation,
      operationId: operationId,
      submittedAt: submittedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      code: CockpitErrorCode.cancelled,
      category: CockpitErrorCategory.cancelled,
      message: 'Target registration was cancelled.',
    );
  }
  if (error is CockpitApplicationServiceException) {
    return _failureResult(
      invocation: invocation,
      operationId: operationId,
      submittedAt: submittedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      code: error.code,
      category: CockpitErrorCategory.application,
      message: error.message,
    );
  }
  if (error is FormatException) {
    return _failureResult(
      invocation: invocation,
      operationId: operationId,
      submittedAt: submittedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      code: 'targetRegistrationInvalid',
      category: CockpitErrorCategory.invalidInput,
      message: 'Target registration input or entrypoint is invalid.',
    );
  }
  return _failureResult(
    invocation: invocation,
    operationId: operationId,
    submittedAt: submittedAt,
    startedAt: startedAt,
    finishedAt: finishedAt,
    code: CockpitErrorCode.internalError,
    category: CockpitErrorCategory.internal,
    message: 'Target registration failed internally.',
  );
}

CockpitOperationResult _failureResult({
  required CockpitOperationInvocation invocation,
  required String operationId,
  required DateTime submittedAt,
  required DateTime startedAt,
  required DateTime finishedAt,
  required String code,
  required CockpitErrorCategory category,
  required String message,
}) => CockpitOperationResult(
  operationId: operationId,
  kind: invocation.kind,
  workspaceId: invocation.workspaceId!,
  lifecycle: CockpitOperationLifecycle.completed,
  outcome: category == CockpitErrorCategory.cancelled
      ? CockpitOperationOutcome.cancelled
      : CockpitOperationOutcome.failed,
  submittedAt: submittedAt,
  startedAt: startedAt,
  finishedAt: finishedAt,
  failure: CockpitFailure(
    primary: CockpitApiError(
      code: code,
      category: category,
      message: message,
      retryable: false,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  ),
);

T _enumeration<T extends Enum>(Object? value, List<T> values, T fallback) {
  if (value == null) return fallback;
  final name = workerString(value, r'$.input.enum', maximum: 64);
  return values.where((entry) => entry.name == name).firstOrNull ??
      (throw const FormatException('Worker target enum is invalid.'));
}
