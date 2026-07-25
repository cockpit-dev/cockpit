import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_application_service_exception.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_forwarded_port_handoff.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_worker_operation_router.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_value_reader.dart';

final class CockpitRpcWorkerForwardedPortHandoff
    implements
        CockpitWorkerForwardedPortHandoff,
        CockpitWorkerInternalOperationDispatcher {
  CockpitRpcWorkerForwardedPortHandoff({
    required this.workspaceId,
    required this.workerOwnerId,
    required this.workerProcessId,
    required this.processStartIdentity,
    required CockpitJsonRpcPeer peer,
    CockpitWorkerLogger? logger,
    DateTime Function()? utcNow,
  }) : _peer = peer,
       _logger = logger ?? CockpitWorkerLogger(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
    workerId(workerOwnerId, r'$.workerOwnerId');
    workerString(processStartIdentity, r'$.processStartIdentity', maximum: 512);
    if (workerProcessId <= 0) {
      throw const FormatException('Worker process id is invalid.');
    }
  }

  static const String bindKind = 'worker.port.bind';

  final String workspaceId;
  final String workerOwnerId;
  final int workerProcessId;
  final String processStartIdentity;
  final CockpitJsonRpcPeer _peer;
  final CockpitWorkerLogger _logger;
  final DateTime Function() _utcNow;
  final Map<String, _PendingPortLaunch<Object?>> _pending =
      <String, _PendingPortLaunch<Object?>>{};

  @override
  Set<String> get internalOperationKinds => const <String>{bindKind};

  @override
  Future<T> launchWithGrant<T>({
    required CockpitWorkerResourceGrant grant,
    required DateTime deadline,
    required Future<T> Function(int port) launch,
  }) async {
    _validateGrant(grant, deadline);
    if (_pending.containsKey(grant.grantId)) {
      throw const CockpitApplicationServiceException(
        code: 'portHandoffAlreadyActive',
        message: 'A forwarded-port handoff is already active.',
      );
    }
    final pending = _PendingPortLaunch<T>(grant: grant, launch: launch);
    _pending[grant.grantId] = pending as _PendingPortLaunch<Object?>;
    unawaited(
      pending.result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      final raw = await _peer.call(
        method: 'operation',
        params: <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': workspaceId,
          'idempotencyKey': '${grant.grantId}-handoff',
          'invocation': CockpitOperationInvocation(
            kind: 'resource.handoff',
            workspaceId: workspaceId,
            idempotencyKey: CockpitIdempotencyKey('${grant.grantId}-handoff'),
            deadline: deadline,
            input: <String, Object?>{
              'grantId': grant.grantId,
              'ownerId': workerOwnerId,
              'processId': workerProcessId,
              'processStartIdentity': processStartIdentity,
              'sessionId': grant.holderId,
            },
          ).toJson(),
        },
        deadline: deadline,
      );
      final result = CockpitWorkerOperationResult.fromJson(raw).result;
      if (result.outcome != CockpitOperationOutcome.succeeded ||
          result.output?['verified'] != true) {
        throw const CockpitApplicationServiceException(
          code: 'portHandoffRejected',
          message: 'Supervisor rejected forwarded-port ownership.',
        );
      }
      return await pending.result;
    } finally {
      _pending.remove(grant.grantId);
    }
  }

  @override
  Future<CockpitOperationResult> executeInternal(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  }) async {
    final submittedAt = _utcNow();
    try {
      _validateInvocation(invocation, submittedAt);
      cancellation.throwIfCancelled();
      final output = switch (invocation.kind) {
        bindKind => await _bind(invocation.input, cancellation),
        _ => throw const FormatException('Unknown internal port operation.'),
      };
      final finishedAt = _utcNow();
      return CockpitOperationResult(
        operationId: requestId,
        kind: invocation.kind,
        workspaceId: workspaceId,
        lifecycle: CockpitOperationLifecycle.completed,
        outcome: CockpitOperationOutcome.succeeded,
        submittedAt: submittedAt,
        startedAt: submittedAt,
        finishedAt: finishedAt,
        output: output,
      );
    } on Object catch (error, stackTrace) {
      _logger.log(
        'error',
        'Forwarded-port launch failed.',
        fields: <String, Object?>{
          'workspaceId': workspaceId,
          'operationKind': invocation.kind,
          'error': '$error',
          'stackTrace': '$stackTrace',
        },
      );
      final finishedAt = _utcNow();
      return CockpitOperationResult(
        operationId: requestId,
        kind: invocation.kind,
        workspaceId: workspaceId,
        lifecycle: CockpitOperationLifecycle.completed,
        outcome: cancellation.isCancelled
            ? CockpitOperationOutcome.cancelled
            : CockpitOperationOutcome.failed,
        submittedAt: submittedAt,
        startedAt: submittedAt,
        finishedAt: finishedAt,
        failure: CockpitFailure(
          primary: CockpitApiError(
            code: cancellation.isCancelled
                ? CockpitErrorCode.cancelled
                : 'portHandoffFailed',
            category: cancellation.isCancelled
                ? CockpitErrorCategory.cancelled
                : CockpitErrorCategory.resource,
            message: cancellation.isCancelled
                ? 'Forwarded-port handoff was cancelled.'
                : 'Forwarded-port handoff failed.',
            retryable: !cancellation.isCancelled,
            responsibleLayer: CockpitResponsibleLayer.worker,
          ),
        ),
      );
    }
  }

  Future<Map<String, Object?>> _bind(
    Map<String, Object?> input,
    CockpitRpcCancellation cancellation,
  ) async {
    workerKeys(
      input,
      const <String>{'grantId', 'port', 'handoffToken'},
      r'$.input',
      required: const <String>{'grantId', 'port', 'handoffToken'},
    );
    final grantId = workerId(input['grantId'], r'$.input.grantId');
    final pending = _pending[grantId];
    if (pending == null) {
      throw const FormatException('Forwarded-port handoff is not pending.');
    }
    final port = workerInteger(
      input['port'],
      r'$.input.port',
      minimum: 1,
      maximum: 65535,
    );
    final handoffToken = workerString(
      input['handoffToken'],
      r'$.input.handoffToken',
      minimum: 16,
      maximum: 128,
    );
    if (port != pending.grant.port ||
        handoffToken != pending.grant.handoffToken) {
      throw const FormatException('Forwarded-port grant does not match.');
    }
    pending.binding ??= () async {
      try {
        cancellation.throwIfCancelled();
        final result = await pending.launch(port);
        cancellation.throwIfCancelled();
        if (!pending._result.isCompleted) pending._result.complete(result);
      } on Object catch (error, stackTrace) {
        if (!pending._result.isCompleted) {
          pending._result.completeError(error, stackTrace);
        }
        rethrow;
      }
    }();
    await pending.binding;
    return const <String, Object?>{'bound': true};
  }

  void _validateGrant(CockpitWorkerResourceGrant grant, DateTime deadline) {
    final now = _utcNow();
    if (grant.workspaceId != workspaceId ||
        grant.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
        grant.port == null ||
        grant.handoffToken == null ||
        !grant.expiresAt.isAfter(now) ||
        !deadline.toUtc().isAfter(now)) {
      throw const CockpitApplicationServiceException(
        code: 'forwardedPortGrantInvalid',
        message: 'Forwarded-port handoff grant is invalid or expired.',
      );
    }
  }

  void _validateInvocation(
    CockpitOperationInvocation invocation,
    DateTime now,
  ) {
    if (invocation.workspaceId != workspaceId ||
        invocation.rootId != null ||
        invocation.idempotencyKey == null ||
        invocation.deadline == null ||
        !invocation.deadline!.isAfter(now)) {
      throw const FormatException(
        'Internal forwarded-port operation scope is invalid.',
      );
    }
  }
}

final class _PendingPortLaunch<T> {
  _PendingPortLaunch({required this.grant, required this.launch});

  final CockpitWorkerResourceGrant grant;
  final Future<T> Function(int port) launch;
  final Completer<T> _result = Completer<T>();
  Future<void>? binding;

  Future<T> get result => _result.future;
}
