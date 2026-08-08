import 'dart:async';

final class CockpitRemoteReadBudget {
  const CockpitRemoteReadBudget(this.deadline);

  final DateTime? deadline;

  Duration? remaining() {
    final value = deadline;
    if (value == null) return null;
    final remaining = value.toUtc().difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Remote read deadline expired.');
    }
    return remaining;
  }

  Duration bound(Duration requested) {
    final available = remaining();
    if (available == null || requested <= available) return requested;
    return available;
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
