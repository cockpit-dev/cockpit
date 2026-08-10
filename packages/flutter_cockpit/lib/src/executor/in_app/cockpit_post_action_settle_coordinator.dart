import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../control/cockpit_command.dart';
import '../../control/cockpit_command_type.dart';
import '../../runtime/cockpit_ui_idle_waiter.dart';
import 'cockpit_command_context.dart';

typedef CockpitRouteTargetsWaiter =
    Future<bool> Function(String? previousRouteName);
typedef CockpitUsesTestBindingProbe = bool Function();

const Duration _hiddenVisualFrameBudget = Duration(milliseconds: 640);
const Duration _hiddenVisualFrameInterval = Duration(milliseconds: 16);
const Duration _hiddenVisualTransitionDuration = Duration(milliseconds: 320);
const int _hiddenVisualMinimumFrameCount = 2;

final class CockpitPostActionSettleCoordinator {
  CockpitPostActionSettleCoordinator({
    required CockpitInAppCommandContext context,
    CockpitUsesTestBindingProbe? usesTestBinding,
  }) : _context = context,
       _usesTestBinding = usesTestBinding ?? _defaultUsesTestBinding;

  final CockpitInAppCommandContext _context;
  final CockpitUsesTestBindingProbe _usesTestBinding;

  bool get isHiddenVisualSurface {
    if (!_supportsHiddenFrameDriving()) {
      return false;
    }
    try {
      final binding = WidgetsBinding.instance;
      return !_isTestBinding(binding) && !binding.framesEnabled;
    } on Object {
      return false;
    }
  }

  Future<void> settleBeforeObservation() async {
    if (isHiddenVisualSurface) {
      await Future<void>.microtask(() {});
      return;
    }
    await waitForCockpitUiIdle(
      quietWindow: _context.interactionPolicy.uiIdleQuietWindow,
      timeout: _context.interactionPolicy.uiIdleTimeout,
      waitTick: _context.waitTickHandler,
      includeNetworkIdle: false,
    );
  }

  Future<void> bestEffortWaitForUiIdle({
    required bool includeNetworkIdle,
  }) async {
    await waitForCockpitUiIdle(
      quietWindow: _context.interactionPolicy.uiIdleQuietWindow,
      timeout: _context.interactionPolicy.uiIdleTimeout,
      waitTick: _context.waitTickHandler,
      waitForNetworkIdle: _context.waitForNetworkIdleHandler,
      includeNetworkIdle: includeNetworkIdle,
    );
  }

  Future<void> prepareForAction(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) async {
    await _context.postActionSettler();
    await settleBeforeObservation();
    await _waitForPreActionContinuity(command, commandType: commandType);
  }

  Future<void> stabilizeAfterAction(
    String? previousRouteName, {
    required CockpitCommandType? commandType,
    required CockpitRouteTargetsWaiter waitForRouteTargets,
  }) async {
    await driveHiddenVisualFrames(commandType);
    await _context.postActionSettler();
    await _waitForGestureCommit(commandType);
    final routeChanged = await waitForRouteTargets(previousRouteName);
    await settleBeforeObservation();
    await _waitForVisualContinuity(
      commandType: commandType,
      routeChanged: routeChanged,
    );
  }

  Future<void> _waitForGestureCommit(CockpitCommandType? commandType) async {
    if (commandType != CockpitCommandType.tap &&
        commandType != CockpitCommandType.doubleTap &&
        commandType != CockpitCommandType.longPress) {
      return;
    }
    WidgetsBinding widgetsBinding;
    try {
      widgetsBinding = WidgetsBinding.instance;
    } on Object {
      return;
    }
    if (_isTestBinding(widgetsBinding)) {
      return;
    }
    if (isHiddenVisualSurface) {
      return;
    }
    final commitDelay = switch (commandType) {
      CockpitCommandType.longPress => const Duration(milliseconds: 32),
      CockpitCommandType.tap || CockpitCommandType.doubleTap =>
        kDoubleTapTimeout + const Duration(milliseconds: 32),
      _ => Duration.zero,
    };
    if (commitDelay > Duration.zero) {
      await Future<void>.delayed(commitDelay);
    }
  }

  Future<void> _waitForVisualContinuity({
    required CockpitCommandType? commandType,
    required bool routeChanged,
  }) async {
    if (_usesTestBinding() && !_context.hasCustomWaitTickHandler) {
      return;
    }
    if (isHiddenVisualSurface) {
      return;
    }
    final delay = _visualContinuityDelay(
      commandType: commandType,
      routeChanged: routeChanged,
    );
    if (delay <= Duration.zero) {
      return;
    }
    await _context.waitTickHandler(delay);
  }

  Future<void> _waitForPreActionContinuity(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) async {
    if (_usesTestBinding() && !_context.hasCustomWaitTickHandler) {
      return;
    }
    if (isHiddenVisualSurface) {
      return;
    }
    final delay = _preActionVisualDelay(command, commandType: commandType);
    if (delay <= Duration.zero) {
      return;
    }
    await _context.waitTickHandler(delay);
  }

  Duration _preActionVisualDelay(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) {
    if (!_isVisualMutation(commandType)) {
      return Duration.zero;
    }
    return _durationFromOptionalPositiveInt(
      command,
      key: 'preActionVisualDelayMs',
      fallback: _context.isRecordingActive()
          ? _maxDuration(
              _context.interactionPolicy.preActionVisualDelay,
              _context.interactionPolicy.recordingPreActionVisualDelay,
            )
          : _context.interactionPolicy.preActionVisualDelay,
    );
  }

  Duration _visualContinuityDelay({
    required CockpitCommandType? commandType,
    required bool routeChanged,
  }) {
    if (!_isVisualMutation(commandType) && !routeChanged) {
      return Duration.zero;
    }
    if (_context.isRecordingActive()) {
      return routeChanged
          ? _maxDuration(
              _context.interactionPolicy.routeTransitionVisualDelay,
              _context.interactionPolicy.recordingActionVisualDelay,
            )
          : _context.interactionPolicy.recordingActionVisualDelay;
    }
    return routeChanged
        ? _context.interactionPolicy.routeTransitionVisualDelay
        : _context.interactionPolicy.actionVisualDelay;
  }

  /// Advances a bounded synthetic frame timeline when a hidden desktop or web
  /// surface cannot receive ordinary vsync callbacks.
  Future<void> driveHiddenVisualFrames(
    CockpitCommandType? commandType, {
    int? baselineTransientCallbackCount,
  }) async {
    if (!_isVisualMutation(commandType) || !isHiddenVisualSurface) {
      return;
    }
    WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } on Object {
      return;
    }
    final budget = _minDuration(
      _hiddenVisualFrameBudget,
      _context.interactionPolicy.actionCommitTimeout,
    );
    final frameOffsets = _hiddenFrameOffsets(commandType, budget);
    final minimumFrameCount = _minimumHiddenFrameCount(
      commandType,
      frameOffsets.length,
    );
    final rawTimeOrigin = binding.currentSystemFrameTimeStamp;
    var forcedFrameCount = 0;
    try {
      while (forcedFrameCount < frameOffsets.length) {
        final callbacks = binding.transientCallbackCount;
        final returnedToBaseline = baselineTransientCallbackCount == null
            ? callbacks == 0
            : callbacks <= baselineTransientCallbackCount;
        if (binding.framesEnabled ||
            (forcedFrameCount >= minimumFrameCount && returnedToBaseline)) {
          return;
        }
        if (binding.schedulerPhase != SchedulerPhase.idle) {
          return;
        }

        final frameOffset = frameOffsets[forcedFrameCount];
        forcedFrameCount += 1;
        binding.handleBeginFrame(rawTimeOrigin + frameOffset);
        await Future<void>.microtask(() {});
        binding.handleDrawFrame();
        await Future<void>.microtask(() {});
      }
    } finally {
      if (forcedFrameCount > 0) {
        binding.resetEpoch();
      }
    }
  }

  int _minimumHiddenFrameCount(
    CockpitCommandType? commandType,
    int availableFrameCount,
  ) {
    final desired = _mayStartVisualTransition(commandType)
        ? 3
        : _hiddenVisualMinimumFrameCount;
    return desired < availableFrameCount ? desired : availableFrameCount;
  }

  List<Duration> _hiddenFrameOffsets(
    CockpitCommandType? commandType,
    Duration budget,
  ) {
    final offsets = <Duration>[];

    void addOffset(Duration offset) {
      final bounded = _minDuration(offset, budget);
      if (bounded <= Duration.zero ||
          (offsets.isNotEmpty && bounded <= offsets.last)) {
        return;
      }
      offsets.add(bounded);
    }

    addOffset(_hiddenVisualFrameInterval);
    if (_mayStartVisualTransition(commandType)) {
      addOffset(_hiddenVisualTransitionDuration);
      addOffset(_hiddenVisualTransitionDuration + _hiddenVisualFrameInterval);
    } else {
      addOffset(_hiddenVisualFrameInterval * _hiddenVisualMinimumFrameCount);
    }
    var nextOffset = offsets.isEmpty
        ? _hiddenVisualFrameInterval
        : offsets.last + _hiddenVisualFrameInterval;
    while (nextOffset <= budget) {
      offsets.add(nextOffset);
      nextOffset += _hiddenVisualFrameInterval;
    }
    return offsets;
  }

  bool _mayStartVisualTransition(CockpitCommandType? commandType) {
    return switch (commandType) {
      CockpitCommandType.tap ||
      CockpitCommandType.doubleTap ||
      CockpitCommandType.longPress ||
      CockpitCommandType.drag ||
      CockpitCommandType.fling ||
      CockpitCommandType.swipe ||
      CockpitCommandType.pinchZoom ||
      CockpitCommandType.rotate ||
      CockpitCommandType.panZoom ||
      CockpitCommandType.multiTouch ||
      CockpitCommandType.scrollUntilVisible ||
      CockpitCommandType.showOnScreen ||
      CockpitCommandType.increase ||
      CockpitCommandType.decrease ||
      CockpitCommandType.dismiss ||
      CockpitCommandType.back => true,
      _ => false,
    };
  }

  bool _supportsHiddenFrameDriving() {
    return switch (_context.platform.trim().toLowerCase()) {
      'macos' || 'windows' || 'linux' || 'web' => true,
      _ => false,
    };
  }

  bool _isVisualMutation(CockpitCommandType? commandType) {
    return switch (commandType) {
      CockpitCommandType.tap ||
      CockpitCommandType.focusTextInput ||
      CockpitCommandType.setTextEditingValue ||
      CockpitCommandType.sendTextInputAction ||
      CockpitCommandType.doubleTap ||
      CockpitCommandType.longPress ||
      CockpitCommandType.drag ||
      CockpitCommandType.fling ||
      CockpitCommandType.swipe ||
      CockpitCommandType.pinchZoom ||
      CockpitCommandType.rotate ||
      CockpitCommandType.panZoom ||
      CockpitCommandType.multiTouch ||
      CockpitCommandType.scrollUntilVisible ||
      CockpitCommandType.enterText ||
      CockpitCommandType.sendKeyEvent ||
      CockpitCommandType.sendKeyDownEvent ||
      CockpitCommandType.sendKeyUpEvent ||
      CockpitCommandType.showOnScreen ||
      CockpitCommandType.increase ||
      CockpitCommandType.decrease ||
      CockpitCommandType.dismiss ||
      CockpitCommandType.back => true,
      _ => false,
    };
  }

  Duration _durationFromOptionalPositiveInt(
    CockpitCommand command, {
    required String key,
    required Duration fallback,
  }) {
    final value = command.parameters[key];
    final durationMs = switch (value) {
      int() => value,
      num() => value.toInt(),
      _ => null,
    };
    if (durationMs == null) {
      return fallback;
    }
    if (durationMs <= 0) {
      throw ArgumentError('$key must be positive.');
    }
    return Duration(milliseconds: durationMs);
  }

  Duration _maxDuration(Duration left, Duration right) {
    return left >= right ? left : right;
  }

  Duration _minDuration(Duration left, Duration right) {
    return left <= right ? left : right;
  }

  static bool _defaultUsesTestBinding() {
    try {
      return _isTestBinding(WidgetsBinding.instance);
    } on Object {
      return false;
    }
  }

  static bool _isTestBinding(WidgetsBinding widgetsBinding) {
    return widgetsBinding.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }
}
