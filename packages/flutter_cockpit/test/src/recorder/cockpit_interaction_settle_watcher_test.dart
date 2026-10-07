import 'package:flutter_cockpit/src/recorder/cockpit_interaction_settle_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives a settle watch entirely through the fake clock: periodic timers
/// only advance when the binding pumps, so each `pump(tick)` is one tick.
void main() {
  const Duration tick = Duration(milliseconds: 50);

  CockpitInteractionSettleWatcher watch({
    required Duration quietWindow,
    required Duration timeout,
    required List<int> settled,
    required List<int> finished,
    bool Function()? isSchedulerIdle,
  }) {
    return CockpitInteractionSettleWatcher(
      quietWindow: quietWindow,
      timeout: timeout,
      isSchedulerIdle: isSchedulerIdle ?? (() => true),
      onSettled: settled.add,
      onFinished: () => finished.add(0),
      tickPeriod: tick,
    );
  }

  testWidgets('reports the elapsed quiet time once the window holds', (
    tester,
  ) async {
    final settled = <int>[];
    final finished = <int>[];
    final watcher = watch(
      quietWindow: const Duration(milliseconds: 100),
      timeout: const Duration(seconds: 5),
      settled: settled,
      finished: finished,
    );

    watcher.start();
    expect(watcher.isRunning, isTrue);

    // Tick 1 records quiet start; tick 2 reaches 50ms of quiet; tick 3
    // reaches 100ms and settles at an elapsed 150ms.
    await tester.pump(tick);
    await tester.pump(tick);
    expect(settled, isEmpty);
    await tester.pump(tick);

    expect(settled, <int>[150]);
    expect(finished, <int>[0]);
    expect(watcher.isRunning, isFalse);
  });

  testWidgets('a busy tick resets the quiet accumulation', (tester) async {
    final settled = <int>[];
    final finished = <int>[];
    var busy = true;
    final watcher = watch(
      quietWindow: const Duration(milliseconds: 100),
      timeout: const Duration(seconds: 5),
      settled: settled,
      finished: finished,
      isSchedulerIdle: () => !busy,
    );

    watcher.start();
    // Two busy ticks: nothing accumulates.
    await tester.pump(tick);
    await tester.pump(tick);
    // Quiet from tick 3: quiet window spans ticks 3-4-5, settling at 250ms.
    busy = false;
    await tester.pump(tick);
    await tester.pump(tick);
    expect(settled, isEmpty);
    await tester.pump(tick);

    expect(settled, <int>[250]);
    expect(finished, hasLength(1));
  });

  testWidgets('times out without back-filling the settle time', (tester) async {
    final settled = <int>[];
    final finished = <int>[];
    final watcher = watch(
      // The quiet window cannot fit inside the timeout.
      quietWindow: const Duration(seconds: 30),
      timeout: const Duration(milliseconds: 200),
      settled: settled,
      finished: finished,
    );

    watcher.start();
    for (var index = 0; index < 4; index += 1) {
      await tester.pump(tick);
    }

    expect(settled, isEmpty);
    expect(finished, hasLength(1));
    expect(watcher.isRunning, isFalse);
  });

  testWidgets('timeout wins when both mature on the same tick', (tester) async {
    final settled = <int>[];
    final finished = <int>[];
    final watcher = watch(
      // Quiet completes exactly at the 200ms tick that also hits the bound.
      quietWindow: const Duration(milliseconds: 150),
      timeout: const Duration(milliseconds: 200),
      settled: settled,
      finished: finished,
    );

    watcher.start();
    for (var index = 0; index < 4; index += 1) {
      await tester.pump(tick);
    }

    expect(settled, isEmpty);
    expect(finished, hasLength(1));
  });

  testWidgets('cancel stops silently and start stays idempotent', (
    tester,
  ) async {
    final settled = <int>[];
    final finished = <int>[];
    final watcher = watch(
      quietWindow: const Duration(milliseconds: 100),
      timeout: const Duration(seconds: 5),
      settled: settled,
      finished: finished,
    );

    watcher.start();
    // Starting again must not stack a second timer.
    watcher.start();
    watcher.cancel();
    watcher.cancel();
    expect(watcher.isRunning, isFalse);

    await tester.pump(const Duration(seconds: 5));

    expect(settled, isEmpty);
    expect(finished, isEmpty);
  });
}
