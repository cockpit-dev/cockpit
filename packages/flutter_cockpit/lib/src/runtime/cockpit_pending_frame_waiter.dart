import 'dart:async';

import 'package:flutter/scheduler.dart';

typedef CockpitEndOfFrameWaiter = Future<void> Function();

Future<void> waitForPendingCockpitFrame({
  required SchedulerPhase phase,
  required bool hasScheduledFrame,
  required CockpitEndOfFrameWaiter waitForEndOfFrame,
  Duration timeout = const Duration(milliseconds: 250),
}) async {
  if (phase == SchedulerPhase.idle && !hasScheduledFrame) {
    return;
  }
  try {
    await waitForEndOfFrame().timeout(timeout);
  } on TimeoutException {
    // A paused or backgrounded engine may not produce another frame. The
    // mounted Element tree remains safe to inspect in that state.
  }
}
