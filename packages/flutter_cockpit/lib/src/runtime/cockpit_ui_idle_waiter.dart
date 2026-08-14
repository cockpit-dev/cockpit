import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

typedef CockpitUiIdleTickHandler = Future<void> Function(Duration duration);
typedef CockpitUiIdleNetworkWaiter =
    Future<bool> Function({
      required Duration quietWindow,
      required Duration timeout,
    });
typedef CockpitUiIdleVisualFrameEnsurer = Future<bool> Function();
typedef CockpitUiIdleStateProbe = bool Function();
typedef CockpitUiIdleClock = DateTime Function();
typedef CockpitUiIdleScheduledFrameWaiter = Future<void> Function();

Future<bool> waitForCockpitUiIdle({
  required Duration quietWindow,
  required Duration timeout,
  required CockpitUiIdleTickHandler waitTick,
  CockpitUiIdleNetworkWaiter? waitForNetworkIdle,
  CockpitUiIdleVisualFrameEnsurer? ensureVisualFrame,
  bool includeNetworkIdle = true,
}) async {
  final deadline = DateTime.now().add(timeout);

  final schedulerSettled = await _waitForSchedulerQuiet(
    deadline: deadline,
    quietWindow: quietWindow,
    waitTick: waitTick,
    ensureVisualFrame: ensureVisualFrame,
  );
  if (!schedulerSettled) {
    return false;
  }

  if (!includeNetworkIdle || waitForNetworkIdle == null) {
    return true;
  }

  final remainingBeforeNetwork = deadline.difference(DateTime.now());
  if (remainingBeforeNetwork <= Duration.zero) {
    return false;
  }

  final networkSettled = await waitForNetworkIdle(
    quietWindow: quietWindow,
    timeout: remainingBeforeNetwork,
  );
  if (!networkSettled) {
    return false;
  }

  return _waitForSchedulerQuiet(
    deadline: deadline,
    quietWindow: quietWindow,
    waitTick: waitTick,
    ensureVisualFrame: ensureVisualFrame,
  );
}

Future<bool> _waitForSchedulerQuiet({
  required DateTime deadline,
  required Duration quietWindow,
  required CockpitUiIdleTickHandler waitTick,
  required CockpitUiIdleVisualFrameEnsurer? ensureVisualFrame,
}) async {
  SchedulerBinding schedulerBinding;
  WidgetsBinding widgetsBinding;
  try {
    schedulerBinding = SchedulerBinding.instance;
    widgetsBinding = WidgetsBinding.instance;
  } on Object {
    return true;
  }

  if (_isTestBinding(widgetsBinding)) {
    return true;
  }

  return waitForCockpitSchedulerQuiet(
    deadline: deadline,
    quietWindow: quietWindow,
    waitTick: waitTick,
    isIdle: () =>
        schedulerBinding.schedulerPhase == SchedulerPhase.idle &&
        !schedulerBinding.hasScheduledFrame,
    ensureVisualFrame: ensureVisualFrame,
    waitForScheduledFrame: () =>
        _awaitFrameIfScheduled(schedulerBinding, widgetsBinding),
  );
}

Future<bool> waitForCockpitSchedulerQuiet({
  required DateTime deadline,
  required Duration quietWindow,
  required CockpitUiIdleTickHandler waitTick,
  required CockpitUiIdleStateProbe isIdle,
  CockpitUiIdleVisualFrameEnsurer? ensureVisualFrame,
  CockpitUiIdleScheduledFrameWaiter? waitForScheduledFrame,
  CockpitUiIdleClock clock = DateTime.now,
}) async {
  DateTime? quietSince;
  while (clock().isBefore(deadline)) {
    await Future<void>.microtask(() {});
    if (isIdle()) {
      quietSince ??= clock();
      if (clock().difference(quietSince) >= quietWindow) {
        await ensureVisualFrame?.call();
        await Future<void>.microtask(() {});
        if (isIdle()) return true;
        quietSince = null;
      }
    } else {
      quietSince = null;
      if (ensureVisualFrame != null) {
        await ensureVisualFrame();
      } else {
        await waitForScheduledFrame?.call();
      }
    }
    await waitTick(const Duration(milliseconds: 16));
  }
  return false;
}

Future<void> _awaitFrameIfScheduled(
  SchedulerBinding schedulerBinding,
  WidgetsBinding widgetsBinding,
) async {
  if (!schedulerBinding.hasScheduledFrame) {
    return;
  }
  try {
    await widgetsBinding.endOfFrame.timeout(const Duration(milliseconds: 50));
  } on TimeoutException {
    return;
  }
}

bool _isTestBinding(WidgetsBinding widgetsBinding) {
  return widgetsBinding.runtimeType.toString().contains(
    'TestWidgetsFlutterBinding',
  );
}
