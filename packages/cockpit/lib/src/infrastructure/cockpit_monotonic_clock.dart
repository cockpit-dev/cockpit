import 'dart:async';

abstract interface class CockpitMonotonicClock {
  Duration get elapsed;
  DateTime get utcNow;
  Future<void> delay(Duration duration);
}

final class CockpitSystemMonotonicClock implements CockpitMonotonicClock {
  CockpitSystemMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  DateTime get utcNow => DateTime.now().toUtc();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

final class CockpitMonotonicDeadline {
  CockpitMonotonicDeadline.after(CockpitMonotonicClock clock, Duration budget)
    : _clock = clock,
      _expiresAt = clock.elapsed + budget {
    if (budget <= Duration.zero) {
      throw ArgumentError.value(budget, 'budget', 'Must be positive.');
    }
  }

  final CockpitMonotonicClock _clock;
  final Duration _expiresAt;

  Duration get remaining {
    final value = _expiresAt - _clock.elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  bool get isExpired => remaining == Duration.zero;

  Duration clamp(Duration requested) {
    final available = remaining;
    return requested < available ? requested : available;
  }
}

final class CockpitDeadlineExceeded implements Exception {
  const CockpitDeadlineExceeded();
}

Future<T> cockpitRaceDeadline<T>({
  required Future<T> operation,
  required CockpitMonotonicClock clock,
  required CockpitMonotonicDeadline deadline,
}) async {
  final remaining = deadline.remaining;
  if (remaining == Duration.zero) {
    throw const CockpitDeadlineExceeded();
  }
  final first = await Future.any<_CockpitDeadlineRace<T>>(
    <Future<_CockpitDeadlineRace<T>>>[
      operation.then<_CockpitDeadlineRace<T>>(
        _CockpitDeadlineResult<T>.new,
        onError: (Object error, StackTrace stackTrace) =>
            _CockpitDeadlineError<T>(error, stackTrace),
      ),
      clock
          .delay(remaining)
          .then<_CockpitDeadlineRace<T>>((_) => _CockpitDeadlineTimeout<T>()),
    ],
  );
  return switch (first) {
    _CockpitDeadlineResult<T>(:final value) => value,
    _CockpitDeadlineError<T>(:final error, :final stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace),
    _CockpitDeadlineTimeout<T>() => throw const CockpitDeadlineExceeded(),
  };
}

sealed class _CockpitDeadlineRace<T> {
  const _CockpitDeadlineRace();
}

final class _CockpitDeadlineResult<T> extends _CockpitDeadlineRace<T> {
  const _CockpitDeadlineResult(this.value);

  final T value;
}

final class _CockpitDeadlineError<T> extends _CockpitDeadlineRace<T> {
  const _CockpitDeadlineError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _CockpitDeadlineTimeout<T> extends _CockpitDeadlineRace<T> {
  const _CockpitDeadlineTimeout();
}
