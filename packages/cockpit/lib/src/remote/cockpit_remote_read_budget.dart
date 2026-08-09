import 'dart:async';

final class CockpitRemoteReadBudget {
  CockpitRemoteReadBudget(this.deadline, {DateTime Function()? utcNow})
    : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final DateTime? deadline;
  final DateTime Function() _utcNow;

  Duration? remaining() {
    final value = deadline;
    if (value == null) return null;
    final remaining = value.toUtc().difference(_utcNow());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Remote read deadline expired.');
    }
    return remaining;
  }

  Duration bound(Duration requested, {Duration reserve = Duration.zero}) {
    if (reserve < Duration.zero) {
      throw ArgumentError.value(reserve, 'reserve');
    }
    final available = remaining();
    if (available == null) return requested;
    final usable = available - reserve;
    if (usable <= Duration.zero) {
      throw TimeoutException('Remote read deadline has no response budget.');
    }
    return requested <= usable ? requested : usable;
  }

  Future<T> run<T>(Future<T> Function() operation) {
    final available = remaining();
    final future = operation();
    return available == null ? future : future.timeout(available);
  }

  Future<void> delay(Duration duration) {
    final available = remaining();
    if (available == null) return Future<void>.delayed(duration);
    if (duration >= available) {
      return Future<void>.delayed(
        available,
      ).then((_) => throw TimeoutException('Remote read deadline expired.'));
    }
    return Future<void>.delayed(duration);
  }
}
