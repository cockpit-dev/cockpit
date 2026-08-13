import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_pending_frame_waiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'remote snapshot does not request a frame while Flutter is idle',
    () async {
      var waitCount = 0;

      await waitForPendingCockpitFrame(
        phase: SchedulerPhase.idle,
        hasScheduledFrame: false,
        waitForEndOfFrame: () async {
          waitCount += 1;
        },
      );

      expect(waitCount, 0);
    },
  );

  test(
    'remote snapshot continues when a pending frame cannot finish',
    () async {
      final frame = Completer<void>();

      await waitForPendingCockpitFrame(
        phase: SchedulerPhase.transientCallbacks,
        hasScheduledFrame: true,
        waitForEndOfFrame: () => frame.future,
        timeout: const Duration(milliseconds: 1),
      );
    },
  );
}
