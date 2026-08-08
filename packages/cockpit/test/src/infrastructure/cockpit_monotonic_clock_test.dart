import 'dart:async';

import 'package:cockpit/src/infrastructure/cockpit_monotonic_clock.dart';
import 'package:test/test.dart';

void main() {
  test('deadline race absorbs a losing operation error', () async {
    final clock = _ControlledClock();
    final operation = Completer<int>();
    final raced = cockpitRaceDeadline<int>(
      operation: operation.future,
      clock: clock,
      deadline: CockpitMonotonicDeadline.after(
        clock,
        const Duration(seconds: 1),
      ),
    );

    clock.advance(const Duration(seconds: 1));
    await expectLater(raced, throwsA(isA<CockpitDeadlineExceeded>()));

    operation.completeError(StateError('late operation failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('deadline race preserves an operation error that wins', () async {
    final clock = _ControlledClock();
    final operation = Completer<int>();
    final raced = cockpitRaceDeadline<int>(
      operation: operation.future,
      clock: clock,
      deadline: CockpitMonotonicDeadline.after(
        clock,
        const Duration(seconds: 1),
      ),
    );

    operation.completeError(ArgumentError('primary failure'));

    await expectLater(
      raced,
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'primary failure',
        ),
      ),
    );
  });
}

final class _ControlledClock implements CockpitMonotonicClock {
  Duration _elapsed = Duration.zero;
  final List<_ControlledDelay> _delays = <_ControlledDelay>[];

  @override
  Duration get elapsed => _elapsed;

  @override
  DateTime get utcNow => DateTime.utc(2026).add(_elapsed);

  @override
  Future<void> delay(Duration duration) {
    final delay = _ControlledDelay(_elapsed + duration);
    _delays.add(delay);
    return delay.completer.future;
  }

  void advance(Duration duration) {
    _elapsed += duration;
    for (final delay in _delays) {
      if (!delay.completer.isCompleted && delay.deadline <= _elapsed) {
        delay.completer.complete();
      }
    }
  }
}

final class _ControlledDelay {
  _ControlledDelay(this.deadline);

  final Duration deadline;
  final Completer<void> completer = Completer<void>();
}
