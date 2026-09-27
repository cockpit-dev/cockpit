import 'dart:async';

import 'package:flutter/scheduler.dart';

typedef CockpitEndOfFrameWaiter = Future<void> Function();

const String cockpitFrameTimeoutDegradationReason = 'frameTimeout';

enum CockpitPendingFrameWaitResult { noPendingFrame, completed, timedOut }

Future<CockpitPendingFrameWaitResult> waitForPendingCockpitFrame({
  required SchedulerPhase phase,
  required bool hasScheduledFrame,
  required CockpitEndOfFrameWaiter waitForEndOfFrame,
  Duration timeout = const Duration(milliseconds: 250),
}) async {
  if (phase == SchedulerPhase.idle && !hasScheduledFrame) {
    return CockpitPendingFrameWaitResult.noPendingFrame;
  }
  try {
    await waitForEndOfFrame().timeout(timeout);
    return CockpitPendingFrameWaitResult.completed;
  } on TimeoutException {
    return CockpitPendingFrameWaitResult.timedOut;
  }
}
