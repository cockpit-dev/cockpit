import 'package:flutter_cockpit/src/runtime/cockpit_ui_idle_waiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frame ensurer is followed by a fresh idle window', () async {
    var now = DateTime.utc(2026);
    var framePending = false;
    var ensureCount = 0;

    final settled = await waitForCockpitSchedulerQuiet(
      deadline: now.add(const Duration(seconds: 1)),
      quietWindow: const Duration(milliseconds: 16),
      waitTick: (duration) async {
        now = now.add(duration);
        framePending = false;
      },
      isIdle: () => !framePending,
      ensureVisualFrame: () async {
        ensureCount += 1;
        if (ensureCount == 1) framePending = true;
        return framePending;
      },
      clock: () => now,
    );

    expect(settled, isTrue);
    expect(ensureCount, 2);
  });

  test(
    'scheduled-frame waiter remains the fallback without an ensurer',
    () async {
      var now = DateTime.utc(2026);
      var framePending = true;
      var waitCount = 0;

      final settled = await waitForCockpitSchedulerQuiet(
        deadline: now.add(const Duration(seconds: 1)),
        quietWindow: const Duration(milliseconds: 16),
        waitTick: (duration) async => now = now.add(duration),
        isIdle: () => !framePending,
        waitForScheduledFrame: () async {
          waitCount += 1;
          framePending = false;
        },
        clock: () => now,
      );

      expect(settled, isTrue);
      expect(waitCount, 1);
    },
  );
}
