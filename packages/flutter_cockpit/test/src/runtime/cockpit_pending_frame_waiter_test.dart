import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_pending_frame_waiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports no pending frame without waiting while Flutter is idle',
    () async {
      var waitCount = 0;

      final result = await waitForPendingCockpitFrame(
        phase: SchedulerPhase.idle,
        hasScheduledFrame: false,
        waitForEndOfFrame: () async {
          waitCount += 1;
        },
      );

      expect(result, CockpitPendingFrameWaitResult.noPendingFrame);
      expect(waitCount, 0);
    },
  );

  test('reports completion when a pending frame finishes', () async {
    final result = await waitForPendingCockpitFrame(
      phase: SchedulerPhase.transientCallbacks,
      hasScheduledFrame: true,
      waitForEndOfFrame: () async {},
    );

    expect(result, CockpitPendingFrameWaitResult.completed);
  });

  test('reports timeout when a pending frame cannot finish', () async {
    final frame = Completer<void>();

    final result = await waitForPendingCockpitFrame(
      phase: SchedulerPhase.transientCallbacks,
      hasScheduledFrame: true,
      waitForEndOfFrame: () => frame.future,
      timeout: const Duration(milliseconds: 1),
    );

    expect(result, CockpitPendingFrameWaitResult.timedOut);
  });
}
