import 'dart:async';

import '../infrastructure/cockpit_monotonic_clock.dart';

final class CockpitCaseExecutionControl {
  CockpitCaseExecutionControl({
    this.cancellationGrace = const Duration(seconds: 2),
    Future<void> Function()? forceAbort,
  }) : _forceAbort = forceAbort;

  final Duration cancellationGrace;
  final Future<void> Function()? _forceAbort;
  final Completer<void> _primaryCancellation = Completer<void>();
  final Completer<void> _hardShutdown = Completer<void>();
  bool _abortInvoked = false;

  bool get isCancellationRequested => _primaryCancellation.isCompleted;
  bool get isHardShutdownRequested => _hardShutdown.isCompleted;
  Future<void> get cancellationSignal => _primaryCancellation.future;
  Future<void> get hardShutdownSignal => _hardShutdown.future;

  void cancel() {
    if (!_primaryCancellation.isCompleted) {
      _primaryCancellation.complete();
    }
  }

  void hardShutdown() {
    cancel();
    if (!_hardShutdown.isCompleted) {
      _hardShutdown.complete();
    }
  }

  Future<void> forceAbortActive() async {
    if (_abortInvoked) {
      return;
    }
    _abortInvoked = true;
    await _forceAbort?.call();
  }
}

final class CockpitCaseCleanupControl {
  const CockpitCaseCleanupControl(this.parent);

  final CockpitCaseExecutionControl parent;

  bool get isHardShutdownRequested => parent.isHardShutdownRequested;
  Future<void> get hardShutdownSignal => parent.hardShutdownSignal;
}

final class CockpitCaseCancelled implements Exception {
  const CockpitCaseCancelled();
}

final class CockpitCaseHardShutdown implements Exception {
  const CockpitCaseHardShutdown();
}

Future<T> cockpitRacePrimaryControl<T>({
  required Future<T> operation,
  required CockpitCaseExecutionControl control,
  required CockpitMonotonicClock clock,
}) async {
  if (control.isCancellationRequested) {
    throw const CockpitCaseCancelled();
  }
  final first = await Future.any<_PrimaryRace<T>>(<Future<_PrimaryRace<T>>>[
    operation.then<_PrimaryRace<T>>(
      _PrimaryOperationResult<T>.new,
      onError: (Object error, StackTrace stackTrace) =>
          _PrimaryOperationError<T>(error, stackTrace),
    ),
    control.cancellationSignal.then<_PrimaryRace<T>>(
      (_) => _PrimaryCancellation<T>(),
    ),
    control.hardShutdownSignal.then<_PrimaryRace<T>>(
      (_) => _PrimaryHardShutdown<T>(),
    ),
  ]);
  switch (first) {
    case _PrimaryOperationResult<T>(:final value):
      return value;
    case _PrimaryOperationError<T>(:final error, :final stackTrace):
      Error.throwWithStackTrace(error, stackTrace);
    case _PrimaryHardShutdown<T>():
      throw const CockpitCaseHardShutdown();
    case _PrimaryCancellation<T>():
      var operationSettled = false;
      final settled = operation.then<void>(
        (_) {
          operationSettled = true;
        },
        onError: (Object _, StackTrace _) {
          operationSettled = true;
        },
      );
      final graceExpired = clock.delay(control.cancellationGrace).then<void>((
        _,
      ) {
        if (!operationSettled) {
          unawaited(
            control.forceAbortActive().catchError((Object _, StackTrace _) {}),
          );
        }
      });
      await Future.any<void>(<Future<void>>[
        settled,
        graceExpired,
        control.hardShutdownSignal.then<void>(
          (_) => throw const CockpitCaseHardShutdown(),
        ),
      ]);
      if (control.isHardShutdownRequested) {
        throw const CockpitCaseHardShutdown();
      }
      throw const CockpitCaseCancelled();
  }
}

Future<T> cockpitRaceCleanupControl<T>({
  required Future<T> operation,
  required CockpitCaseCleanupControl control,
}) {
  if (control.isHardShutdownRequested) {
    throw const CockpitCaseHardShutdown();
  }
  return Future.any<T>(<Future<T>>[
    operation,
    control.hardShutdownSignal.then<T>(
      (_) => throw const CockpitCaseHardShutdown(),
    ),
  ]);
}

sealed class _PrimaryRace<T> {
  const _PrimaryRace();
}

final class _PrimaryOperationResult<T> extends _PrimaryRace<T> {
  const _PrimaryOperationResult(this.value);
  final T value;
}

final class _PrimaryOperationError<T> extends _PrimaryRace<T> {
  const _PrimaryOperationError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

final class _PrimaryCancellation<T> extends _PrimaryRace<T> {
  const _PrimaryCancellation();
}

final class _PrimaryHardShutdown<T> extends _PrimaryRace<T> {
  const _PrimaryHardShutdown();
}
