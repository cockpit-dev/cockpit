import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_application_service_exception.dart';
import '../foundation/cockpit_ids.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_worker_operation_journal.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_server.dart';
import 'cockpit_worker_value_reader.dart';

typedef CockpitWorkspaceOperationPrepare =
    FutureOr<CockpitPreparedWorkspaceOperation> Function(
      CockpitWorkspaceOperationContext context,
      Map<String, Object?> input,
    );

typedef CockpitPreparedWorkspaceOperationExecute =
    Future<Map<String, Object?>> Function(
      List<CockpitWorkerResourceGrant> grants,
    );

final class CockpitWorkspaceOperationContext {
  CockpitWorkspaceOperationContext({
    required this.workspaceId,
    required this.workspaceRoot,
    required this.requestId,
    required this.deadline,
    required this.idempotencyKey,
    required Iterable<String> requiredFeatures,
    required this.cancellation,
  }) : requiredFeatures = List<String>.unmodifiable(requiredFeatures);

  final String workspaceId;
  final String workspaceRoot;
  final String requestId;
  final DateTime deadline;
  final String idempotencyKey;
  final List<String> requiredFeatures;
  final CockpitRpcCancellation cancellation;
}

final class CockpitWorkerOperationRollbackException implements Exception {
  const CockpitWorkerOperationRollbackException({
    required this.primary,
    required this.cleanupError,
    required this.warningCode,
    required this.warningMessage,
  });

  final Object primary;
  final Object cleanupError;
  final String warningCode;
  final String warningMessage;
}

final class CockpitPreparedWorkspaceOperation {
  CockpitPreparedWorkspaceOperation({
    required Iterable<CockpitWorkerResourceRequest> resources,
    required CockpitPreparedWorkspaceOperationExecute execute,
    this.isIdempotentReplay = false,
    this.cancellationGrace,
  }) : resources = List<CockpitWorkerResourceRequest>.unmodifiable(resources),
       _execute = execute {
    if (cancellationGrace case final grace?
        when grace <= Duration.zero || grace > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        cancellationGrace,
        'cancellationGrace',
        'Must be greater than zero and at most five minutes.',
      );
    }
  }

  final List<CockpitWorkerResourceRequest> resources;
  final bool isIdempotentReplay;
  final Duration? cancellationGrace;
  final CockpitPreparedWorkspaceOperationExecute _execute;

  Future<Map<String, Object?>> execute(
    List<CockpitWorkerResourceGrant> grants,
  ) => _execute(grants);
}

final class CockpitWorkspaceOperationAdapter {
  CockpitWorkspaceOperationAdapter({
    required this.kind,
    required this.mutationClass,
    required Iterable<String> resourceKinds,
    required CockpitWorkspaceOperationPrepare prepare,
  }) : resourceKinds = List<String>.unmodifiable(resourceKinds),
       _prepare = prepare {
    workerKind(kind, r'$.kind');
    final unique = <String>{};
    for (final resourceKind in this.resourceKinds) {
      workerKind(resourceKind, r'$.resourceKinds[]');
      if (!unique.add(resourceKind)) {
        throw FormatException('Duplicate resource kind $resourceKind.');
      }
    }
  }

  final String kind;
  final CockpitMutationClass mutationClass;
  final List<String> resourceKinds;
  final CockpitWorkspaceOperationPrepare _prepare;

  FutureOr<CockpitPreparedWorkspaceOperation> prepare(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) => _prepare(context, input);
}

final class CockpitWorkspaceOperationRegistry
    implements CockpitWorkerOperationDispatcher {
  CockpitWorkspaceOperationRegistry({
    required this.workspaceId,
    required this.workspaceRoot,
    required Iterable<CockpitWorkspaceOperationAdapter> adapters,
    required CockpitWorkerResourceAuthorityClient resourceAuthority,
    required CockpitWorkerOperationJournal operationJournal,
    required Future<void> Function() terminateUnsafeWorker,
    CockpitWorkerLogRedactor? redactor,
    CockpitWorkerLogger? logger,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? utcNow,
    Duration cancellationGrace = const Duration(milliseconds: 250),
    Duration forcedAbortGrace = const Duration(seconds: 2),
  }) : _resourceAuthority = resourceAuthority,
       _operationJournal = operationJournal,
       _terminateUnsafeWorker = terminateUnsafeWorker,
       _redactor = redactor ?? CockpitWorkerLogRedactor(),
       _logger = logger ?? CockpitWorkerLogger(redactor: redactor),
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _cancellationGrace = cancellationGrace,
       _forcedAbortGrace = forcedAbortGrace,
       _adapters = <String, CockpitWorkspaceOperationAdapter>{} {
    workerId(workspaceId, r'$.workspaceId');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    if (cancellationGrace < Duration.zero ||
        forcedAbortGrace <= Duration.zero ||
        cancellationGrace > const Duration(seconds: 30) ||
        forcedAbortGrace > const Duration(seconds: 30)) {
      throw ArgumentError('Worker operation cancellation grace is invalid.');
    }
    for (final adapter in adapters) {
      if (_forbiddenKinds.contains(adapter.kind)) {
        throw FormatException(
          'Operation ${adapter.kind} cannot be registered in a worker.',
        );
      }
      if (_adapters.putIfAbsent(adapter.kind, () => adapter) != adapter) {
        throw FormatException('Duplicate worker operation ${adapter.kind}.');
      }
    }
  }

  static const Set<String> _forbiddenKinds = <String>{
    'target.discover',
    'system.capabilities',
    'system.diagnostics',
    'project.create',
    'package.search',
  };

  final String workspaceId;
  final String workspaceRoot;
  final CockpitWorkerResourceAuthorityClient _resourceAuthority;
  final CockpitWorkerOperationJournal _operationJournal;
  final Future<void> Function() _terminateUnsafeWorker;
  final CockpitWorkerLogRedactor _redactor;
  final CockpitWorkerLogger _logger;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _utcNow;
  final Duration _cancellationGrace;
  final Duration _forcedAbortGrace;
  final Map<String, CockpitWorkspaceOperationAdapter> _adapters;

  @override
  List<String> get operationKinds => _adapters.keys.toList()..sort();

  @override
  List<String> get resourceKinds {
    final kinds = _adapters.values
        .expand((adapter) => adapter.resourceKinds)
        .toSet();
    return kinds.toList()..sort();
  }

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  }) async {
    final submittedAt = _utcNow();
    var operationId = 'op-${_tokenGenerator.nextResourceIdToken()}';
    final adapter = _adapters[invocation.kind];
    if (adapter == null) {
      return _failureResult(
        invocation,
        operationId,
        submittedAt,
        submittedAt,
        'unsupportedOperation',
        CockpitErrorCategory.unsupported,
        'Workspace operation ${invocation.kind} is not supported.',
      );
    }
    if (invocation.workspaceId != workspaceId || invocation.rootId != null) {
      return _failureResult(
        invocation,
        operationId,
        submittedAt,
        submittedAt,
        'workspaceMismatch',
        CockpitErrorCategory.invalidInput,
        'Workspace operation scope is inconsistent.',
      );
    }
    final deadline = invocation.deadline;
    if (deadline == null || !deadline.isAfter(submittedAt)) {
      return _failureResult(
        invocation,
        operationId,
        submittedAt,
        submittedAt,
        'deadlineExceeded',
        CockpitErrorCategory.cancelled,
        'Workspace operation deadline has expired.',
      );
    }
    if (adapter.mutationClass == CockpitMutationClass.mutating &&
        invocation.idempotencyKey == null) {
      return _failureResult(
        invocation,
        operationId,
        submittedAt,
        submittedAt,
        'idempotencyRequired',
        CockpitErrorCategory.invalidInput,
        'Mutating workspace operations require idempotency.',
      );
    }
    String? durableIdempotencyKey;
    if (adapter.mutationClass == CockpitMutationClass.mutating) {
      durableIdempotencyKey = invocation.idempotencyKey!.value;
      try {
        final admission = await _operationJournal.admit(
          invocation: invocation,
          submittedAt: submittedAt,
        );
        operationId = admission.operationId;
        if (!admission.execute) return admission.replay!;
      } on FormatException {
        return _failureResult(
          invocation,
          operationId,
          submittedAt,
          submittedAt,
          'idempotencyConflict',
          CockpitErrorCategory.invalidInput,
          'Idempotency key conflicts with another workspace mutation.',
        );
      }
    }
    final startedAt = _utcNow();
    final context = CockpitWorkspaceOperationContext(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      requestId: requestId,
      deadline: deadline,
      idempotencyKey: invocation.idempotencyKey?.value ?? 'read-$operationId',
      requiredFeatures: invocation.requiredFeatures,
      cancellation: cancellation,
    );
    final grants = <CockpitWorkerResourceGrant>[];
    final heartbeats = _CockpitResourceHeartbeatGroup(
      authority: _resourceAuthority,
      cancellation: cancellation,
    );
    CockpitFailure? primaryFailure;
    Map<String, Object?>? output;
    Future<void>? executionTerminal;
    Timer? operationDeadlineTimer;
    var executionFinished = true;
    var operationCancellationGrace = _cancellationGrace;
    try {
      _assertNoPlaintextSecrets(invocation.input);
      cancellation.throwIfCancelled();
      final prepared = await adapter.prepare(context, invocation.input);
      operationCancellationGrace =
          prepared.cancellationGrace ?? _cancellationGrace;
      if (adapter.mutationClass == CockpitMutationClass.mutating &&
          prepared.resources.isEmpty &&
          !prepared.isIdempotentReplay) {
        throw const CockpitApplicationServiceException(
          code: 'resourceGrantRequired',
          message: 'Mutating worker operation has no Supervisor resource plan.',
        );
      }
      for (var index = 0; index < prepared.resources.length; index += 1) {
        cancellation.throwIfCancelled();
        final request = prepared.resources[index];
        final grant = await _resourceAuthority.acquire(
          request,
          workspaceId: workspaceId,
          holderId: operationId,
          idempotencyKey: '${context.idempotencyKey}-resource-$index',
          deadline: deadline,
        );
        grants.add(grant);
        _validateResourceGrant(
          grant,
          request,
          workspaceId: workspaceId,
          holderId: operationId,
          now: _utcNow(),
        );
        heartbeats.add(grant, request.ttl);
      }
      cancellation.throwIfCancelled();
      if (durableIdempotencyKey != null) {
        await _operationJournal.markRunning(
          idempotencyKey: durableIdempotencyKey,
          startedAt: startedAt,
        );
      }
      final execution = prepared.execute(grants);
      executionFinished = false;
      executionTerminal = execution.then<void>(
        (_) => executionFinished = true,
        onError: (Object _, StackTrace _) => executionFinished = true,
      );
      final deadlineSignal = Completer<Object>();
      final remaining = deadline.difference(_utcNow());
      if (remaining <= Duration.zero) {
        cancellation.cancel();
        deadlineSignal.complete(const _OperationDeadlineExceeded());
      } else {
        operationDeadlineTimer = Timer(remaining, () {
          cancellation.cancel();
          deadlineSignal.complete(const _OperationDeadlineExceeded());
        });
      }
      final completed = await Future.any<Object>(<Future<Object>>[
        execution.then<Object>(_OperationOutput.new),
        heartbeats.failure,
        cancellation.whenCancelled.then<Object>((_) {
          if (heartbeats.hasFailed) {
            return const _ResourceHeartbeatFailure();
          }
          return _utcNow().isBefore(deadline)
              ? const _OperationCancelled()
              : const _OperationDeadlineExceeded();
        }),
        deadlineSignal.future,
      ]);
      output = switch (completed) {
        _OperationOutput(:final value) => value,
        _ResourceHeartbeatFailure() => throw completed,
        _OperationCancelled() => throw const CockpitRpcCancelledException(),
        _OperationDeadlineExceeded() => throw TimeoutException(
          'Workspace operation deadline has expired.',
        ),
        _ => throw StateError('Unexpected worker operation completion.'),
      };
      if (heartbeats.hasFailed) throw const _ResourceHeartbeatFailure();
      cancellation.throwIfCancelled();
      output = Map<String, Object?>.from(
        _redactor.redact(output) as Map<String, Object?>,
      );
      workerValidateJsonValue(output, r'$.output');
      _assertNoPlaintextSecrets(output);
    } on Object catch (error, stackTrace) {
      primaryFailure = _operationFailure(
        error,
        cancellation.isCancelled,
        _redactor,
      );
      if (primaryFailure.primary.category == CockpitErrorCategory.internal) {
        _logger.log(
          'error',
          'Workspace operation failed internally.',
          fields: <String, Object?>{
            'workspaceId': workspaceId,
            'operationId': operationId,
            'operationKind': invocation.kind,
            'errorType': error.runtimeType.toString(),
            'error': '$error',
            'stackTrace': '$stackTrace',
          },
        );
      }
    }
    operationDeadlineTimer?.cancel();

    await heartbeats.stop();
    var unsafeExecution = false;
    if (!executionFinished && executionTerminal != null) {
      cancellation.cancel();
      var terminated = await _completesWithin(
        executionTerminal,
        operationCancellationGrace,
      );
      if (!terminated) {
        try {
          await cancellation.requestForceAbort();
          terminated = await _completesWithin(
            executionTerminal,
            _forcedAbortGrace,
          );
        } on Object {
          terminated = false;
        }
      }
      if (!terminated) {
        unsafeExecution = true;
        primaryFailure = _withUnsafeExecutionWarning(primaryFailure);
        try {
          await _terminateUnsafeWorker();
        } on Object {
          primaryFailure = _withWorkerTerminationWarning(primaryFailure);
        }
      }
    }
    CockpitApiWarning? cleanupWarning;
    if (!unsafeExecution) {
      for (final grant in grants.reversed) {
        try {
          await _resourceAuthority.release(
            grant,
            cancel: _requiresCancelledRelease(
              primaryFailure,
              cancellation.isCancelled,
            ),
          );
        } on Object {
          cleanupWarning = CockpitApiWarning(
            stage: CockpitWarningStage.cleanup,
            error: CockpitApiError(
              code: 'resourceReleaseFailed',
              category: CockpitErrorCategory.resource,
              message: 'Supervisor resource release failed.',
              retryable: true,
              responsibleLayer: CockpitResponsibleLayer.supervisor,
            ),
          );
        }
      }
    }
    final finishedAt = _utcNow();
    late final CockpitOperationResult result;
    if (primaryFailure == null && cleanupWarning == null) {
      result = CockpitOperationResult(
        operationId: operationId,
        kind: invocation.kind,
        workspaceId: workspaceId,
        lifecycle: CockpitOperationLifecycle.completed,
        outcome: CockpitOperationOutcome.succeeded,
        submittedAt: submittedAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        output: output ?? const <String, Object?>{},
      );
    } else {
      final failure = primaryFailure == null
          ? CockpitFailure(primary: cleanupWarning!.error)
          : CockpitFailure(
              primary: primaryFailure.primary,
              warnings: <CockpitApiWarning>[
                ...primaryFailure.warnings,
                ?cleanupWarning,
              ],
            );
      result = CockpitOperationResult(
        operationId: operationId,
        kind: invocation.kind,
        workspaceId: workspaceId,
        lifecycle: CockpitOperationLifecycle.completed,
        outcome: failure.primary.category == CockpitErrorCategory.cancelled
            ? CockpitOperationOutcome.cancelled
            : CockpitOperationOutcome.failed,
        submittedAt: submittedAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        failure: failure,
      );
    }
    if (durableIdempotencyKey != null && !unsafeExecution) {
      try {
        await _operationJournal.complete(
          idempotencyKey: durableIdempotencyKey,
          result: result,
        );
      } on Object {
        await _terminateUnsafeWorker();
        rethrow;
      }
    }
    return result;
  }

  CockpitOperationResult _failureResult(
    CockpitOperationInvocation invocation,
    String operationId,
    DateTime submittedAt,
    DateTime startedAt,
    String code,
    CockpitErrorCategory category,
    String message,
  ) => CockpitOperationResult(
    operationId: operationId,
    kind: invocation.kind,
    workspaceId: workspaceId,
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.failed,
    submittedAt: submittedAt,
    startedAt: startedAt,
    finishedAt: _utcNow(),
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
}

void _validateResourceGrant(
  CockpitWorkerResourceGrant grant,
  CockpitWorkerResourceRequest request, {
  required String workspaceId,
  required String holderId,
  required DateTime now,
}) {
  if (grant.workspaceId != workspaceId ||
      grant.holderId != holderId ||
      grant.resourceKind != request.resourceKind ||
      grant.resourceId != request.resourceId ||
      !grant.expiresAt.isAfter(now) ||
      request.requiresPort != (grant.port != null)) {
    throw const CockpitApplicationServiceException(
      code: 'workerResourceGrantInvalid',
      message: 'Supervisor grant does not match the requested resource.',
    );
  }
}

bool _requiresCancelledRelease(CockpitFailure? failure, bool cancelled) {
  if (cancelled) return true;
  if (failure == null) return false;
  if (failure.primary.category != CockpitErrorCategory.application) return true;
  return failure.warnings.any(
    (warning) => warning.stage == CockpitWarningStage.cleanup,
  );
}

CockpitFailure _operationFailure(
  Object error,
  bool cancelled,
  CockpitWorkerLogRedactor redactor,
) {
  if (error is CockpitWorkerOperationRollbackException) {
    final primary = _operationFailure(error.primary, cancelled, redactor);
    return CockpitFailure(
      primary: primary.primary,
      warnings: <CockpitApiWarning>[
        ...primary.warnings,
        CockpitApiWarning(
          stage: CockpitWarningStage.cleanup,
          error: CockpitApiError(
            code: error.warningCode,
            category: CockpitErrorCategory.application,
            message: error.warningMessage,
            retryable: true,
            responsibleLayer: CockpitResponsibleLayer.worker,
            redactedDetails: <String, Object?>{
              'errorType': error.cleanupError.runtimeType.toString(),
            },
          ),
        ),
      ],
    );
  }
  if (error is _ResourceHeartbeatFailure) {
    return CockpitFailure(
      primary: CockpitApiError(
        code: 'resourceHeartbeatFailed',
        category: CockpitErrorCategory.resource,
        message: 'Supervisor resource renewal failed.',
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
    );
  }
  if (cancelled || error is CockpitRpcCancelledException) {
    return CockpitFailure(
      primary: CockpitApiError(
        code: CockpitErrorCode.cancelled,
        category: CockpitErrorCategory.cancelled,
        message: 'Workspace operation was cancelled.',
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
    );
  }
  if (error is CockpitApplicationServiceException) {
    return CockpitFailure(
      primary: CockpitApiError(
        code: error.code,
        category: CockpitErrorCategory.application,
        message: redactor.redact(error.message) as String,
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.worker,
        redactedDetails: Map<String, Object?>.from(
          redactor.redact(error.details) as Map<String, Object?>,
        ),
      ),
    );
  }
  if (error is FormatException) {
    final message = error.message.toString();
    return CockpitFailure(
      primary: CockpitApiError(
        code: CockpitErrorCode.invalidRequest,
        category: CockpitErrorCategory.invalidInput,
        message: redactor.redact(message) as String,
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
    );
  }
  if (error is TimeoutException) {
    return CockpitFailure(
      primary: CockpitApiError(
        code: 'deadlineExceeded',
        category: CockpitErrorCategory.cancelled,
        message:
            redactor.redact(
                  error.message ?? 'Workspace operation deadline has expired.',
                )
                as String,
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
    );
  }
  return CockpitFailure(
    primary: CockpitApiError(
      code: CockpitErrorCode.internalError,
      category: CockpitErrorCategory.internal,
      message: 'Workspace operation failed internally.',
      retryable: false,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  );
}

final class _OperationOutput {
  const _OperationOutput(this.value);

  final Map<String, Object?> value;
}

final class _OperationCancelled {
  const _OperationCancelled();
}

final class _OperationDeadlineExceeded {
  const _OperationDeadlineExceeded();
}

final class _ResourceHeartbeatFailure implements Exception {
  const _ResourceHeartbeatFailure();
}

Future<bool> _completesWithin(Future<void> terminal, Duration grace) async {
  if (grace <= Duration.zero) return false;
  return Future.any<bool>(<Future<bool>>[
    terminal.then((_) => true),
    Future<bool>.delayed(grace, () => false),
  ]);
}

CockpitFailure _withUnsafeExecutionWarning(CockpitFailure? failure) {
  final warning = CockpitApiWarning(
    stage: CockpitWarningStage.cleanup,
    error: CockpitApiError(
      code: 'workerExecutionTerminationFailed',
      category: CockpitErrorCategory.internal,
      message: 'Worker execution did not terminate within the bounded grace.',
      retryable: true,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  );
  return failure == null
      ? CockpitFailure(primary: warning.error)
      : CockpitFailure(
          primary: failure.primary,
          warnings: <CockpitApiWarning>[...failure.warnings, warning],
        );
}

CockpitFailure _withWorkerTerminationWarning(CockpitFailure? failure) {
  final warning = CockpitApiWarning(
    stage: CockpitWarningStage.cleanup,
    error: CockpitApiError(
      code: 'unsafeWorkerTerminationFailed',
      category: CockpitErrorCategory.internal,
      message: 'Unsafe worker termination could not be confirmed.',
      retryable: true,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  );
  return failure == null
      ? CockpitFailure(primary: warning.error)
      : CockpitFailure(
          primary: failure.primary,
          warnings: <CockpitApiWarning>[...failure.warnings, warning],
        );
}

final class _CockpitResourceHeartbeatGroup {
  _CockpitResourceHeartbeatGroup({
    required CockpitWorkerResourceAuthorityClient authority,
    required CockpitRpcCancellation cancellation,
  }) : _authority = authority,
       _cancellation = cancellation;

  final CockpitWorkerResourceAuthorityClient _authority;
  final CockpitRpcCancellation _cancellation;
  final List<Timer> _timers = <Timer>[];
  final Set<Future<void>> _active = <Future<void>>{};
  final Set<String> _activeGrantIds = <String>{};
  final Completer<Object> _failure = Completer<Object>();
  Future<void> _heartbeatTail = Future<void>.value();
  var _stopped = false;

  Future<Object> get failure => _failure.future;
  bool get hasFailed => _failure.isCompleted;

  void add(CockpitWorkerResourceGrant grant, Duration ttl) {
    final third = Duration(microseconds: ttl.inMicroseconds ~/ 3);
    final interval = third < const Duration(milliseconds: 250)
        ? const Duration(milliseconds: 250)
        : third > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : third;
    _timers.add(
      Timer.periodic(interval, (_) {
        if (_stopped ||
            _cancellation.isCancelled ||
            !_activeGrantIds.add(grant.grantId)) {
          return;
        }
        late final Future<void> heartbeat;
        heartbeat = _heartbeatTail
            .then((_) {
              if (_stopped || _cancellation.isCancelled) {
                return Future<void>.value();
              }
              return _authority.heartbeat(grant);
            })
            .catchError((Object _) {
              if (!_failure.isCompleted) {
                _failure.complete(const _ResourceHeartbeatFailure());
                _cancellation.cancel();
              }
            })
            .whenComplete(() {
              _active.remove(heartbeat);
              _activeGrantIds.remove(grant.grantId);
            });
        _heartbeatTail = heartbeat;
        _active.add(heartbeat);
      }),
    );
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    if (_active.isNotEmpty) {
      await Future.wait<void>(_active.toList(growable: false));
    }
  }
}

final RegExp _plaintextSecretKey = RegExp(
  r'^(?:authorization|cookie|password|secretValue|token|apiKey|privateKey)$',
  caseSensitive: false,
);

void _assertNoPlaintextSecrets(Object? value, {String? key}) {
  if (key != null &&
      _plaintextSecretKey.hasMatch(key) &&
      key != 'idempotencyKey' &&
      key != 'handoffToken' &&
      !_isRedactedSecretValue(value) &&
      !_isSecretVariableDeclaration(value)) {
    throw CockpitApplicationServiceException(
      code: 'plaintextSecretRejected',
      message: 'Plaintext secrets cannot cross the worker boundary.',
      details: <String, Object?>{'field': key},
    );
  }
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      _assertNoPlaintextSecrets(entry.value, key: '${entry.key}');
    }
  } else if (value is Iterable<Object?>) {
    for (final item in value) {
      _assertNoPlaintextSecrets(item);
    }
  }
}

bool _isRedactedSecretValue(Object? value) =>
    value == '[REDACTED]' ||
    value is Iterable<Object?> && value.every(_isRedactedSecretValue);

bool _isSecretVariableDeclaration(Object? value) {
  if (value is! Map ||
      value['source'] != 'secret' ||
      value['type'] != 'string' ||
      value['reference'] is! String) {
    return false;
  }
  return !value.containsKey('value') && !value.containsKey('default');
}
