// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../capture/cockpit_screenshot_inspector.dart';
import '../control/cockpit_capture_failure_policy.dart';
import '../control/cockpit_command.dart';
import '../control/cockpit_command_execution.dart';
import '../control/cockpit_command_result.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../control/cockpit_screenshot_request.dart';
import '../errors/cockpit_command_error.dart';
import '../executor/cockpit_command_executor.dart';
import '../executor/in_app/cockpit_capture_orchestrator.dart';
import '../executor/in_app/cockpit_command_context.dart';
import '../executor/in_app/cockpit_command_router.dart';
import '../executor/in_app/cockpit_gesture_command_executor.dart';
import '../executor/in_app/cockpit_post_action_settle_coordinator.dart';
import '../executor/in_app/cockpit_semantic_command_executor.dart';
import '../executor/in_app/cockpit_text_input_command_executor.dart';
import '../executor/in_app/cockpit_wait_and_assert_executor.dart';
import '../gesture/cockpit_gesture_action.dart';
import '../gesture/cockpit_gesture_anchor.dart';
import '../gesture/cockpit_gesture_profile.dart';
import '../gesture/cockpit_multi_touch_sequence.dart';
import '../model/cockpit_artifact_ref.dart';
import '../runtime/cockpit_capabilities.dart';
import '../runtime/cockpit_focus_snapshot_builder.dart';
import '../runtime/cockpit_hit_test_miss_policy.dart';
import '../runtime/cockpit_interaction_policy.dart';
import '../runtime/cockpit_reveal_alignment.dart';
import '../runtime/cockpit_scroll_step_result.dart';
import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_snapshot_options.dart';
import '../runtime/cockpit_target.dart';
import '../runtime/cockpit_target_geometry_resolver.dart';
import '../runtime/cockpit_target_hit_test_inspector.dart';
import '../runtime/cockpit_target_registry.dart';
import '../runtime/cockpit_ui_idle_waiter.dart';
import '../runtime/cockpit_key_event_request.dart';
import '../runtime/cockpit_text_input_request.dart';

const int _defaultAssertSettleTimeoutMs = 1000;
const Duration _assertPollInterval = Duration(milliseconds: 16);
const int _routeTargetReadinessProbeLimit = 6;
const Duration _hardCommandTimeoutGrace = Duration(milliseconds: 250);
const Duration _platformClipboardAccessTimeout = Duration(seconds: 5);

enum _TapActivation { auto, direct, semantic, gesture }

enum _ActionCommitOutcome { actionCompleted, uiCommitted, timedOut }

enum _ActionActivationPath {
  direct,
  semantic,
  gesture,
  directTextInput,
  directEnterText,
  semanticTextInput,
  semanticEnterText,
}

final class InAppCockpitCommandExecutor implements CockpitCommandExecutor {
  InAppCockpitCommandExecutor({
    required CockpitTargetRegistry registry,
    CockpitCaptureHandler? captureHandler,
    CockpitSnapshotProvider? snapshotProvider,
    CockpitLocatorProbe? locatorProbe,
    CockpitPostActionSettler? postActionSettler,
    CockpitScrollStepHandler? scrollStepHandler,
    bool scrollStepProbesTarget = false,
    CockpitEnsureVisibleHandler? ensureVisibleHandler,
    CockpitGestureHandler? gestureHandler,
    CockpitNetworkActivityClearer? clearNetworkActivityHandler,
    CockpitNetworkIdleWaiter? waitForNetworkIdleHandler,
    CockpitBackNavigationHandler? backNavigationHandler,
    CockpitDismissActionResolver? dismissActionResolver,
    CockpitWaitTickHandler? waitTickHandler,
    CockpitKeyEventHandler? keyEventHandler,
    CockpitScreenshotInspector? screenshotInspector,
    CockpitInteractionPolicy interactionPolicy =
        const CockpitInteractionPolicy(),
    CockpitRecordingActivityProbe? isRecordingActive,
    CockpitRouteNameSynchronizer? routeNameSynchronizer,
    String platform = 'flutter',
    String transportType = 'inApp',
  }) : _context = CockpitInAppCommandContext(
         registry: registry,
         captureHandler: captureHandler,
         snapshotProvider:
             snapshotProvider ?? _defaultSnapshotProvider(registry),
         locatorProbe: locatorProbe,
         postActionSettler: postActionSettler ?? _defaultPostActionSettler,
         scrollStepHandler: scrollStepHandler,
         scrollStepProbesTarget: scrollStepProbesTarget,
         ensureVisibleHandler: ensureVisibleHandler,
         gestureHandler: gestureHandler,
         clearNetworkActivityHandler: clearNetworkActivityHandler,
         waitForNetworkIdleHandler: waitForNetworkIdleHandler,
         backNavigationHandler: backNavigationHandler,
         dismissActionResolver: dismissActionResolver,
         hasCustomWaitTickHandler: waitTickHandler != null,
         waitTickHandler: waitTickHandler ?? _defaultWaitTickHandler,
         keyEventHandler: keyEventHandler ?? _defaultKeyEventHandler,
         interactionPolicy: interactionPolicy,
         isRecordingActive: isRecordingActive ?? _defaultRecordingActivityProbe,
         routeNameSynchronizer: routeNameSynchronizer,
         platform: platform,
         transportType: transportType,
       ) {
    _settleCoordinator = CockpitPostActionSettleCoordinator(context: _context);
    _captureOrchestrator = CockpitCaptureOrchestrator(
      captureHandler: _context.captureHandler,
      postActionSettler: _context.postActionSettler,
      settleBeforeObservation: _settleCoordinator.settleBeforeObservation,
      bestEffortWaitForUiIdle: ({required includeNetworkIdleValue}) {
        return _settleCoordinator.bestEffortWaitForUiIdle(
          includeNetworkIdle: includeNetworkIdleValue,
        );
      },
      defaultSnapshotOptionsForReason: _defaultSnapshotOptionsForReason,
      screenshotInspector: screenshotInspector,
    );
    _semanticCommandExecutor = CockpitSemanticCommandExecutor(
      tap: _executeTap,
      longPress: _executeLongPress,
      doubleTap: _executeDoubleTap,
      showOnScreen: (command, stopwatch) {
        return _executeSemanticAction(
          command,
          stopwatch,
          requiredCommand: CockpitCommandType.showOnScreen,
          semanticAction: (target) => target.onSemanticShowOnScreen,
        );
      },
      increase: (command, stopwatch) {
        return _executeSemanticAction(
          command,
          stopwatch,
          requiredCommand: CockpitCommandType.increase,
          semanticAction: (target) => target.onSemanticIncrease,
        );
      },
      decrease: (command, stopwatch) {
        return _executeSemanticAction(
          command,
          stopwatch,
          requiredCommand: CockpitCommandType.decrease,
          semanticAction: (target) => target.onSemanticDecrease,
        );
      },
      dismiss: _executeDismiss,
    );
    _textInputCommandExecutor = CockpitTextInputCommandExecutor(
      enterText: _executeEnterText,
      eraseText: _executeEraseText,
      copyText: _executeCopyText,
      pasteText: _executePasteText,
      focusTextInput: _executeFocusTextInput,
      setTextEditingValue: _executeSetTextEditingValue,
      sendTextInputAction: _executeSendTextInputAction,
      sendKeyEvent: _executeKeyEvent,
      sendKeyDownEvent: _executeKeyEvent,
      sendKeyUpEvent: _executeKeyEvent,
    );
    _gestureCommandExecutor = CockpitGestureCommandExecutor(
      hover: _executeHover,
      wheel: _executeWheel,
      drag: _executeDrag,
      fling: _executeFling,
      swipe: _executeSwipe,
      pinchZoom: _executePinchZoom,
      rotate: _executeRotate,
      panZoom: _executePanZoom,
      multiTouch: _executeMultiTouch,
    );
    _waitAndAssertExecutor = CockpitWaitAndAssertExecutor(
      scrollUntilVisible: _executeScrollUntilVisible,
      waitForNetworkIdle: _executeWaitForNetworkIdle,
      waitForUiIdle: _executeWaitForUiIdle,
      assertVisible: _executeAssertVisible,
      assertText: _executeAssertText,
      waitFor: _executeWaitFor,
    );
    _commandRouter = CockpitCommandRouter(handlers: _buildCommandHandlers());
  }

  final CockpitInAppCommandContext _context;
  late final CockpitPostActionSettleCoordinator _settleCoordinator;
  late final CockpitCaptureOrchestrator _captureOrchestrator;
  late final CockpitCommandRouter _commandRouter;
  late final CockpitSemanticCommandExecutor _semanticCommandExecutor;
  late final CockpitTextInputCommandExecutor _textInputCommandExecutor;
  late final CockpitGestureCommandExecutor _gestureCommandExecutor;
  late final CockpitWaitAndAssertExecutor _waitAndAssertExecutor;
  String? _inAppClipboardText;

  CockpitTargetRegistry get _registry => _context.registry;
  CockpitCaptureHandler? get _captureHandler => _context.captureHandler;
  CockpitSnapshotProvider get _snapshotProvider => _context.snapshotProvider;
  CockpitPostActionSettler get _postActionSettler => _context.postActionSettler;
  CockpitScrollStepHandler? get _scrollStepHandler =>
      _context.scrollStepHandler;
  CockpitEnsureVisibleHandler? get _ensureVisibleHandler =>
      _context.ensureVisibleHandler;
  CockpitGestureHandler? get _gestureHandler => _context.gestureHandler;
  CockpitNetworkActivityClearer? get _clearNetworkActivityHandler =>
      _context.clearNetworkActivityHandler;
  CockpitNetworkIdleWaiter? get _waitForNetworkIdleHandler =>
      _context.waitForNetworkIdleHandler;
  CockpitBackNavigationHandler? get _backNavigationHandler =>
      _context.backNavigationHandler;
  CockpitDismissActionResolver? get _dismissActionResolver =>
      _context.dismissActionResolver;
  bool get _hasCustomWaitTickHandler => _context.hasCustomWaitTickHandler;
  CockpitWaitTickHandler get _waitTickHandler => _context.waitTickHandler;
  CockpitKeyEventHandler get _keyEventHandler => _context.keyEventHandler;
  CockpitInteractionPolicy get _interactionPolicy => _context.interactionPolicy;
  CockpitRecordingActivityProbe get _isRecordingActive =>
      _context.isRecordingActive;
  CockpitRouteNameSynchronizer? get _routeNameSynchronizer =>
      _context.routeNameSynchronizer;
  String get _platform => _context.platform;
  String get _transportType => _context.transportType;

  // In release builds semantic nodes can only be resolved through the live
  // SemanticsOwner tree, which requires the semantics tree to be enabled;
  // advertising the semantic-plane commands otherwise would fake capability.
  bool get _semanticPlaneResolvable {
    if (!kReleaseMode) {
      return true;
    }
    try {
      return SemanticsBinding.instance.semanticsEnabled;
    } on Object {
      return false;
    }
  }

  @override
  Future<CockpitCapabilities> describeCapabilities() async {
    final supportedCommands = <CockpitCommandType>{
      CockpitCommandType.tap,
      CockpitCommandType.enterText,
      CockpitCommandType.eraseText,
      CockpitCommandType.copyText,
      CockpitCommandType.pasteText,
      CockpitCommandType.focusTextInput,
      CockpitCommandType.setTextEditingValue,
      CockpitCommandType.sendTextInputAction,
      CockpitCommandType.sendKeyEvent,
      CockpitCommandType.sendKeyDownEvent,
      CockpitCommandType.sendKeyUpEvent,
      if (_semanticPlaneResolvable) ...<CockpitCommandType>{
        CockpitCommandType.showOnScreen,
        CockpitCommandType.increase,
        CockpitCommandType.decrease,
        CockpitCommandType.dismiss,
      },
      CockpitCommandType.dismissKeyboard,
      CockpitCommandType.longPress,
      CockpitCommandType.doubleTap,
      if (_gestureHandler != null) ...<CockpitCommandType>{
        CockpitCommandType.hover,
        CockpitCommandType.wheel,
        CockpitCommandType.drag,
        CockpitCommandType.fling,
        CockpitCommandType.swipe,
        CockpitCommandType.pinchZoom,
        CockpitCommandType.rotate,
        CockpitCommandType.panZoom,
        CockpitCommandType.multiTouch,
      },
      if (_scrollStepHandler != null) CockpitCommandType.scrollUntilVisible,
      if (_clearNetworkActivityHandler != null)
        CockpitCommandType.clearNetworkActivity,
      if (_waitForNetworkIdleHandler != null)
        CockpitCommandType.waitForNetworkIdle,
      CockpitCommandType.waitForUiIdle,
      if (_backNavigationHandler != null) CockpitCommandType.back,
      CockpitCommandType.assertVisible,
      CockpitCommandType.assertText,
      CockpitCommandType.waitFor,
      CockpitCommandType.collectSnapshot,
      if (_captureHandler != null) CockpitCommandType.captureScreenshot,
    };

    return CockpitCapabilities(
      platform: _platform,
      transportType: _transportType,
      supportsInAppControl: true,
      supportsFlutterViewCapture: _captureHandler != null,
      supportsNativeScreenCapture: false,
      supportsHostAutomation: false,
      supportedCommands: supportedCommands.toList(growable: false),
      supportedLocatorStrategies: CockpitLocatorKind.values,
    );
  }

  @override
  Future<CockpitCommandResult> execute(CockpitCommand command) async {
    return (await executeWithArtifacts(command)).result;
  }

  Future<CockpitCommandExecution> executeWithArtifacts(
    CockpitCommand command,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final commandTimeout = _hardCommandTimeout(command);
      final execution = _commandRouter.execute(command, stopwatch);
      if (commandTimeout == null) {
        return await execution;
      }
      // The grace lets in-command wait/assert loops that poll up to the same
      // budget finish first, so their detailed diagnostics win over the
      // generic hard-timeout failure.
      final enforcedTimeout = commandTimeout + _hardCommandTimeoutGrace;
      return await execution.timeout(
        enforcedTimeout,
        onTimeout: () => _commandTimeoutExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          timeoutMs: commandTimeout.inMilliseconds,
          enforcedTimeoutMs: enforcedTimeout.inMilliseconds,
        ),
      );
    } finally {
      stopwatch.stop();
    }
  }

  Duration? _hardCommandTimeout(CockpitCommand command) {
    final timeoutMs = command.timeoutMs;
    if (timeoutMs == null || timeoutMs <= 0) {
      return null;
    }
    return Duration(milliseconds: timeoutMs);
  }

  CockpitCommandExecution _commandTimeoutExecution({
    required CockpitCommand command,
    required int durationMs,
    required int timeoutMs,
    required int enforcedTimeoutMs,
  }) {
    final snapshot = _liveSnapshot();
    final expectedRouteName = _expectedRouteName(command);
    return _failureExecution(
      command: command,
      durationMs: durationMs,
      snapshot: snapshot.toJson(),
      error: CockpitCommandError.timeout(
        message:
            'Command ${command.commandId} exceeded its ${timeoutMs}ms timeout.',
        details: <String, Object?>{
          'commandId': command.commandId,
          'commandType': command.commandType.name,
          'timeoutMs': timeoutMs,
          'enforcedTimeoutMs': enforcedTimeoutMs,
          'expectedRouteName': ?expectedRouteName,
          'routeName': snapshot.routeName,
          'visibleTargetCount': _registry.visibleTargets.length,
          'routeReadyVisibleTargetCount':
              _registry.routeReadyVisibleTargets.length,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ).take(12).toList(growable: false),
          'targetDiscoveryDiagnostics': _registry.routeDiagnostics(),
          'emptyRouteHint': ?_emptyRouteHint(),
        },
      ),
    );
  }

  Map<CockpitCommandType, CockpitInAppCommandHandler> _buildCommandHandlers() {
    return <CockpitCommandType, CockpitInAppCommandHandler>{
      CockpitCommandType.tap: _semanticCommandExecutor.execute,
      CockpitCommandType.hover: _gestureCommandExecutor.execute,
      CockpitCommandType.wheel: _gestureCommandExecutor.execute,
      CockpitCommandType.enterText: _textInputCommandExecutor.execute,
      CockpitCommandType.eraseText: _textInputCommandExecutor.execute,
      CockpitCommandType.copyText: _textInputCommandExecutor.execute,
      CockpitCommandType.pasteText: _textInputCommandExecutor.execute,
      CockpitCommandType.focusTextInput: _textInputCommandExecutor.execute,
      CockpitCommandType.setTextEditingValue: _textInputCommandExecutor.execute,
      CockpitCommandType.sendTextInputAction: _textInputCommandExecutor.execute,
      CockpitCommandType.sendKeyEvent: _textInputCommandExecutor.execute,
      CockpitCommandType.sendKeyDownEvent: _textInputCommandExecutor.execute,
      CockpitCommandType.sendKeyUpEvent: _textInputCommandExecutor.execute,
      CockpitCommandType.longPress: _semanticCommandExecutor.execute,
      CockpitCommandType.doubleTap: _semanticCommandExecutor.execute,
      CockpitCommandType.drag: _gestureCommandExecutor.execute,
      CockpitCommandType.fling: _gestureCommandExecutor.execute,
      CockpitCommandType.swipe: _gestureCommandExecutor.execute,
      CockpitCommandType.pinchZoom: _gestureCommandExecutor.execute,
      CockpitCommandType.rotate: _gestureCommandExecutor.execute,
      CockpitCommandType.panZoom: _gestureCommandExecutor.execute,
      CockpitCommandType.multiTouch: _gestureCommandExecutor.execute,
      CockpitCommandType.scrollUntilVisible: _waitAndAssertExecutor.execute,
      CockpitCommandType.clearNetworkActivity: (command, stopwatch) async =>
          _executeClearNetworkActivity(command, stopwatch),
      CockpitCommandType.waitForNetworkIdle: _waitAndAssertExecutor.execute,
      CockpitCommandType.waitForUiIdle: _waitAndAssertExecutor.execute,
      CockpitCommandType.back: _executeBack,
      CockpitCommandType.showOnScreen: _semanticCommandExecutor.execute,
      CockpitCommandType.increase: _semanticCommandExecutor.execute,
      CockpitCommandType.decrease: _semanticCommandExecutor.execute,
      CockpitCommandType.dismiss: _semanticCommandExecutor.execute,
      CockpitCommandType.dismissKeyboard: _executeDismissKeyboard,
      CockpitCommandType.assertVisible: _waitAndAssertExecutor.execute,
      CockpitCommandType.assertText: _waitAndAssertExecutor.execute,
      CockpitCommandType.waitFor: _waitAndAssertExecutor.execute,
      CockpitCommandType.collectSnapshot: (command, stopwatch) async {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          snapshot: _snapshotProvider(
            options:
                command.snapshotOptions ??
                const CockpitSnapshotOptions.baseline(),
          ).toJson(),
        );
      },
      CockpitCommandType.captureScreenshot: _executeCaptureScreenshot,
    };
  }

  Future<CockpitCommandExecution> _executeTap(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    var previousRouteName = _currentRouteName();
    final coordinateOrigin = _pointParameter(command);
    if (command.locator == null && coordinateOrigin != null) {
      return _executeResolvedGesture(
        command: command,
        stopwatch: stopwatch,
        resolution: null,
        actionBuilder: () => CockpitGestureAction.tap(
          origin: coordinateOrigin,
          anchor: _gestureAnchorParameter(command),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
          buttons: _buttonsParameter(command),
        ),
      );
    }
    final resolution = await _resolveInteractiveTarget(
      command,
      requiredCommand: CockpitCommandType.tap,
    );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    final target = resolution.target!;
    if (previousRouteName == null || previousRouteName.isEmpty) {
      previousRouteName = _currentRouteName();
    }
    if ((previousRouteName == null || previousRouteName.isEmpty) &&
        target.routeName.isNotEmpty) {
      previousRouteName = target.routeName;
    }
    late final _TapActivation activation;
    try {
      activation = _tapActivationParameter(command);
    } on ArgumentError catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution.locatorResolution,
        error: CockpitCommandError.invalidGestureParameters(
          message:
              error.message?.toString() ?? 'Invalid tap activation parameter.',
          details: <String, Object?>{
            if (command.locator != null) 'locator': command.locator!.toJson(),
          },
        ),
      );
    }
    if (activation == _TapActivation.gesture) {
      final gestureResult = await _executeGestureAction(
        command: command,
        stopwatch: stopwatch,
        resolution: resolution,
        action: CockpitGestureAction.tap(
          target: target,
          anchor: _gestureAnchorParameter(command),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
          buttons: _buttonsParameter(command),
        ),
        previousRouteName: previousRouteName,
      );
      if (gestureResult != null) {
        return gestureResult;
      }
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution.locatorResolution,
        error: CockpitCommandError.unsupportedCapability(
          message:
              'Gesture activation is not available for this executor. Use the default activation or provide a gesture handler.',
          details: <String, Object?>{'activation': activation.name},
        ),
      );
    }
    if (activation != _TapActivation.semantic &&
        target.supportedCommands.contains(CockpitCommandType.tap) &&
        target.onTap != null) {
      final preflight = _preflightTargetHitTest(
        command: command,
        commandType: CockpitCommandType.tap,
        target: target,
      );
      if (preflight?.error != null) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          snapshot: _liveSnapshot().toJson(),
          error: preflight!.error!,
        );
      }
      await _prepareForAction(command, commandType: CockpitCommandType.tap);
      final commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: target.onTap!,
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.tap,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.direct,
      );
      if (commit.failure != null) {
        return commit.failure!;
      }
      await _stabilizeAfterAction(
        previousRouteName,
        commandType: CockpitCommandType.tap,
        routeAlreadyCommitted: commit.routeCommitted,
      );
      final routeExpectationFailure = await _validateExpectedRouteAfterAction(
        command: command,
        commandType: CockpitCommandType.tap,
        durationMs: stopwatch.elapsedMilliseconds,
        resolution: resolution,
        activationPath: _ActionActivationPath.direct,
        actionDiagnostics: commit.diagnostics,
        timeoutOverride:
            _autoGestureFallbackEligible(
              command: command,
              activation: activation,
              previousRouteName: previousRouteName,
            )
            ? _interactionPolicy.actionCommitTimeout
            : null,
      );
      if (routeExpectationFailure != null) {
        final fallback = await _tryAutoGestureFallback(
          command: command,
          stopwatch: stopwatch,
          resolution: resolution,
          activation: activation,
          previousRouteName: previousRouteName,
          failedActivation: 'direct',
        );
        if (fallback != null) {
          return fallback;
        }
        return routeExpectationFailure;
      }

      return _buildSuccessWithOptionalCapture(
        command: command,
        resolution: resolution,
        durationMs: stopwatch.elapsedMilliseconds,
        warnings: <Map<String, Object?>>[
          ...commit.warnings,
          if (preflight?.warning != null) preflight!.warning!,
        ],
        changed: _changedSince(commit),
      );
    }
    if (activation != _TapActivation.direct &&
        target.supportedCommands.contains(CockpitCommandType.tap) &&
        target.onSemanticTap != null) {
      await _prepareForAction(command, commandType: CockpitCommandType.tap);
      final commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: target.onSemanticTap!,
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.tap,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.semantic,
      );
      if (commit.failure != null) {
        return commit.failure!;
      }
      await _stabilizeAfterAction(
        previousRouteName,
        commandType: CockpitCommandType.tap,
        routeAlreadyCommitted: commit.routeCommitted,
      );
      final routeExpectationFailure = await _validateExpectedRouteAfterAction(
        command: command,
        commandType: CockpitCommandType.tap,
        durationMs: stopwatch.elapsedMilliseconds,
        resolution: resolution,
        activationPath: _ActionActivationPath.semantic,
        actionDiagnostics: commit.diagnostics,
        timeoutOverride:
            _autoGestureFallbackEligible(
              command: command,
              activation: activation,
              previousRouteName: previousRouteName,
            )
            ? _interactionPolicy.actionCommitTimeout
            : null,
      );
      if (routeExpectationFailure != null) {
        final fallback = await _tryAutoGestureFallback(
          command: command,
          stopwatch: stopwatch,
          resolution: resolution,
          activation: activation,
          previousRouteName: previousRouteName,
          failedActivation: 'semantic',
        );
        if (fallback != null) {
          return fallback;
        }
        return routeExpectationFailure;
      }
      return _buildSuccessWithOptionalCapture(
        command: command,
        resolution: resolution,
        durationMs: stopwatch.elapsedMilliseconds,
        warnings: commit.warnings,
        changed: _changedSince(commit),
      );
    }
    if (activation == _TapActivation.auto &&
        target.supportedCommands.contains(CockpitCommandType.tap) &&
        _gestureHandler != null) {
      final gestureResult = await _executeGestureAction(
        command: command,
        stopwatch: stopwatch,
        resolution: resolution,
        action: CockpitGestureAction.tap(
          target: target,
          anchor: _gestureAnchorParameter(command),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
          buttons: _buttonsParameter(command),
        ),
        previousRouteName: previousRouteName,
      );
      if (gestureResult != null) {
        return gestureResult;
      }
    }
    return _unsupportedExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      target: target,
    );
  }

  Future<CockpitCommandExecution> _executeHover(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final coordinateOrigin = _pointParameter(command);
    if (command.locator == null && coordinateOrigin != null) {
      return _executeResolvedGesture(
        command: command,
        stopwatch: stopwatch,
        resolution: null,
        actionBuilder: () => CockpitGestureAction.hover(
          origin: coordinateOrigin,
          anchor: _gestureAnchorParameter(command),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
        ),
      );
    }
    if (command.locator == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'hover requires either a locator or explicit coordinates.',
        ),
      );
    }
    final resolution = await _resolveInteractiveTarget(
      command,
      requiredCommand: CockpitCommandType.hover,
    );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }
    return _executeResolvedGesture(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      actionBuilder: () => CockpitGestureAction.hover(
        target: resolution.target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        pointerDeviceKind: _pointerDeviceKindParameter(command),
      ),
    );
  }

  Future<CockpitCommandExecution> _executeWheel(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final dx = _doubleParameter(command, 'dx') ?? 0;
    final dy = _doubleParameter(command, 'dy') ?? 0;
    if (!dx.isFinite || !dy.isFinite || (dx == 0 && dy == 0)) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'wheel requires a finite non-zero dx or dy.',
        ),
      );
    }
    final steps = _intParameter(command, 'steps') ?? 1;
    if (steps < 1 || steps > 1000) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'wheel steps must be between 1 and 1000.',
        ),
      );
    }
    final interval = _optionalDurationParameter(command, 'intervalMs');
    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => CockpitGestureAction.wheel(
        target: target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: Offset(dx, dy),
        steps: steps,
        interval: interval,
        pointerDeviceKind: _pointerDeviceKindParameter(
          command,
          allowTrackpad: true,
        ),
      ),
    );
  }

  bool _autoGestureFallbackEligible({
    required CockpitCommand command,
    required _TapActivation activation,
    required String? previousRouteName,
  }) {
    final currentRouteName = _currentRouteName();
    return activation == _TapActivation.auto &&
        _gestureHandler != null &&
        _expectedRouteName(command) != null &&
        (previousRouteName == null ||
            currentRouteName == null ||
            currentRouteName == previousRouteName);
  }

  Future<CockpitCommandExecution?> _tryAutoGestureFallback({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitTargetResolutionResult resolution,
    required _TapActivation activation,
    required String? previousRouteName,
    required String failedActivation,
  }) {
    if (!_autoGestureFallbackEligible(
      command: command,
      activation: activation,
      previousRouteName: previousRouteName,
    )) {
      return Future<CockpitCommandExecution?>.value();
    }
    return _executeGestureAction(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      action: CockpitGestureAction.tap(
        target: resolution.target,
        anchor: _gestureAnchorParameter(command),
        pointerDeviceKind: _pointerDeviceKindParameter(command),
        buttons: _buttonsParameter(command),
      ),
      previousRouteName: previousRouteName,
      warnings: <Map<String, Object?>>[
        <String, Object?>{
          'code': 'autoActivationGestureFallback',
          'message':
              'Auto activation fell back to a user-like gesture because the first activation path did not reach the expected route.',
          'details': <String, Object?>{
            'failedActivation': failedActivation,
            'expectedRouteName': _expectedRouteName(command),
            'routeName': _currentRouteName(),
          },
        },
      ],
    );
  }

  Future<CockpitCommandExecution> _executeLongPress(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final previousRouteName = _currentRouteName();
    final coordinateOrigin = _pointParameter(command);
    if (command.locator == null && coordinateOrigin != null) {
      return _executeResolvedGesture(
        command: command,
        stopwatch: stopwatch,
        resolution: null,
        actionBuilder: () => CockpitGestureAction.longPress(
          origin: coordinateOrigin,
          anchor: _gestureAnchorParameter(command),
          duration: _durationParameter(
            command,
            key: 'durationMs',
            fallbackMs: (kLongPressTimeout + kPressTimeout).inMilliseconds,
          ),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
          buttons: _buttonsParameter(command),
        ),
      );
    }
    if (command.locator == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message:
              'longPress requires either a locator or explicit coordinates.',
        ),
      );
    }
    final resolution = await _resolveInteractiveTarget(
      command,
      requiredCommand: CockpitCommandType.longPress,
    );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }
    final target = resolution.target!;
    // Prefer the direct widget callback whenever the source element exposes
    // one. A Semantics wrapper can inherit a merged long-press action from a
    // different node; invoking that node may report success without reaching
    // the callback that owns the matched control. The direct handler is the
    // source-faithful path for native Flutter controls.
    // A command that supplies duration asks for an actual pointer gesture.
    // Semantic callbacks cannot model the press duration and would make
    // custom timing silently ineffective.
    if (!command.parameters.containsKey('durationMs') &&
        target.supportedCommands.contains(CockpitCommandType.longPress) &&
        target.onLongPress != null) {
      final preflight = _preflightTargetHitTest(
        command: command,
        commandType: CockpitCommandType.longPress,
        target: target,
      );
      if (preflight?.error != null) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          snapshot: _liveSnapshot().toJson(),
          error: preflight!.error!,
        );
      }
      await _prepareForAction(
        command,
        commandType: CockpitCommandType.longPress,
      );
      final commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: target.onLongPress!,
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.longPress,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.direct,
      );
      if (commit.failure != null) {
        return commit.failure!;
      }
      await _stabilizeAfterAction(
        previousRouteName,
        commandType: CockpitCommandType.longPress,
        routeAlreadyCommitted: commit.routeCommitted,
      );
      return _buildSuccessWithOptionalCapture(
        command: command,
        resolution: resolution,
        durationMs: stopwatch.elapsedMilliseconds,
        warnings: <Map<String, Object?>>[
          ...commit.warnings,
          if (preflight?.warning != null) preflight!.warning!,
        ],
        changed: _changedSince(commit),
      );
    }
    if (!command.parameters.containsKey('durationMs') &&
        target.supportedCommands.contains(CockpitCommandType.longPress) &&
        target.onSemanticLongPress != null) {
      await _prepareForAction(
        command,
        commandType: CockpitCommandType.longPress,
      );
      final commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: target.onSemanticLongPress!,
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.longPress,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.semantic,
      );
      if (commit.failure != null) {
        return commit.failure!;
      }
      await _stabilizeAfterAction(
        previousRouteName,
        commandType: CockpitCommandType.longPress,
        routeAlreadyCommitted: commit.routeCommitted,
      );
      return _buildSuccessWithOptionalCapture(
        command: command,
        resolution: resolution,
        durationMs: stopwatch.elapsedMilliseconds,
        warnings: commit.warnings,
        changed: _changedSince(commit),
      );
    }
    return _executeResolvedGesture(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      actionBuilder: () => CockpitGestureAction.longPress(
        target: target,
        anchor: _gestureAnchorParameter(command),
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: (kLongPressTimeout + kPressTimeout).inMilliseconds,
        ),
        pointerDeviceKind: _pointerDeviceKindParameter(command),
        buttons: _buttonsParameter(command),
      ),
    );
  }

  Future<CockpitCommandExecution> _executeDoubleTap(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final previousRouteName = _currentRouteName();
    final coordinateOrigin = _pointParameter(command);
    if (command.locator == null && coordinateOrigin != null) {
      return _executeResolvedGesture(
        command: command,
        stopwatch: stopwatch,
        resolution: null,
        actionBuilder: () => CockpitGestureAction.doubleTap(
          origin: coordinateOrigin,
          anchor: _gestureAnchorParameter(command),
          interval: _durationParameter(
            command,
            key: 'intervalMs',
            fallbackMs: 90,
          ),
          pointerDeviceKind: _pointerDeviceKindParameter(command),
          buttons: _buttonsParameter(command),
        ),
      );
    }
    if (command.locator == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message:
              'doubleTap requires either a locator or explicit coordinates.',
        ),
      );
    }
    final resolution = await _resolveInteractiveTarget(
      command,
      requiredCommand: CockpitCommandType.doubleTap,
    );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }
    final target = resolution.target!;
    if (!command.parameters.containsKey('intervalMs') &&
        target.supportedCommands.contains(CockpitCommandType.doubleTap) &&
        target.onDoubleTap != null) {
      final preflight = _preflightTargetHitTest(
        command: command,
        commandType: CockpitCommandType.doubleTap,
        target: target,
      );
      if (preflight?.error != null) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          snapshot: _liveSnapshot().toJson(),
          error: preflight!.error!,
        );
      }
      await _prepareForAction(
        command,
        commandType: CockpitCommandType.doubleTap,
      );
      final commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: target.onDoubleTap!,
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.doubleTap,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.direct,
      );
      if (commit.failure != null) {
        return commit.failure!;
      }
      await _stabilizeAfterAction(
        previousRouteName,
        commandType: CockpitCommandType.doubleTap,
        routeAlreadyCommitted: commit.routeCommitted,
      );
      return _buildSuccessWithOptionalCapture(
        command: command,
        resolution: resolution,
        durationMs: stopwatch.elapsedMilliseconds,
        warnings: <Map<String, Object?>>[
          ...commit.warnings,
          if (preflight?.warning != null) preflight!.warning!,
        ],
        changed: _changedSince(commit),
      );
    }
    return _executeResolvedGesture(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      actionBuilder: () => CockpitGestureAction.doubleTap(
        target: target,
        anchor: _gestureAnchorParameter(command),
        interval: _durationParameter(
          command,
          key: 'intervalMs',
          fallbackMs: 90,
        ),
        pointerDeviceKind: _pointerDeviceKindParameter(command),
        buttons: _buttonsParameter(command),
      ),
    );
  }

  Future<CockpitCommandExecution> _executeDrag(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final dx = _doubleParameter(command, 'dx');
    final dy = _doubleParameter(command, 'dy');
    if (dx == null || dy == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'drag requires numeric dx and dy parameters.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => _buildDirectionalGesture(
        command: command,
        target: target,
        delta: Offset(dx, dy),
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 220,
        ),
        holdDuration: _optionalDurationParameter(command, 'holdDurationMs'),
        touchSlopX:
            _doubleParameter(command, 'touchSlopX') ??
            cockpitDefaultDragTouchSlop,
        touchSlopY:
            _doubleParameter(command, 'touchSlopY') ??
            cockpitDefaultDragTouchSlop,
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 0,
        fallbackType: CockpitCommandType.drag,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeSwipe(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final direction = _axisDirectionParameter(command.parameters['direction']);
    if (direction == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'swipe requires direction: up, down, left, or right.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => _buildSwipeGesture(
        command: command,
        target: target,
        direction: direction,
        distanceFactor: (_doubleParameter(command, 'distanceFactor') ?? 0.82)
            .clamp(0.15, 0.95),
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 200,
        ),
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 0,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeFling(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final dx = _doubleParameter(command, 'dx');
    final dy = _doubleParameter(command, 'dy');
    if (dx == null || dy == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'fling requires numeric dx and dy parameters.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => _buildDirectionalGesture(
        command: command,
        target: target,
        delta: Offset(dx, dy),
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 96,
        ),
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 50,
        fallbackType: CockpitCommandType.fling,
      ),
    );
  }

  Future<CockpitCommandExecution> _executePinchZoom(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final scale = _doubleParameter(command, 'scale');
    if (scale == null || scale <= 0) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'pinchZoom requires a positive scale parameter.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => _buildPinchZoomGesture(
        command: command,
        target: target,
        scale: scale,
        startSpan: _doubleParameter(command, 'startSpan') ?? 56,
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 220,
        ),
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 0,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeRotate(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final rotation = _doubleParameter(command, 'rotationRadians');
    if (rotation == null || rotation == 0) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'rotate requires a non-zero rotationRadians parameter.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => _buildRotateGesture(
        command: command,
        target: target,
        rotation: rotation,
        startSpan: _doubleParameter(command, 'startSpan') ?? 56,
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 220,
        ),
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 0,
      ),
    );
  }

  Future<CockpitCommandExecution> _executePanZoom(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final scale = _doubleParameter(command, 'scale') ?? 1.0;
    final rotation = _doubleParameter(command, 'rotationRadians') ?? 0.0;
    final panDx = _doubleParameter(command, 'panDx') ?? 0.0;
    final panDy = _doubleParameter(command, 'panDy') ?? 0.0;
    if (scale <= 0) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'panZoom requires a positive scale parameter.',
        ),
      );
    }
    if (scale == 1.0 && rotation == 0.0 && panDx == 0.0 && panDy == 0.0) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message:
              'panZoom requires pan, scale, or rotation parameters to change.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => CockpitGestureAction.panZoom(
        target: target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: Offset(panDx, panDy),
        scale: scale,
        rotation: rotation,
        duration: _durationParameter(
          command,
          key: 'durationMs',
          fallbackMs: 180,
        ),
        moveEventCount: _intParameter(command, 'moveEventCount') ?? 0,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeMultiTouch(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final rawSequence = command.parameters['sequence'];
    CockpitMultiTouchSequence? sequence;
    try {
      sequence = switch (rawSequence) {
        CockpitMultiTouchSequence() => rawSequence,
        Map<Object?, Object?>() => CockpitMultiTouchSequence.fromJson(
          Map<String, Object?>.from(rawSequence),
        ),
        _ => null,
      };
      if (sequence != null && sequence.steps.isEmpty) {
        throw const FormatException('Multi-touch sequence must not be empty.');
      }
    } on Object catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'Invalid multiTouch sequence.',
          details: <String, Object?>{'error': error.toString()},
        ),
      );
    }
    final validSequence = sequence;
    if (validSequence == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.invalidGestureParameters(
          message: 'multiTouch requires a valid sequence payload.',
        ),
      );
    }

    return _executeOptionalTargetGesture(
      command: command,
      stopwatch: stopwatch,
      actionBuilder: (target) => CockpitGestureAction.multiTouch(
        target: target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        sequence: validSequence,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeScrollUntilVisible(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final scrollStepHandler = _scrollStepHandler;
    if (scrollStepHandler == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.unsupportedCapability(
          message: 'Scrolling is not available for this executor.',
        ),
      );
    }

    final locator = command.locator;
    if (locator == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(
          message: 'scrollUntilVisible requires a locator.',
        ),
      );
    }

    final maxScrolls = _intParameter(command, 'maxScrolls') ?? 12;
    final viewportFraction =
        _doubleParameter(command, 'viewportFraction') ?? 0.8;
    final reverse = command.parameters['reverse'] == true;
    final scrollableKey = _stringParameter(command, 'scrollableKey');
    final scrollableLocator =
        _locatorParameter(command, 'scrollLocator') ??
        _locatorParameter(command, 'scrollableLocator');
    final durationPerStep = _durationFromOptionalPositiveInt(
      command,
      key: 'durationPerStepMs',
      fallback: const Duration(milliseconds: 220),
    );
    final gestureProfile = _gestureProfileParameter(command);
    final continuous = _boolParameter(command, 'continuous') ?? false;
    final postScrollEnsureVisible =
        _boolParameter(command, 'postScrollEnsureVisible') ?? true;
    final revealAlignment =
        _revealAlignmentParameter(command) ?? CockpitRevealAlignment.nearest;
    final revealPadding = (_doubleParameter(command, 'revealPaddingPx') ?? 0)
        .clamp(0, 240)
        .toDouble();
    final revealOffset = _doubleParameter(command, 'revealOffsetPx') ?? 0;
    final allowsGenericResolution = _allowsGenericScrollResolution(locator);

    Future<void> settleAfterReveal() async {
      if (_context.scrollStepProbesTarget) {
        return;
      }
      await _postActionSettler();
      await _settleBeforeObservation();
      await _waitForVisualContinuity(
        commandType: CockpitCommandType.scrollUntilVisible,
        routeChanged: false,
      );
    }

    Future<CockpitCommandExecution?> buildScrollSuccess(
      CockpitTargetResolutionResult successResolution,
    ) async {
      var candidateResolution = successResolution;
      for (var attempt = 0; attempt < 2; attempt += 1) {
        if (await _attemptEnsureVisible(
          locator,
          durationPerStep,
          alignment: revealAlignment,
          padding: revealPadding,
          offset: revealOffset,
        )) {
          await settleAfterReveal();
        }
        final satisfied = _scrollLocatorResolution(command);
        if (satisfied != null) {
          candidateResolution = _scrollResolutionSuccess(satisfied);
        } else {
          candidateResolution = _resolve(command);
        }
        if (candidateResolution.isSuccess) {
          return _buildSuccessWithOptionalCapture(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            resolution: candidateResolution,
          );
        }
      }

      if (await _attemptEnsureVisible(
        locator,
        durationPerStep,
        alignment: revealAlignment,
        padding: revealPadding,
        offset: revealOffset,
      )) {
        await settleAfterReveal();
      }
      return null;
    }

    Future<CockpitCommandExecution?> buildScrollSatisfiedSuccess(
      CockpitLocatorResolution locatorResolution,
    ) {
      return buildScrollSuccess(_scrollResolutionSuccess(locatorResolution));
    }

    Future<CockpitCommandExecution?> confirmSimpleLocatorAfterReveal() async {
      if (allowsGenericResolution) {
        return null;
      }
      for (var attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) {
          await _waitTickHandler(const Duration(milliseconds: 16));
        }
        final satisfied = _scrollLocatorResolution(command);
        if (satisfied != null) {
          return _buildSuccessWithOptionalCapture(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            resolution: _scrollResolutionSuccess(satisfied),
          );
        }
      }
      return null;
    }

    final initialSatisfied = _scrollLocatorResolution(command);
    if (initialSatisfied != null) {
      final success = await buildScrollSatisfiedSuccess(initialSatisfied);
      if (success != null) {
        return success;
      }
    }

    var resolution = allowsGenericResolution
        ? _resolve(command)
        : CockpitTargetResolutionResult.failure(
            error: CockpitCommandError.targetNotFound(
              message: 'No visible target matched the requested locator chain.',
              details: <String, Object?>{'requestedLocator': locator.toJson()},
            ),
          );
    const maxAutoScrollableCandidates = 8;
    final hasExplicitScrollable =
        (scrollableKey != null && scrollableKey.isNotEmpty) ||
        scrollableLocator != null;
    var scrollAttempts = 0;
    var scrollsPerformed = 0;
    var scrollPrepareDurationMs = 0;
    var scrollHandlerDurationMs = 0;
    var scrollObservationDurationMs = 0;
    var candidateIndex = 0;
    var candidateCount = 1;
    var availableCandidateCount = 1;
    var searchingMountedTargetAncestors = false;
    CockpitScrollStepResult? lastScrollStep;
    final directionsTried = <String>[];
    final scrollableCandidatesTried = <Map<String, Object?>>[];

    CockpitLocator? effectiveScrollableLocator() {
      if (hasExplicitScrollable) {
        return scrollableLocator;
      }
      return CockpitLocator(index: candidateIndex);
    }

    void recordScrollableCandidate(
      CockpitScrollStepResult step, {
      required bool reverse,
    }) {
      final candidate = <String, Object?>{
        'index': step.scrollableCandidateIndex ?? candidateIndex,
        if (step.scrollableCandidateCount != null)
          'count': step.scrollableCandidateCount,
        if (step.scrollableKey != null) 'key': step.scrollableKey,
        if (step.scrollableTypeName != null) 'type': step.scrollableTypeName,
        if (step.scrollablePath != null) 'path': step.scrollablePath,
        'direction': reverse ? 'reverse' : 'forward',
      };
      final alreadyRecorded = scrollableCandidatesTried.any(
        (existing) =>
            existing['index'] == candidate['index'] &&
            existing['key'] == candidate['key'] &&
            existing['type'] == candidate['type'] &&
            existing['path'] == candidate['path'] &&
            existing['direction'] == candidate['direction'],
      );
      if (!alreadyRecorded &&
          scrollableCandidatesTried.length < maxAutoScrollableCandidates * 2) {
        scrollableCandidatesTried.add(candidate);
      }
    }

    CockpitScrollStepResult mergeScrollProbeSegment(
      CockpitScrollStepResult? aggregate,
      CockpitScrollStepResult segment, {
      required int segmentCount,
      bool targetVisible = false,
    }) {
      final didScroll = (aggregate?.didScroll ?? false) || segment.didScroll;
      return CockpitScrollStepResult(
        didScroll: didScroll,
        strategy: didScroll && segmentCount > 1 && segment.strategy != 'none'
            ? '${segment.strategy}_probe'
            : segment.strategy,
        scrollableKey: segment.scrollableKey ?? aggregate?.scrollableKey,
        scrollablePath: segment.scrollablePath ?? aggregate?.scrollablePath,
        scrollableTypeName:
            segment.scrollableTypeName ?? aggregate?.scrollableTypeName,
        scrollableCandidateIndex:
            segment.scrollableCandidateIndex ??
            aggregate?.scrollableCandidateIndex,
        scrollableCandidateCount:
            segment.scrollableCandidateCount ??
            aggregate?.scrollableCandidateCount,
        pixelsBefore: aggregate?.pixelsBefore ?? segment.pixelsBefore,
        pixelsAfter: segment.pixelsAfter ?? aggregate?.pixelsAfter,
        nextPixels: segment.nextPixels ?? aggregate?.nextPixels,
        minScrollExtent: segment.minScrollExtent ?? aggregate?.minScrollExtent,
        maxScrollExtent: segment.maxScrollExtent ?? aggregate?.maxScrollExtent,
        viewportDimension:
            segment.viewportDimension ?? aggregate?.viewportDimension,
        acceptsUserOffset:
            segment.acceptsUserOffset ?? aggregate?.acceptsUserOffset,
        allowsProgrammaticScroll:
            segment.allowsProgrammaticScroll ??
            aggregate?.allowsProgrammaticScroll,
        hadGestureTarget:
            (aggregate?.hadGestureTarget ?? false) || segment.hadGestureTarget,
        hadSemanticAction:
            (aggregate?.hadSemanticAction ?? false) ||
            segment.hadSemanticAction,
        matchedRegistryTarget:
            (aggregate?.matchedRegistryTarget ?? false) ||
            segment.matchedRegistryTarget,
        targetVisibilityObserved:
            (aggregate?.targetVisibilityObserved ?? false) ||
            segment.targetVisibilityObserved ||
            targetVisible,
        targetMounted:
            (aggregate?.targetMounted ?? false) ||
            segment.targetMounted ||
            targetVisible,
        targetVisible:
            (aggregate?.targetVisible ?? false) ||
            segment.targetVisible ||
            targetVisible,
      );
    }

    Future<CockpitScrollStepResult> runScrollAttempt(
      bool currentReverse,
    ) async {
      if (_context.scrollStepProbesTarget) {
        return scrollStepHandler(
          reverse: currentReverse,
          viewportFraction: viewportFraction,
          scrollableKey: scrollableKey,
          targetLocator: locator,
          scrollableLocator: effectiveScrollableLocator(),
          duration: durationPerStep,
          gestureProfile: gestureProfile,
          continuous: continuous,
          postScrollEnsureVisible: postScrollEnsureVisible,
        );
      }

      final clampedFraction = viewportFraction.clamp(0.1, 0.95).toDouble();
      final segmentCount = clampedFraction < 0.4
          ? 1
          : (clampedFraction / 0.2).floor().clamp(1, 4);
      final segmentFraction = clampedFraction / segmentCount;
      CockpitScrollStepResult? aggregate;

      for (
        var segmentIndex = 0;
        segmentIndex < segmentCount;
        segmentIndex += 1
      ) {
        final segment = await scrollStepHandler(
          reverse: currentReverse,
          viewportFraction: segmentFraction,
          scrollableKey: scrollableKey,
          targetLocator: locator,
          scrollableLocator: effectiveScrollableLocator(),
          duration: durationPerStep,
          gestureProfile: gestureProfile,
          continuous: continuous,
          postScrollEnsureVisible: postScrollEnsureVisible,
        );
        aggregate = mergeScrollProbeSegment(
          aggregate,
          segment,
          segmentCount: segmentCount,
        );
        if (!segment.didScroll || segmentCount == 1) {
          break;
        }

        final observationStopwatch = Stopwatch()..start();
        await _postActionSettler();
        await _waitForVisualContinuity(
          commandType: CockpitCommandType.scrollUntilVisible,
          routeChanged: false,
        );
        scrollObservationDurationMs += observationStopwatch.elapsedMilliseconds;
        final targetVisible =
            _scrollLocatorResolution(command) != null ||
            (allowsGenericResolution && _resolveProbe(command).isSuccess);
        if (targetVisible) {
          return mergeScrollProbeSegment(
            aggregate,
            segment,
            segmentCount: segmentCount,
            targetVisible: true,
          );
        }
      }

      return aggregate ?? const CockpitScrollStepResult(didScroll: false);
    }

    if (allowsGenericResolution && resolution.isSuccess) {
      final success = await buildScrollSuccess(resolution);
      if (success != null) {
        return success;
      }
    }

    if (await _attemptEnsureVisible(
      locator,
      durationPerStep,
      alignment: revealAlignment,
      padding: revealPadding,
      offset: revealOffset,
    )) {
      final fastSuccess = await confirmSimpleLocatorAfterReveal();
      if (fastSuccess != null) {
        return fastSuccess;
      }
      await settleAfterReveal();
      resolution = _resolve(command);
      if (resolution.isSuccess) {
        final success = await buildScrollSuccess(resolution);
        if (success != null) {
          return success;
        }
      }
    }

    if (maxScrolls > 0) {
      final prepareStopwatch = Stopwatch()..start();
      await _prepareForAction(
        command,
        commandType: CockpitCommandType.scrollUntilVisible,
      );
      scrollPrepareDurationMs = prepareStopwatch.elapsedMilliseconds;
    }

    candidateLoop:
    while (candidateIndex < candidateCount) {
      var currentReverse = reverse;
      var usedDirectionFallback = false;

      directionLoop:
      while (true) {
        final directionName = currentReverse ? 'reverse' : 'forward';
        var directionStoppedWithoutProgress = false;
        CockpitScrollStepResult? lastDirectionScrollStep;
        if (!directionsTried.contains(directionName)) {
          directionsTried.add(directionName);
        }

        for (var attempt = 0; attempt < maxScrolls; attempt += 1) {
          scrollAttempts += 1;
          final handlerStopwatch = Stopwatch()..start();
          final scrollStep = await runScrollAttempt(currentReverse);
          scrollHandlerDurationMs += handlerStopwatch.elapsedMilliseconds;
          // A custom tick handler is used by Flutter's widget-test binding.
          // Target-probing scroll handlers can update a ScrollPosition
          // synchronously, but lazy sliver children are not mounted until the
          // next pumped frame. Pump exactly one frame before resolving the
          // target so tests and source-owned integration harnesses observe the
          // same mounted tree as a live app.
          if (scrollStep.didScroll &&
              _usesTestBinding() &&
              _hasCustomWaitTickHandler) {
            await _waitTickHandler(const Duration(milliseconds: 16));
          }
          lastScrollStep = scrollStep;
          lastDirectionScrollStep = scrollStep;
          recordScrollableCandidate(scrollStep, reverse: currentReverse);
          if (!hasExplicitScrollable) {
            final reportedCount = scrollStep.scrollableCandidateCount;
            if (reportedCount != null && reportedCount > 0) {
              availableCandidateCount = reportedCount;
              candidateCount = reportedCount.clamp(
                1,
                maxAutoScrollableCandidates,
              );
            }
          }
          if (!scrollStep.didScroll) {
            final observationStopwatch = Stopwatch()..start();
            await _postActionSettler();
            scrollObservationDurationMs +=
                observationStopwatch.elapsedMilliseconds;
            final satisfied = _scrollLocatorResolution(command);
            if (satisfied != null) {
              final success = await buildScrollSatisfiedSuccess(satisfied);
              if (success != null) {
                return success;
              }
            }
            if (allowsGenericResolution) {
              resolution = _resolveProbe(command);
              if (resolution.isSuccess) {
                final success = await buildScrollSuccess(resolution);
                if (success != null) {
                  return success;
                }
              }
              if (resolution.error?.code ==
                  CockpitCommandError.ambiguousTargetCode) {
                return _failureExecution(
                  command: command,
                  durationMs: stopwatch.elapsedMilliseconds,
                  snapshot: _liveSnapshot().toJson(),
                  error: resolution.error!,
                );
              }
            }
            if (!hasExplicitScrollable &&
                scrollStep.targetMounted &&
                !searchingMountedTargetAncestors) {
              searchingMountedTargetAncestors = true;
              candidateIndex = 0;
              candidateCount = 1;
              continue candidateLoop;
            }
            if (!usedDirectionFallback &&
                _shouldTryOppositeScrollDirection(currentReverse, scrollStep)) {
              usedDirectionFallback = true;
              currentReverse = !currentReverse;
              continue directionLoop;
            }
            directionStoppedWithoutProgress = true;
            break;
          }
          scrollsPerformed += 1;

          final observationStopwatch = Stopwatch()..start();
          if (!_context.scrollStepProbesTarget) {
            await _settleCoordinator.driveHiddenVisualFrames(
              CockpitCommandType.scrollUntilVisible,
            );
            await _waitForVisualContinuity(
              commandType: CockpitCommandType.scrollUntilVisible,
              routeChanged: false,
            );
            await _postActionSettler();
          }
          if (scrollStep.targetMounted && !scrollStep.targetVisible) {
            _liveSnapshot();
          }
          scrollObservationDurationMs +=
              observationStopwatch.elapsedMilliseconds;

          // A target-probing scroll step observes one layout frame itself.
          // Resolve again from the live registry instead of trusting state from
          // before the newly exposed lazy children were laid out.
          final satisfied = _scrollLocatorResolution(command);
          if (satisfied != null) {
            final success = await buildScrollSatisfiedSuccess(satisfied);
            if (success != null) {
              return success;
            }
          }

          if (allowsGenericResolution) {
            resolution = _resolveProbe(command);
            if (resolution.isSuccess) {
              final success = await buildScrollSuccess(resolution);
              if (success != null) {
                return success;
              }
            }
          }
          if ((scrollStep.targetMounted || resolution.isSuccess) &&
              await _attemptEnsureVisible(
                locator,
                durationPerStep,
                alignment: revealAlignment,
                padding: revealPadding,
                offset: revealOffset,
              )) {
            final fastSuccess = await confirmSimpleLocatorAfterReveal();
            if (fastSuccess != null) {
              return fastSuccess;
            }
            await settleAfterReveal();
            resolution = _resolve(command);
            if (resolution.isSuccess) {
              final success = await buildScrollSuccess(resolution);
              if (success != null) {
                return success;
              }
            }
          }
          if (resolution.error?.code ==
              CockpitCommandError.ambiguousTargetCode) {
            return _failureExecution(
              command: command,
              durationMs: stopwatch.elapsedMilliseconds,
              snapshot: _liveSnapshot().toJson(),
              error: resolution.error!,
            );
          }
          if (!hasExplicitScrollable &&
              scrollStep.targetMounted &&
              !searchingMountedTargetAncestors) {
            searchingMountedTargetAncestors = true;
            candidateIndex = 0;
            candidateCount = 1;
            continue candidateLoop;
          }
          if (!usedDirectionFallback &&
              _shouldTryOppositeScrollDirection(currentReverse, scrollStep)) {
            usedDirectionFallback = true;
            currentReverse = !currentReverse;
            continue directionLoop;
          }
        }

        if (!directionStoppedWithoutProgress &&
            !usedDirectionFallback &&
            maxScrolls > 0 &&
            lastDirectionScrollStep != null &&
            _shouldTryOppositeScrollDirection(
              currentReverse,
              lastDirectionScrollStep,
            )) {
          usedDirectionFallback = true;
          currentReverse = !currentReverse;
          continue directionLoop;
        }
        break;
      }

      if (hasExplicitScrollable) {
        break;
      }
      candidateIndex += 1;
    }

    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _liveSnapshot().toJson(),
      error: _buildScrollUntilVisibleFailure(
        command: command,
        resolution: resolution,
        scrollAttempts: scrollAttempts,
        scrollsPerformed: scrollsPerformed,
        maxScrolls: maxScrolls,
        reverse: reverse,
        viewportFraction: viewportFraction,
        scrollableKey: scrollableKey,
        scrollableLocator: scrollableLocator,
        durationPerStep: durationPerStep,
        gestureProfile: gestureProfile,
        continuous: continuous,
        postScrollEnsureVisible: postScrollEnsureVisible,
        revealAlignment: revealAlignment,
        revealPadding: revealPadding,
        revealOffset: revealOffset,
        lastScrollStep: lastScrollStep,
        directionsTried: directionsTried,
        scrollableCandidatesTried: scrollableCandidatesTried,
        availableScrollableCandidateCount: availableCandidateCount,
        maxAutoScrollableCandidates: maxAutoScrollableCandidates,
        scrollPrepareDurationMs: scrollPrepareDurationMs,
        scrollHandlerDurationMs: scrollHandlerDurationMs,
        scrollObservationDurationMs: scrollObservationDurationMs,
      ),
    );
  }

  CockpitCommandError _buildScrollUntilVisibleFailure({
    required CockpitCommand command,
    required CockpitTargetResolutionResult resolution,
    required int scrollAttempts,
    required int scrollsPerformed,
    required int maxScrolls,
    required bool reverse,
    required double viewportFraction,
    required String? scrollableKey,
    required CockpitLocator? scrollableLocator,
    required Duration durationPerStep,
    required CockpitGestureProfile gestureProfile,
    required bool continuous,
    required bool postScrollEnsureVisible,
    required CockpitRevealAlignment revealAlignment,
    required double revealPadding,
    required double revealOffset,
    CockpitScrollStepResult? lastScrollStep,
    List<String> directionsTried = const <String>[],
    List<Map<String, Object?>> scrollableCandidatesTried =
        const <Map<String, Object?>>[],
    int? availableScrollableCandidateCount,
    int? maxAutoScrollableCandidates,
    int? scrollPrepareDurationMs,
    int? scrollHandlerDurationMs,
    int? scrollObservationDurationMs,
  }) {
    final baseError = resolution.error;
    final details = <String, Object?>{
      if (baseError != null) ...baseError.details,
      'requestedLocator': command.locator?.toJson(),
      'maxScrolls': maxScrolls,
      'scrollAttempts': scrollAttempts,
      'scrollsPerformed': scrollsPerformed,
      'reverse': reverse,
      'viewportFraction': viewportFraction,
      'scrollableKey': scrollableKey,
      'scrollableLocator': scrollableLocator?.toJson(),
      'durationPerStepMs': durationPerStep.inMilliseconds,
      'gestureProfile': gestureProfile.name,
      'continuous': continuous,
      'postScrollEnsureVisible': postScrollEnsureVisible,
      'revealAlignment': revealAlignment.name,
      'revealPaddingPx': revealPadding,
      'revealOffsetPx': revealOffset,
      if (directionsTried.isNotEmpty) 'directionsTried': directionsTried,
      if (scrollableCandidatesTried.isNotEmpty)
        'scrollableCandidatesTried': scrollableCandidatesTried,
      'availableScrollableCandidateCount': ?availableScrollableCandidateCount,
      if (maxAutoScrollableCandidates != null &&
          availableScrollableCandidateCount != null &&
          availableScrollableCandidateCount > maxAutoScrollableCandidates)
        'scrollableCandidateLimit': maxAutoScrollableCandidates,
      'scrollPrepareDurationMs': ?scrollPrepareDurationMs,
      'scrollHandlerDurationMs': ?scrollHandlerDurationMs,
      'scrollObservationDurationMs': ?scrollObservationDurationMs,
      'visibleScrollables': _visibleScrollables(),
      if (lastScrollStep != null) 'lastScrollStep': lastScrollStep.toJson(),
    };
    if (baseError != null) {
      return CockpitCommandError(
        code: baseError.code,
        message: baseError.message,
        details: details,
      );
    }
    return CockpitCommandError.targetNotFound(
      message: 'No visible target matched after scrolling.',
      details: details,
    );
  }

  Future<bool> _attemptEnsureVisible(
    CockpitLocator locator,
    Duration duration, {
    required CockpitRevealAlignment alignment,
    required double padding,
    required double offset,
  }) async {
    final ensureVisibleHandler = _ensureVisibleHandler;
    if (ensureVisibleHandler == null) {
      return false;
    }
    return ensureVisibleHandler(
      locator: locator,
      duration: duration,
      alignment: alignment,
      padding: padding,
      offset: offset,
    );
  }

  bool _shouldTryOppositeScrollDirection(
    bool reverse,
    CockpitScrollStepResult step,
  ) {
    final boundary = reverse ? step.minScrollExtent : step.maxScrollExtent;
    final pixels = step.pixelsAfter ?? step.pixelsBefore;
    if (boundary == null || pixels == null) {
      return false;
    }
    if ((pixels - boundary).abs() < 0.5) {
      return true;
    }
    final nextPixels = step.nextPixels;
    return nextPixels != null && (nextPixels - boundary).abs() < 0.5;
  }

  CockpitCommandExecution _executeClearNetworkActivity(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    final clearNetworkActivityHandler = _clearNetworkActivityHandler;
    if (clearNetworkActivityHandler == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.unsupportedCapability(
          message:
              'Network activity capture is not available for this executor.',
        ),
      );
    }

    clearNetworkActivityHandler();
    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _liveSnapshot().toJson(),
    );
  }

  Future<CockpitCommandExecution> _executeDismissKeyboard(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final focusBefore = cockpitBuildFocusSnapshot();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.microtask(() {});

    Object? hideError;
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on Object catch (error) {
      hideError = error;
    }

    await _postActionSettler();
    await _settleBeforeObservation();

    final warnings = <Map<String, Object?>>[
      if (hideError != null)
        <String, Object?>{
          'code': 'textInputHideFailed',
          'message':
              'Focus was cleared, but the platform text input hide call failed.',
          'details': <String, Object?>{'error': '$hideError'},
        },
    ];

    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _appendWarningsToSnapshot(_liveSnapshot().toJson(), [
        <String, Object?>{
          'code': 'keyboardDismissed',
          'message': 'Primary focus was cleared and text input was hidden.',
          'details': <String, Object?>{
            'hadPrimaryFocus': focusBefore.hasPrimaryFocus,
            if (focusBefore.primaryFocusLabel != null)
              'primaryFocusLabel': focusBefore.primaryFocusLabel,
            'wasTextInputFocus': focusBefore.isTextInputFocus,
          },
        },
        ...warnings,
      ]),
    );
  }

  Future<CockpitCommandExecution> _executeWaitForNetworkIdle(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final waitForNetworkIdleHandler = _waitForNetworkIdleHandler;
    if (waitForNetworkIdleHandler == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.unsupportedCapability(
          message: 'Network idle waiting is not available for this executor.',
        ),
      );
    }

    final quietWindow = _durationFromOptionalPositiveInt(
      command,
      key: 'quietWindowMs',
      fallback: const Duration(milliseconds: 150),
    );
    final timeout = _durationFromOptionalPositiveInt(
      command,
      key: 'timeoutMs',
      fallback: Duration(milliseconds: command.timeoutMs ?? 2000),
    );
    final didGoIdle = await waitForNetworkIdleHandler(
      quietWindow: quietWindow,
      timeout: timeout,
    );
    if (!didGoIdle) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: CockpitCommandError.timeout(
          message: 'Timed out waiting for network to go idle.',
          details: <String, Object?>{
            'quietWindowMs': quietWindow.inMilliseconds,
            'timeoutMs': timeout.inMilliseconds,
          },
        ),
      );
    }

    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _liveSnapshot().toJson(),
    );
  }

  Future<CockpitCommandExecution> _executeWaitForUiIdle(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final quietWindow = _durationFromOptionalPositiveInt(
      command,
      key: 'quietWindowMs',
      fallback: _interactionPolicy.uiIdleQuietWindow,
    );
    final timeout = _durationFromOptionalPositiveInt(
      command,
      key: 'timeoutMs',
      fallback: Duration(milliseconds: command.timeoutMs ?? 2000),
    );
    final includeNetworkIdle =
        _boolParameter(command, 'includeNetworkIdle') ?? true;
    final didGoIdle = await waitForCockpitUiIdle(
      quietWindow: quietWindow,
      timeout: timeout,
      waitTick: _waitTickHandler,
      waitForNetworkIdle: _waitForNetworkIdleHandler,
      ensureVisualFrame: _settleCoordinator.ensureVisualFrame,
      includeNetworkIdle: includeNetworkIdle,
    );
    if (!didGoIdle) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: CockpitCommandError.timeout(
          message: 'Timed out waiting for the app to go quiet.',
          details: <String, Object?>{
            'quietWindowMs': quietWindow.inMilliseconds,
            'timeoutMs': timeout.inMilliseconds,
            'includeNetworkIdle': includeNetworkIdle,
          },
        ),
      );
    }

    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _liveSnapshot().toJson(),
    );
  }

  Future<CockpitCommandExecution> _executeBack(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final backNavigationHandler = _backNavigationHandler;
    if (backNavigationHandler == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.unsupportedCapability(
          message: 'Back navigation is not available for this executor.',
        ),
      );
    }

    final previousRouteName = _currentRouteName();
    await _prepareForAction(command, commandType: CockpitCommandType.back);
    final didHandle = await backNavigationHandler();
    if (!didHandle) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: CockpitCommandError.assertionFailed(
          message: 'Back navigation was not handled by the current route.',
        ),
      );
    }

    await _stabilizeAfterAction(
      previousRouteName,
      commandType: CockpitCommandType.back,
      routeAlreadyCommitted: _routeChangedFrom(previousRouteName),
    );
    return _buildSuccessWithOptionalCapture(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      changed: true,
    );
  }

  Future<CockpitCommandExecution> _executeEnterText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final previousRouteName = _currentRouteName();
    final request = _textInputRequest(command);
    if (request == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(
          message: 'enterText requires a text parameter.',
        ),
      );
    }

    final resolution = command.locator == null
        ? _resolveActiveTextInput(requiredCommand: CockpitCommandType.enterText)
        : await _resolveInteractiveTarget(
            command,
            requiredCommand: CockpitCommandType.enterText,
          );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    final resolvedTarget = resolution.target!;
    if (!resolvedTarget.supportedCommands.contains(
          CockpitCommandType.enterText,
        ) ||
        (resolvedTarget.onSemanticTextInput == null &&
            resolvedTarget.onTextInput == null &&
            resolvedTarget.onSemanticEnterText == null &&
            resolvedTarget.onEnterText == null)) {
      return _unsupportedExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        target: resolvedTarget,
      );
    }

    final semanticTextInput = resolvedTarget.onSemanticTextInput;
    final textInput = resolvedTarget.onTextInput;
    final semanticEnterText = resolvedTarget.onSemanticEnterText;
    final enterText = resolvedTarget.onEnterText;
    await _prepareForAction(command, commandType: CockpitCommandType.enterText);
    late final _ActionCommitResult commit;
    if (textInput != null) {
      commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: () => textInput(request),
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.enterText,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.directTextInput,
      );
    } else if (request.text != null && enterText != null) {
      commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: () => enterText.call(request.text!),
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.enterText,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.directEnterText,
      );
    } else if (semanticTextInput != null) {
      commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: () => semanticTextInput(request),
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.enterText,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.semanticTextInput,
      );
    } else if (request.text != null && semanticEnterText != null) {
      commit = await _invokeActionAndAwaitCommit(
        command: command,
        action: () => semanticEnterText(request.text!),
        previousRouteName: previousRouteName,
        commandType: CockpitCommandType.enterText,
        stopwatch: stopwatch,
        resolution: resolution,
        activationPath: _ActionActivationPath.semanticEnterText,
      );
    } else {
      return _unsupportedExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        target: resolvedTarget,
      );
    }
    if (commit.failure != null) {
      return commit.failure!;
    }
    final mutationCommitted = _textMutationCommitted(resolvedTarget, request);
    final settleWarning = await _stabilizeAfterTextMutation(
      command: command,
      stopwatch: stopwatch,
      previousRouteName: previousRouteName,
      commandType: CockpitCommandType.enterText,
      routeAlreadyCommitted: commit.routeCommitted,
      mutationCommitted: mutationCommitted,
    );

    return _buildSuccessWithOptionalCapture(
      command: command,
      resolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      warnings: <Map<String, Object?>>[...commit.warnings, ?settleWarning],
      changed: mutationCommitted ? true : _changedSince(commit),
    );
  }

  Future<CockpitCommandExecution> _executeEraseText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final resolution = await _resolveTextMutationTarget(command);
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }
    final target = resolution.target!;
    final editable = _editableTextState(target);
    final current = editable?.widget.controller.value;
    final requested = _intParameter(command, 'characters');
    String nextText;
    int selectionOffset;
    if (requested == null) {
      nextText = '';
      selectionOffset = 0;
    } else if (current != null && current.selection.isValid) {
      final selection = current.selection;
      if (!selection.isCollapsed) {
        nextText = current.text.replaceRange(
          selection.start,
          selection.end,
          '',
        );
        selectionOffset = selection.start;
      } else {
        final end = selection.extentOffset.clamp(0, current.text.length);
        final start = (end - requested).clamp(0, end);
        nextText = current.text.replaceRange(start, end, '');
        selectionOffset = start;
      }
    } else {
      final currentText = current?.text ?? target.text ?? '';
      final end = currentText.length;
      final start = (end - requested).clamp(0, end);
      nextText = currentText.replaceRange(start, end, '');
      selectionOffset = start;
    }
    return _executeResolvedTextMutation(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      request: CockpitTextInputRequest(
        text: nextText,
        selectionBase: selectionOffset,
        selectionExtent: selectionOffset,
        clearExisting: true,
      ),
    );
  }

  Future<CockpitCommandExecution> _executeCopyText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final resolution = command.locator == null
        ? _resolveActiveTextInput(requiredCommand: CockpitCommandType.enterText)
        : await _resolveWithRetry(command);
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }
    final target = resolution.target!;
    final text =
        _editableTextState(target)?.widget.controller.text ?? target.text;
    if (text == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution.locatorResolution,
        error: CockpitCommandError.assertionFailed(
          message: 'Resolved target does not expose copyable text.',
        ),
      );
    }
    if (!kIsWeb) {
      final clipboardTimeout = _platformClipboardTimeout(command, stopwatch);
      try {
        if (clipboardTimeout <= Duration.zero) {
          throw TimeoutException('The command deadline has elapsed.');
        }
        await Clipboard.setData(
          ClipboardData(text: text),
        ).timeout(clipboardTimeout);
      } on TimeoutException {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          error: CockpitCommandError.timeout(
            message: _platformClipboardTimeoutMessage(
              operation: 'write',
              timeout: clipboardTimeout,
            ),
            details: <String, Object?>{
              'phase': 'clipboardWrite',
              'timeoutMs': clipboardTimeout.inMilliseconds,
            },
          ),
        );
      } on Object catch (error) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          error: CockpitCommandError(
            code: 'clipboardFailed',
            message: 'Could not write the platform clipboard: $error',
          ),
        );
      }
    }
    _inAppClipboardText = text;
    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      locatorResolution: resolution.locatorResolution,
    );
  }

  Future<CockpitCommandExecution> _executePasteText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final resolution = await _resolveTextMutationTarget(command);
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    final cachedClipboardText = _inAppClipboardText;
    String clipboardText;
    if (cachedClipboardText != null) {
      clipboardText = cachedClipboardText;
    } else if (kIsWeb) {
      // Browser clipboard APIs require transient user activation, which a
      // remote semantic command cannot provide deterministically.
      clipboardText = '';
    } else {
      final clipboardTimeout = _platformClipboardTimeout(command, stopwatch);
      try {
        if (clipboardTimeout <= Duration.zero) {
          throw TimeoutException('The command deadline has elapsed.');
        }
        clipboardText =
            (await Clipboard.getData(
              Clipboard.kTextPlain,
            ).timeout(clipboardTimeout))?.text ??
            '';
      } on TimeoutException {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          error: CockpitCommandError.timeout(
            message: _platformClipboardTimeoutMessage(
              operation: 'read',
              timeout: clipboardTimeout,
            ),
            details: <String, Object?>{
              'phase': 'clipboardRead',
              'timeoutMs': clipboardTimeout.inMilliseconds,
            },
          ),
        );
      } on Object catch (error) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          error: CockpitCommandError(
            code: 'clipboardFailed',
            message: 'Could not read the platform clipboard: $error',
          ),
        );
      }
    }
    final target = resolution.target!;
    final current = _editableTextState(target)?.widget.controller.value;
    String nextText;
    int selectionOffset;
    if (current != null && current.selection.isValid) {
      final selection = current.selection;
      nextText = current.text.replaceRange(
        selection.start,
        selection.end,
        clipboardText,
      );
      selectionOffset = selection.start + clipboardText.length;
    } else {
      nextText = clipboardText;
      selectionOffset = clipboardText.length;
    }
    return _executeResolvedTextMutation(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      request: CockpitTextInputRequest(
        text: nextText,
        selectionBase: selectionOffset,
        selectionExtent: selectionOffset,
        clearExisting: true,
      ),
    );
  }

  Duration _platformClipboardTimeout(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    final commandTimeout = _hardCommandTimeout(command);
    if (commandTimeout == null) {
      return _platformClipboardAccessTimeout;
    }
    final remaining = commandTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining < _platformClipboardAccessTimeout
        ? remaining
        : _platformClipboardAccessTimeout;
  }

  String _platformClipboardTimeoutMessage({
    required String operation,
    required Duration timeout,
  }) {
    if (timeout <= Duration.zero) {
      return 'The command deadline elapsed before the platform clipboard '
          '$operation could start.';
    }
    return 'Could not $operation the platform clipboard within '
        '${timeout.inMilliseconds}ms.';
  }

  Future<CockpitTargetResolutionResult> _resolveTextMutationTarget(
    CockpitCommand command,
  ) async => command.locator == null
      ? _resolveActiveTextInput(requiredCommand: CockpitCommandType.enterText)
      : _resolveInteractiveTarget(
          command,
          requiredCommand: CockpitCommandType.enterText,
        );

  Future<CockpitCommandExecution> _executeResolvedTextMutation({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitTargetResolutionResult resolution,
    required CockpitTextInputRequest request,
  }) async {
    final target = resolution.target!;
    if (!target.supportedCommands.contains(CockpitCommandType.enterText) ||
        target.onTextInput == null) {
      return _unsupportedExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        target: target,
      );
    }
    final previousRouteName = _currentRouteName();
    await _prepareForAction(command, commandType: command.commandType);
    final commit = await _invokeActionAndAwaitCommit(
      command: command,
      action: () => target.onTextInput!.call(request),
      previousRouteName: previousRouteName,
      commandType: command.commandType,
      stopwatch: stopwatch,
      resolution: resolution,
      activationPath: _ActionActivationPath.directTextInput,
    );
    if (commit.failure != null) return commit.failure!;
    final mutationCommitted = _textMutationCommitted(target, request);
    final settleWarning = await _stabilizeAfterTextMutation(
      command: command,
      stopwatch: stopwatch,
      previousRouteName: previousRouteName,
      commandType: command.commandType,
      routeAlreadyCommitted: commit.routeCommitted,
      mutationCommitted: mutationCommitted,
    );
    return _buildSuccessWithOptionalCapture(
      command: command,
      resolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      warnings: <Map<String, Object?>>[...commit.warnings, ?settleWarning],
      changed: mutationCommitted ? true : _changedSince(commit),
    );
  }

  Future<Map<String, Object?>?> _stabilizeAfterTextMutation({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required String? previousRouteName,
    required CockpitCommandType commandType,
    required bool routeAlreadyCommitted,
    required bool mutationCommitted,
  }) async {
    Future<void> stabilize() => _stabilizeAfterAction(
      previousRouteName,
      commandType: commandType,
      routeAlreadyCommitted: routeAlreadyCommitted,
    );
    final timeoutMs = command.timeoutMs;
    if (!mutationCommitted || timeoutMs == null || timeoutMs <= 0) {
      await stabilize();
      return null;
    }

    // Leave enough of the command deadline for the final live snapshot and
    // transport response. The text controller is the authoritative mutation
    // postcondition; settling after that point improves observation quality
    // but must not turn a proven mutation into a hard timeout failure.
    const completionReserveMs = 500;
    final settleBudgetMs =
        timeoutMs - stopwatch.elapsedMilliseconds - completionReserveMs;
    if (settleBudgetMs <= 0) {
      return _textMutationSettleWarning(
        commandType: commandType,
        timeoutMs: timeoutMs,
        settleBudgetMs: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    try {
      await stabilize().timeout(Duration(milliseconds: settleBudgetMs));
      return null;
    } on TimeoutException {
      return _textMutationSettleWarning(
        commandType: commandType,
        timeoutMs: timeoutMs,
        settleBudgetMs: settleBudgetMs,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  bool _textMutationCommitted(
    CockpitTarget target,
    CockpitTextInputRequest request,
  ) {
    if (!request.hasEditingMutation) {
      return false;
    }
    final value = _editableTextState(target)?.widget.controller.value;
    if (value == null) {
      return false;
    }
    final expectedText = request.text;
    if (expectedText != null && value.text != expectedText) {
      return false;
    }
    if (expectedText == null &&
        request.clearExisting &&
        value.text.isNotEmpty) {
      return false;
    }
    final selectionBase = request.selectionBase;
    if (selectionBase != null) {
      if (!value.selection.isValid) {
        return false;
      }
      final expectedBase = selectionBase.clamp(0, value.text.length);
      final expectedExtent = (request.selectionExtent ?? selectionBase).clamp(
        0,
        value.text.length,
      );
      if (value.selection.baseOffset != expectedBase ||
          value.selection.extentOffset != expectedExtent) {
        return false;
      }
    }
    final composingBase = request.composingBase;
    if (composingBase == null) {
      return true;
    }
    final composingExtent = (request.composingExtent ?? composingBase).clamp(
      0,
      value.text.length,
    );
    return value.composing.start == composingBase.clamp(0, value.text.length) &&
        value.composing.end == composingExtent;
  }

  Map<String, Object?> _textMutationSettleWarning({
    required CockpitCommandType commandType,
    required int timeoutMs,
    required int settleBudgetMs,
    required int elapsedMs,
  }) => <String, Object?>{
    'code': 'postActionSettleIncomplete',
    'message':
        'The text mutation committed, but optional post-action settling did not finish within the remaining command deadline.',
    'details': <String, Object?>{
      'commandType': commandType.name,
      'timeoutMs': timeoutMs,
      'settleBudgetMs': settleBudgetMs,
      'elapsedMs': elapsedMs,
    },
  };

  EditableTextState? _editableTextState(CockpitTarget target) {
    final node = target.diagnosticNodeProvider?.call();
    if (node is! Element || !node.mounted) return null;
    EditableTextState? result;
    void visit(Element candidate) {
      if (result != null || !candidate.mounted) return;
      if (candidate is StatefulElement &&
          candidate.state is EditableTextState) {
        result = candidate.state as EditableTextState;
        return;
      }
      candidate.visitChildElements(visit);
    }

    visit(node);
    return result;
  }

  CockpitTargetResolutionResult _resolveActiveTextInput({
    required CockpitCommandType requiredCommand,
  }) {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    if (focusNode == null || focusContext is! Element) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'No active text input is focused.',
          details: <String, Object?>{
            'hasPrimaryFocus': focusNode != null,
            'isTextInputFocus': false,
          },
        ),
      );
    }

    final focusSnapshot = cockpitBuildFocusSnapshot();
    if (!focusSnapshot.isTextInputFocus) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'The primary focus is not a text input.',
          details: <String, Object?>{
            'hasPrimaryFocus': focusSnapshot.hasPrimaryFocus,
            'isTextInputFocus': false,
            'primaryFocusLabel': ?focusSnapshot.primaryFocusLabel,
            'primaryFocusWidgetType': ?focusSnapshot.primaryFocusWidgetType,
          },
        ),
      );
    }

    final candidates = <({CockpitTarget target, int distance})>[];
    for (final target in _registry.visibleTargets) {
      if (!target.supportedCommands.contains(requiredCommand) ||
          (requiredCommand == CockpitCommandType.enterText
              ? target.onTextInput == null &&
                    target.onEnterText == null &&
                    target.onSemanticTextInput == null &&
                    target.onSemanticEnterText == null
              : target.onTextInput == null)) {
        continue;
      }
      final targetElement = target.diagnosticNodeProvider?.call();
      if (targetElement is! Element) {
        continue;
      }
      final distance = _elementDistance(focusContext, targetElement);
      if (distance != null) {
        candidates.add((target: target, distance: distance));
      }
    }

    if (candidates.isEmpty) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message:
              'No visible target is associated with the active text input.',
          details: <String, Object?>{
            'primaryFocusLabel': ?focusSnapshot.primaryFocusLabel,
            'primaryFocusWidgetType': ?focusSnapshot.primaryFocusWidgetType,
            'visibleTargetCount': _registry.visibleTargets.length,
          },
        ),
      );
    }

    candidates.sort((left, right) {
      final distanceCompare = left.distance.compareTo(right.distance);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      final leftDirect = left.target.onTextInput != null ? 1 : 0;
      final rightDirect = right.target.onTextInput != null ? 1 : 0;
      final directCompare = rightDirect.compareTo(leftDirect);
      if (directCompare != 0) {
        return directCompare;
      }
      return left.target.registrationId.compareTo(right.target.registrationId);
    });

    final best = candidates.first;
    final tied = candidates
        .skip(1)
        .where(
          (candidate) =>
              candidate.distance == best.distance &&
              (candidate.target.onTextInput != null) ==
                  (best.target.onTextInput != null),
        )
        .toList(growable: false);
    if (tied.isNotEmpty) {
      final matches = <CockpitTarget>[
        best.target,
        ...tied.map((candidate) => candidate.target),
      ];
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.ambiguousTarget(
          message:
              'Multiple visible targets are associated with the active text input.',
          details: <String, Object?>{
            'candidateCount': matches.length,
            'candidates': matches
                .map((target) => target.registrationId)
                .toList(growable: false),
            'primaryFocusLabel': ?focusSnapshot.primaryFocusLabel,
          },
        ),
        matches: matches,
      );
    }

    return CockpitTargetResolutionResult.success(
      target: best.target,
      locatorResolution: CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.registrationId,
        matchedValue: best.target.registrationId,
        matchedSignals: const <String, String>{'focus': 'primary'},
      ),
      matches: candidates
          .map((candidate) => candidate.target)
          .toList(growable: false),
    );
  }

  int? _elementDistance(Element focused, Element candidate) {
    if (identical(focused, candidate)) {
      return 0;
    }

    var distance = 0;
    var found = false;
    focused.visitAncestorElements((ancestor) {
      distance += 1;
      if (identical(ancestor, candidate)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) {
      return distance;
    }

    distance = 0;
    found = false;
    candidate.visitAncestorElements((ancestor) {
      distance += 1;
      if (identical(ancestor, focused)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) {
      return distance;
    }
    return null;
  }

  Future<CockpitCommandExecution> _executeFocusTextInput(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    return _executeStructuredTextInput(
      command: command,
      stopwatch: stopwatch,
      requiredCommand: CockpitCommandType.focusTextInput,
      requestBuilder: () => const CockpitTextInputRequest(requestFocus: true),
    );
  }

  Future<CockpitCommandExecution> _executeSetTextEditingValue(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    return _executeStructuredTextInput(
      command: command,
      stopwatch: stopwatch,
      requiredCommand: CockpitCommandType.setTextEditingValue,
      requestBuilder: () {
        final request = _textInputRequest(command);
        if (request == null || !request.hasEditingMutation) {
          return null;
        }
        return request;
      },
    );
  }

  Future<CockpitCommandExecution> _executeSendTextInputAction(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    return _executeStructuredTextInput(
      command: command,
      stopwatch: stopwatch,
      requiredCommand: CockpitCommandType.sendTextInputAction,
      requestBuilder: () {
        final request = _textInputRequest(command);
        if (request?.inputAction == null) {
          return null;
        }
        return request;
      },
    );
  }

  Future<CockpitCommandExecution> _executeStructuredTextInput({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitCommandType requiredCommand,
    required CockpitTextInputRequest? Function() requestBuilder,
  }) async {
    final request = requestBuilder();
    if (request == null) {
      final message = switch (requiredCommand) {
        CockpitCommandType.focusTextInput =>
          'focusTextInput does not require additional parameters.',
        CockpitCommandType.setTextEditingValue =>
          'setTextEditingValue requires text and/or selection parameters.',
        CockpitCommandType.sendTextInputAction =>
          'sendTextInputAction requires an inputAction parameter.',
        _ => 'Invalid text input request.',
      };
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(message: message),
      );
    }

    final previousRouteName = _currentRouteName();
    final resolution = command.locator == null
        ? _resolveActiveTextInput(requiredCommand: requiredCommand)
        : await _resolveInteractiveTarget(
            command,
            requiredCommand: requiredCommand,
          );
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    final resolvedTarget = resolution.target!;
    if (!resolvedTarget.supportedCommands.contains(requiredCommand) ||
        resolvedTarget.onTextInput == null) {
      return _unsupportedExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        target: resolvedTarget,
      );
    }

    await _prepareForAction(command, commandType: requiredCommand);
    final commit = await _invokeActionAndAwaitCommit(
      command: command,
      action: () => resolvedTarget.onTextInput!.call(request),
      previousRouteName: previousRouteName,
      commandType: requiredCommand,
      stopwatch: stopwatch,
      resolution: resolution,
      activationPath: _ActionActivationPath.directTextInput,
    );
    if (commit.failure != null) {
      return commit.failure!;
    }
    final mutationCommitted = _textMutationCommitted(resolvedTarget, request);
    final settleWarning = await _stabilizeAfterTextMutation(
      command: command,
      stopwatch: stopwatch,
      previousRouteName: previousRouteName,
      commandType: requiredCommand,
      routeAlreadyCommitted: commit.routeCommitted,
      mutationCommitted: mutationCommitted,
    );
    return _buildSuccessWithOptionalCapture(
      command: command,
      resolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      warnings: <Map<String, Object?>>[...commit.warnings, ?settleWarning],
      changed: mutationCommitted ? true : _changedSince(commit),
    );
  }

  Future<CockpitCommandExecution> _executeKeyEvent(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final request = _keyEventRequest(command);
    if (request == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(
          message:
              '${command.commandType.name} requires a logicalKey parameter.',
        ),
      );
    }
    final focusedTextInputAction = _focusedTextInputActionForKeyEvent(
      command.commandType,
      request,
    );
    if (focusedTextInputAction != null) {
      final focusedTextInput = _resolveActiveTextInput(
        requiredCommand: CockpitCommandType.sendTextInputAction,
      );
      if (focusedTextInput.isSuccess) {
        return _executeSendTextInputAction(
          command.copyWith(
            commandType: CockpitCommandType.sendTextInputAction,
            parameters: <String, Object?>{
              'inputAction': focusedTextInputAction.name,
            },
          ),
          stopwatch,
        );
      }
    }
    final previousRouteName = _currentRouteName();
    final beforeActionFingerprint = _observableUiFingerprint();
    await _prepareForAction(command, commandType: command.commandType);
    final handled = await _keyEventHandler(request, command.commandType);
    await _stabilizeAfterAction(
      previousRouteName,
      commandType: command.commandType,
    );
    final allowUnhandled = _boolParameter(command, 'allowUnhandled') ?? false;
    if (!handled && !allowUnhandled) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: CockpitCommandError.assertionFailed(
          message:
              'The keyboard event was not handled by the current Flutter focus tree.',
          details: request.toJson(),
        ),
      );
    }
    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: _liveSnapshot().toJson(),
      changed: _observableUiFingerprint() != beforeActionFingerprint,
    );
  }

  CockpitTextInputAction? _focusedTextInputActionForKeyEvent(
    CockpitCommandType commandType,
    CockpitKeyEventRequest request,
  ) {
    if (commandType != CockpitCommandType.sendKeyEvent ||
        (request.logicalKey != LogicalKeyboardKey.enter &&
            request.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return null;
    }
    if (!cockpitBuildFocusSnapshot().isTextInputFocus) {
      return null;
    }
    final action = _focusedTextInputAction();
    return action == CockpitTextInputAction.newline ? null : action;
  }

  CockpitTextInputAction _focusedTextInputAction() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusContext = primaryFocus?.context;
    if (focusContext is! Element) {
      return CockpitTextInputAction.done;
    }

    TextInputAction? action;
    bool inspect(Element element) {
      if (!element.mounted) return false;
      final widget = element.widget;
      if (widget is EditableText &&
          (identical(widget.focusNode, primaryFocus) ||
              widget.focusNode.hasFocus)) {
        action = widget.textInputAction;
        return true;
      }
      return false;
    }

    inspect(focusContext);
    if (action == null) {
      focusContext.visitAncestorElements((ancestor) => !inspect(ancestor));
    }
    if (action == null) {
      void visitDescendants(Element element) {
        if (action != null || inspect(element)) return;
        element.visitChildElements(visitDescendants);
      }

      focusContext.visitChildElements(visitDescendants);
    }
    return switch (action) {
      TextInputAction.next => CockpitTextInputAction.next,
      TextInputAction.previous => CockpitTextInputAction.previous,
      TextInputAction.search => CockpitTextInputAction.search,
      TextInputAction.send => CockpitTextInputAction.send,
      TextInputAction.go => CockpitTextInputAction.go,
      TextInputAction.newline => CockpitTextInputAction.newline,
      TextInputAction.none => CockpitTextInputAction.none,
      TextInputAction.unspecified => CockpitTextInputAction.unspecified,
      TextInputAction.continueAction => CockpitTextInputAction.continueAction,
      TextInputAction.emergencyCall => CockpitTextInputAction.emergencyCall,
      TextInputAction.join => CockpitTextInputAction.join,
      TextInputAction.route => CockpitTextInputAction.route,
      TextInputAction.done || null => CockpitTextInputAction.done,
    };
  }

  Future<CockpitCommandExecution> _executeSemanticAction(
    CockpitCommand command,
    Stopwatch stopwatch, {
    required CockpitCommandType requiredCommand,
    required CockpitSemanticActionHandler? Function(CockpitTarget target)
    semanticAction,
  }) async {
    final previousRouteName = _currentRouteName();
    final locator = command.locator;
    final revealedWithEnsureVisible =
        requiredCommand == CockpitCommandType.showOnScreen &&
        locator != null &&
        await _attemptEnsureVisible(
          locator,
          const Duration(milliseconds: 220),
          alignment:
              _revealAlignmentParameter(command) ??
              CockpitRevealAlignment.nearest,
          padding: 0,
          offset: _doubleParameter(command, 'revealOffsetPx') ?? 0,
        );
    late CockpitTargetResolutionResult resolution;
    if (revealedWithEnsureVisible) {
      await _postActionSettler();
      await _settleBeforeObservation();
      resolution = await _resolveWithRetry(command, attempts: 2);
    } else {
      resolution = await _resolveInteractiveTarget(
        command,
        requiredCommand: requiredCommand,
      );
    }
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    final target = resolution.target!;
    final action = semanticAction(target);
    if (!target.supportedCommands.contains(requiredCommand) || action == null) {
      if (revealedWithEnsureVisible &&
          requiredCommand == CockpitCommandType.showOnScreen) {
        return _buildSuccessWithOptionalCapture(
          command: command,
          resolution: resolution,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      return _unsupportedExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        target: target,
      );
    }

    await _prepareForAction(command, commandType: requiredCommand);
    final commit = await _invokeActionAndAwaitCommit(
      command: command,
      action: action,
      previousRouteName: previousRouteName,
      commandType: requiredCommand,
      stopwatch: stopwatch,
      resolution: resolution,
      activationPath: _ActionActivationPath.semantic,
    );
    if (commit.failure != null) {
      return commit.failure!;
    }
    await _stabilizeAfterAction(
      previousRouteName,
      commandType: requiredCommand,
    );
    return _buildSuccessWithOptionalCapture(
      command: command,
      resolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      warnings: commit.warnings,
      changed: _changedSince(commit),
    );
  }

  Future<CockpitCommandExecution> _executeDismiss(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final resolver = _dismissActionResolver;
    if (command.locator == null && resolver != null) {
      final action = resolver();
      if (action != null) {
        final previousRouteName = _currentRouteName();
        await _prepareForAction(
          command,
          commandType: CockpitCommandType.dismiss,
        );
        final commit = await _invokeActionAndAwaitCommit(
          command: command,
          action: action,
          previousRouteName: previousRouteName,
          commandType: CockpitCommandType.dismiss,
          stopwatch: stopwatch,
          activationPath: _ActionActivationPath.direct,
        );
        if (commit.failure != null) {
          return commit.failure!;
        }
        await _stabilizeAfterAction(
          previousRouteName,
          commandType: CockpitCommandType.dismiss,
        );
        return _buildSuccessWithOptionalCapture(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          warnings: commit.warnings,
          changed: _changedSince(commit),
        );
      }
    }
    return _executeSemanticAction(
      command,
      stopwatch,
      requiredCommand: CockpitCommandType.dismiss,
      semanticAction: (target) => target.onSemanticDismiss,
    );
  }

  Future<CockpitCommandExecution> _executeAssertVisible(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    await _settleBeforeObservation();
    final locator = command.locator;
    final timeoutMs = command.timeoutMs ?? _defaultAssertSettleTimeoutMs;
    CockpitTargetResolutionResult? lastResolution;

    while (true) {
      final snapshot = _liveSnapshot();
      if (locator != null) {
        if (_isSimpleLocatorFor(locator, CockpitLocatorKind.route) &&
            snapshot.routeName == locator.value) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            locatorResolution: CockpitLocatorResolution(
              matchedKind: CockpitLocatorKind.route,
              matchedValue: locator.value,
            ),
            snapshot: snapshot.toJson(),
          );
        }
        if (_isSimpleLocatorFor(locator, CockpitLocatorKind.text) &&
            _visibleTargetsContainText(
              _registry.visibleTargets,
              locator.value,
              matchMode: locator.matchMode,
            )) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            locatorResolution: CockpitLocatorResolution(
              matchedKind: CockpitLocatorKind.text,
              matchedValue: locator.value,
              matchedSignals: locator.matchMode == CockpitTextMatchMode.exact
                  ? const <String, String>{}
                  : <String, String>{
                      'text': locator.value,
                      'matchMode': locator.matchMode.name,
                    },
            ),
            snapshot: snapshot.toJson(),
          );
        }
      }

      final resolution = _resolve(command);
      if (resolution.isSuccess) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          snapshot: _liveSnapshot().toJson(),
        );
      }
      if (resolution.error?.code == CockpitCommandError.ambiguousTargetCode) {
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          snapshot: snapshot.toJson(),
          error: resolution.error!,
        );
      }
      lastResolution = resolution;
      if (stopwatch.elapsedMilliseconds >= timeoutMs) {
        break;
      }
      await _postActionSettler();
      await _waitTickHandler(_assertPollInterval);
    }

    final failureSnapshot = _liveSnapshot();
    if (!lastResolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: failureSnapshot.toJson(),
        error: _withAssertionRetryDetails(
          lastResolution.error!,
          timeoutMs: timeoutMs,
          visibleTargets: _registry.visibleTargets,
        ),
      );
    }

    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: failureSnapshot.toJson(),
      error: CockpitCommandError.assertionFailed(
        message: 'Timed out waiting for visible target.',
        details: <String, Object?>{
          'timeoutMs': timeoutMs,
          'routeName': failureSnapshot.routeName,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ),
        },
      ),
    );
  }

  Future<CockpitCommandExecution> _executeAssertText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final expectedText = _expectedText(command);
    if (expectedText == null || expectedText.isEmpty) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(
          message: 'assertText requires a non-empty expected text value.',
        ),
      );
    }
    if (_boolParameter(command, 'probe') ?? false) {
      return _executeAssertTextProbe(
        command,
        stopwatch,
        expectedText: expectedText,
      );
    }

    await _settleBeforeObservation();
    final timeoutMs = command.timeoutMs ?? _defaultAssertSettleTimeoutMs;
    final locator = command.locator;
    final useGlobalTextObservation =
        locator == null ||
        _isSimpleLocatorFor(locator, CockpitLocatorKind.text);
    final textMatchMode = _textMatchModeParameter(command);
    while (true) {
      final snapshot = _liveSnapshot();
      if (useGlobalTextObservation &&
          _visibleTargetsContainText(
            _registry.visibleTargets,
            expectedText,
            matchMode: textMatchMode,
          )) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          snapshot: snapshot.toJson(),
        );
      }
      if (!useGlobalTextObservation) {
        final resolution = _resolve(command);
        if (resolution.isSuccess &&
            _targetContainsText(
              resolution.target!,
              expectedText,
              matchMode: textMatchMode,
            )) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            locatorResolution: resolution.locatorResolution,
            snapshot: snapshot.toJson(),
          );
        }
        if (resolution.error?.code == CockpitCommandError.ambiguousTargetCode) {
          return _failureExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            snapshot: snapshot.toJson(),
            error: resolution.error!,
          );
        }
      }
      if (stopwatch.elapsedMilliseconds >= timeoutMs) {
        break;
      }
      await _postActionSettler();
      await _waitTickHandler(_assertPollInterval);
    }

    final snapshot = _liveSnapshot();
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: snapshot.toJson(),
      error: CockpitCommandError.assertionFailed(
        message: 'Expected visible text "$expectedText" was not found.',
        details: <String, Object?>{
          'expectedText': expectedText,
          'timeoutMs': timeoutMs,
          'routeName': snapshot.routeName,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ),
        },
      ),
    );
  }

  CockpitCommandError _withAssertionRetryDetails(
    CockpitCommandError error, {
    required int timeoutMs,
    required Iterable<CockpitTarget> visibleTargets,
  }) {
    final details = <String, Object?>{
      ...error.details,
      'timeoutMs': timeoutMs,
      'visibleTextCandidates': _visibleTextCandidates(visibleTargets),
    };
    return CockpitCommandError(
      code: error.code,
      message: error.message,
      details: details,
    );
  }

  Future<CockpitCommandExecution> _executeWaitFor(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final timeoutMs = command.timeoutMs ?? 2000;
    final waitCondition = _describeWaitCondition(command);
    if (waitCondition == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.timeout(
          message:
              'waitFor requires a locator, routeName parameter, or text parameter.',
        ),
      );
    }
    if (_boolParameter(command, 'probe') ?? false) {
      return _executeWaitForProbe(
        command,
        stopwatch,
        waitCondition: waitCondition,
      );
    }
    if (_boolParameter(command, 'absent') ?? false) {
      return _executeWaitForAbsent(
        command,
        stopwatch,
        timeoutMs: timeoutMs,
        waitCondition: waitCondition,
      );
    }
    final minVisibleTargets = _minVisibleTargetsForWait(command);

    while (stopwatch.elapsedMilliseconds <= timeoutMs) {
      final snapshot = _liveSnapshot();
      final routeName = _expectedRouteName(command);
      if (routeName != null &&
          snapshot.routeName == routeName &&
          _hasEnoughVisibleTargets(minVisibleTargets)) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: CockpitLocatorResolution(
            matchedKind: CockpitLocatorKind.route,
            matchedValue: routeName,
          ),
          snapshot: snapshot.toJson(),
        );
      }

      final locator = command.locator;
      final expectedText = _expectedText(command);
      if (expectedText != null &&
          (locator == null ||
              _isSimpleLocatorFor(locator, CockpitLocatorKind.text)) &&
          _visibleTargetsContainText(
            _registry.visibleTargets,
            expectedText,
            matchMode: locator?.matchMode ?? _textMatchModeParameter(command),
          )) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: CockpitLocatorResolution(
            matchedKind: CockpitLocatorKind.text,
            matchedValue: expectedText,
          ),
          snapshot: snapshot.toJson(),
        );
      }

      if (locator != null &&
          !_isSimpleLocatorFor(locator, CockpitLocatorKind.route) &&
          !_isSimpleLocatorFor(locator, CockpitLocatorKind.text)) {
        final resolution = _resolve(command);
        if (resolution.isSuccess) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            locatorResolution: resolution.locatorResolution,
            snapshot: snapshot.toJson(),
          );
        }
        if (resolution.error?.code == CockpitCommandError.ambiguousTargetCode) {
          return _failureExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            snapshot: snapshot.toJson(),
            error: resolution.error!,
          );
        }
      }

      final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
      if (remaining <= 0) {
        break;
      }
      final settleCompleted = await _settleWithinCommandBudget(
        Duration(milliseconds: remaining),
      );
      if (!settleCompleted) {
        break;
      }
      await _waitTickHandler(const Duration(milliseconds: 16));
    }

    final failureSnapshot = _liveSnapshot();
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: failureSnapshot.toJson(),
      error: CockpitCommandError.timeout(
        message: 'Timed out waiting for $waitCondition.',
        details: <String, Object?>{
          'waitCondition': waitCondition,
          'timeoutMs': timeoutMs,
          'routeName': failureSnapshot.routeName,
          'visibleTargetCount': _registry.visibleTargets.length,
          'routeReadyVisibleTargetCount':
              _registry.routeReadyVisibleTargets.length,
          if (minVisibleTargets > 0) 'minVisibleTargets': minVisibleTargets,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ).take(12).toList(growable: false),
          'targetDiscoveryDiagnostics': _registry.routeDiagnostics(),
          'emptyRouteHint': ?_emptyRouteHint(),
        },
      ),
    );
  }

  CockpitCommandExecution _executeAssertTextProbe(
    CockpitCommand command,
    Stopwatch stopwatch, {
    required String expectedText,
  }) {
    final locator = command.locator;
    final useGlobalTextObservation =
        locator == null ||
        _isSimpleLocatorFor(locator, CockpitLocatorKind.text);
    final textMatchMode = _textMatchModeParameter(command);
    if (useGlobalTextObservation) {
      final locatorProbe = _context.locatorProbe;
      if (locatorProbe != null) {
        final resolution = locatorProbe(
          locator ??
              CockpitLocator(text: expectedText, matchMode: textMatchMode),
        );
        if (resolution.isSuccess &&
            _targetContainsText(
              resolution.target!,
              expectedText,
              matchMode: textMatchMode,
            )) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            locatorResolution: resolution.locatorResolution,
          );
        }
        return _failureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: resolution.locatorResolution,
          error:
              resolution.error ??
              CockpitCommandError.assertionFailed(
                message: 'Resolved target does not contain "$expectedText".',
                details: <String, Object?>{
                  'probe': true,
                  'expectedText': expectedText,
                  'routeName': _currentRouteName(),
                },
              ),
        );
      }
      final visibleTargets = _registry.visibleTargets;
      if (_visibleTargetsContainText(
        visibleTargets,
        expectedText,
        matchMode: textMatchMode,
      )) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.assertionFailed(
          message: 'Expected visible text "$expectedText" was not found.',
          details: <String, Object?>{
            'probe': true,
            'expectedText': expectedText,
            'routeName': _currentRouteName(),
            'visibleTextCandidates': _visibleTextCandidates(
              visibleTargets,
            ).take(12).toList(growable: false),
          },
        ),
      );
    }

    final resolution = _resolveProbe(command);
    if (resolution.isSuccess &&
        _targetContainsText(
          resolution.target!,
          expectedText,
          matchMode: textMatchMode,
        )) {
      return _successExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution.locatorResolution,
      );
    }
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      locatorResolution: resolution.locatorResolution,
      error:
          resolution.error ??
          CockpitCommandError.assertionFailed(
            message: 'Resolved target does not contain "$expectedText".',
            details: <String, Object?>{
              'probe': true,
              'expectedText': expectedText,
              'routeName': _currentRouteName(),
            },
          ),
    );
  }

  CockpitCommandExecution _executeWaitForProbe(
    CockpitCommand command,
    Stopwatch stopwatch, {
    required String waitCondition,
  }) {
    final absent = _boolParameter(command, 'absent') ?? false;
    final routeName = _expectedRouteName(command);
    if (routeName != null) {
      final minVisibleTargets = _minVisibleTargetsForWait(command);
      final matched =
          _currentRouteName() == routeName &&
          _hasEnoughVisibleTargetsForProbe(minVisibleTargets);
      if (matched != absent) {
        return _successExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          locatorResolution: CockpitLocatorResolution(
            matchedKind: CockpitLocatorKind.route,
            matchedValue: routeName,
          ),
        );
      }
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.timeout(
          message: absent
              ? 'Route "$routeName" is currently active.'
              : 'Route "$routeName" is not currently ready.',
          details: <String, Object?>{
            'probe': true,
            'waitCondition': waitCondition,
            'absent': absent,
            'routeName': _currentRouteName(),
            'minVisibleTargets': minVisibleTargets,
          },
        ),
      );
    }

    final locator = command.locator;
    final expectedText = _expectedText(command);
    CockpitLocatorResolution? locatorResolution;
    CockpitCommandError? resolutionError;
    var matched = false;
    List<CockpitTarget>? visibleTargets;
    if (expectedText != null &&
        (locator == null ||
            _isSimpleLocatorFor(locator, CockpitLocatorKind.text))) {
      final matchMode = locator?.matchMode ?? _textMatchModeParameter(command);
      final locatorProbe = _context.locatorProbe;
      if (locatorProbe != null) {
        final resolution = locatorProbe(
          locator ?? CockpitLocator(text: expectedText, matchMode: matchMode),
        );
        matched = resolution.isSuccess;
        locatorResolution = resolution.locatorResolution;
        resolutionError = resolution.error;
      } else {
        visibleTargets = _registry.visibleTargets;
        matched = _visibleTargetsContainText(
          visibleTargets,
          expectedText,
          matchMode: matchMode,
        );
        if (matched) {
          locatorResolution = CockpitLocatorResolution(
            matchedKind: CockpitLocatorKind.text,
            matchedValue: expectedText,
          );
        }
      }
    } else if (locator != null) {
      final resolution = _resolveProbe(command);
      matched = resolution.isSuccess;
      locatorResolution = resolution.locatorResolution;
      resolutionError = resolution.error;
    }

    if (matched != absent) {
      return _successExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: locatorResolution,
      );
    }
    if (!absent && resolutionError != null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: resolutionError,
      );
    }
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      locatorResolution: locatorResolution,
      error: CockpitCommandError.timeout(
        message: absent
            ? 'The probed target is currently visible.'
            : 'The probed target is not currently visible.',
        details: <String, Object?>{
          'probe': true,
          'waitCondition': waitCondition,
          'absent': absent,
          'routeName': _currentRouteName(),
          if (visibleTargets != null)
            'visibleTextCandidates': _visibleTextCandidates(
              visibleTargets,
            ).take(12).toList(growable: false),
        },
      ),
    );
  }

  bool _hasEnoughVisibleTargetsForProbe(int minVisibleTargets) {
    if (minVisibleTargets <= 0) {
      return true;
    }
    if (minVisibleTargets == 1) {
      return _registry.hasRouteReadyVisibleTargets;
    }
    return _registry.routeReadyVisibleTargets.length >= minVisibleTargets;
  }

  CockpitTargetResolutionResult _resolveProbe(CockpitCommand command) {
    final locator = command.locator;
    if (locator == null) {
      return _resolve(command);
    }
    return _context.locatorProbe?.call(locator) ?? _resolve(command);
  }

  Future<CockpitCommandExecution> _executeWaitForAbsent(
    CockpitCommand command,
    Stopwatch stopwatch, {
    required int timeoutMs,
    required String waitCondition,
  }) async {
    // A single absent observation can race a route transition or frame
    // rebuild where targets briefly unregister before re-registering, so
    // require two consecutive absent observations separated by a settle.
    var absentStreak = 0;
    while (stopwatch.elapsedMilliseconds <= timeoutMs) {
      final snapshot = _liveSnapshot();
      if (_waitConditionIsAbsent(command, snapshot)) {
        absentStreak += 1;
        if (absentStreak >= 2) {
          return _successExecution(
            command: command,
            durationMs: stopwatch.elapsedMilliseconds,
            snapshot: snapshot.toJson(),
          );
        }
      } else {
        absentStreak = 0;
      }

      final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
      if (remaining <= 0) {
        break;
      }
      final settleCompleted = await _settleWithinCommandBudget(
        Duration(milliseconds: remaining),
      );
      if (!settleCompleted) {
        break;
      }
      await _waitTickHandler(const Duration(milliseconds: 16));
    }

    final failureSnapshot = _liveSnapshot();
    final unconfirmedAbsence = absentStreak > 0;
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      snapshot: failureSnapshot.toJson(),
      error: CockpitCommandError.timeout(
        message: unconfirmedAbsence
            ? 'Timed out waiting for $waitCondition to disappear; it was '
                  'absent at the deadline but stable absence could not be '
                  'confirmed within the budget.'
            : 'Timed out waiting for $waitCondition to disappear; it is still present.',
        details: <String, Object?>{
          'waitCondition': waitCondition,
          'absent': true,
          if (unconfirmedAbsence) 'unconfirmedAbsence': true,
          'timeoutMs': timeoutMs,
          'routeName': failureSnapshot.routeName,
          'visibleTargetCount': _registry.visibleTargets.length,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ).take(12).toList(growable: false),
        },
      ),
    );
  }

  bool _waitConditionIsAbsent(
    CockpitCommand command,
    CockpitSnapshot snapshot,
  ) {
    final routeName = _expectedRouteName(command);
    if (routeName != null && snapshot.routeName == routeName) {
      return false;
    }

    final expectedText = _expectedText(command);
    if (expectedText != null &&
        (command.locator == null ||
            _isSimpleLocatorFor(command.locator!, CockpitLocatorKind.text)) &&
        _visibleTargetsContainText(
          _registry.visibleTargets,
          expectedText,
          matchMode:
              command.locator?.matchMode ?? _textMatchModeParameter(command),
        )) {
      return false;
    }

    final locator = command.locator;
    if (locator != null &&
        !_isSimpleLocatorFor(locator, CockpitLocatorKind.route) &&
        !_isSimpleLocatorFor(locator, CockpitLocatorKind.text)) {
      final resolution = _resolve(command);
      if (resolution.isSuccess ||
          resolution.error?.code == CockpitCommandError.ambiguousTargetCode) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _settleWithinCommandBudget(Duration budget) async {
    if (budget <= Duration.zero) {
      return false;
    }
    try {
      await _postActionSettler().timeout(budget);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<CockpitCommandExecution> _executeCaptureScreenshot(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final capture = await _captureOrchestrator.captureExplicit(
      command,
      waitForNetworkIdleDuringAcceptanceCapture:
          _interactionPolicy.waitForNetworkIdleDuringAcceptanceCapture,
    );
    if (capture == null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        error: CockpitCommandError.unsupportedCapability(
          message: 'Flutter view capture is not available for this executor.',
        ),
      );
    }
    return _successExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      artifacts: capture.artifacts,
      snapshot: capture.snapshot,
      requestedCaptureProfile: capture.requestedCaptureProfile,
      resolvedCaptureKind: capture.resolvedCaptureKind,
      usedCaptureFallback: capture.usedCaptureFallback,
      degradationReason: capture.degradationReason,
      artifactPayloads: capture.artifactPayloads,
    );
  }

  CockpitGestureAction _buildDirectionalGesture({
    required CockpitCommand command,
    required CockpitTarget? target,
    required Offset delta,
    required Duration duration,
    required CockpitCommandType fallbackType,
    Duration holdDuration = Duration.zero,
    double touchSlopX = cockpitDefaultDragTouchSlop,
    double touchSlopY = cockpitDefaultDragTouchSlop,
    int moveEventCount = 0,
  }) {
    final pointerDeviceKind = _pointerDeviceKindParameter(
      command,
      allowTrackpad: true,
    );
    final profile = _gestureProfileParameter(command);
    final sampleHz = _doubleParameter(command, 'sampleHz');
    final frameInterval = _optionalDurationParameter(
      command,
      'frameIntervalMs',
    );
    final initialHoldDuration = _optionalDurationParameter(
      command,
      'initialHoldMs',
    );
    if (pointerDeviceKind == PointerDeviceKind.trackpad) {
      return CockpitGestureAction.panZoom(
        target: target,
        origin: _startPointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: delta,
        duration: duration,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
      );
    }

    return switch (fallbackType) {
      CockpitCommandType.drag => CockpitGestureAction.drag(
        target: target,
        origin: _startPointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: delta,
        duration: duration,
        holdDuration: holdDuration,
        touchSlopX: touchSlopX,
        touchSlopY: touchSlopY,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
        pointerDeviceKind: pointerDeviceKind,
        buttons: _buttonsParameter(command),
      ),
      CockpitCommandType.fling => CockpitGestureAction.fling(
        target: target,
        origin: _startPointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: delta,
        duration: duration,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
        pointerDeviceKind: pointerDeviceKind,
        buttons: _buttonsParameter(command),
      ),
      _ => throw ArgumentError(
        'Directional gestures only support drag and fling fallbacks.',
      ),
    };
  }

  CockpitGestureAction _buildSwipeGesture({
    required CockpitCommand command,
    required CockpitTarget? target,
    required AxisDirection direction,
    required double distanceFactor,
    required Duration duration,
    required int moveEventCount,
  }) {
    final pointerDeviceKind = _pointerDeviceKindParameter(
      command,
      allowTrackpad: true,
    );
    final profile = _gestureProfileParameter(command);
    final sampleHz = _doubleParameter(command, 'sampleHz');
    final frameInterval = _optionalDurationParameter(
      command,
      'frameIntervalMs',
    );
    final initialHoldDuration = _optionalDurationParameter(
      command,
      'initialHoldMs',
    );
    if (pointerDeviceKind == PointerDeviceKind.trackpad) {
      final geometry = target == null
          ? null
          : CockpitTargetGeometryResolver.maybeFromTarget(target);
      final distance = switch (direction) {
        AxisDirection.left || AxisDirection.right =>
          ((geometry?.width ?? 240) * distanceFactor).clamp(24, 640),
        AxisDirection.up || AxisDirection.down =>
          ((geometry?.height ?? 240) * distanceFactor).clamp(24, 640),
      }.toDouble();
      final delta = switch (direction) {
        AxisDirection.left => Offset(-distance, 0),
        AxisDirection.right => Offset(distance, 0),
        AxisDirection.up => Offset(0, -distance),
        AxisDirection.down => Offset(0, distance),
      };
      return CockpitGestureAction.panZoom(
        target: target,
        origin: _startPointParameter(command),
        anchor: _gestureAnchorParameter(command),
        delta: delta,
        duration: duration,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
      );
    }

    return CockpitGestureAction.swipe(
      target: target,
      origin: _startPointParameter(command),
      anchor: _gestureAnchorParameter(command),
      direction: direction,
      distanceFactor: distanceFactor,
      duration: duration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      initialHoldDuration: initialHoldDuration,
      pointerDeviceKind: pointerDeviceKind,
      buttons: _buttonsParameter(command),
    );
  }

  CockpitGestureAction _buildPinchZoomGesture({
    required CockpitCommand command,
    required CockpitTarget? target,
    required double scale,
    required double startSpan,
    required Duration duration,
    required int moveEventCount,
  }) {
    final profile = _gestureProfileParameter(
      command,
      fallback: CockpitGestureProfile.precise,
    );
    final sampleHz = _doubleParameter(command, 'sampleHz');
    final frameInterval = _optionalDurationParameter(
      command,
      'frameIntervalMs',
    );
    final initialHoldDuration = _optionalDurationParameter(
      command,
      'initialHoldMs',
    );
    final pointerDeviceKind = _pointerDeviceKindParameter(
      command,
      allowTrackpad: true,
    );
    if (pointerDeviceKind == PointerDeviceKind.trackpad) {
      return CockpitGestureAction.panZoom(
        target: target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        scale: scale,
        duration: duration,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
      );
    }
    return CockpitGestureAction.pinchZoom(
      target: target,
      origin: _pointParameter(command),
      anchor: _gestureAnchorParameter(command),
      scale: scale,
      startSpan: startSpan,
      duration: duration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      initialHoldDuration: initialHoldDuration,
    );
  }

  CockpitGestureAction _buildRotateGesture({
    required CockpitCommand command,
    required CockpitTarget? target,
    required double rotation,
    required double startSpan,
    required Duration duration,
    required int moveEventCount,
  }) {
    final profile = _gestureProfileParameter(
      command,
      fallback: CockpitGestureProfile.precise,
    );
    final sampleHz = _doubleParameter(command, 'sampleHz');
    final frameInterval = _optionalDurationParameter(
      command,
      'frameIntervalMs',
    );
    final initialHoldDuration = _optionalDurationParameter(
      command,
      'initialHoldMs',
    );
    final pointerDeviceKind = _pointerDeviceKindParameter(
      command,
      allowTrackpad: true,
    );
    if (pointerDeviceKind == PointerDeviceKind.trackpad) {
      return CockpitGestureAction.panZoom(
        target: target,
        origin: _pointParameter(command),
        anchor: _gestureAnchorParameter(command),
        rotation: rotation,
        duration: duration,
        moveEventCount: moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
        initialHoldDuration: initialHoldDuration,
      );
    }
    return CockpitGestureAction.rotate(
      target: target,
      origin: _pointParameter(command),
      anchor: _gestureAnchorParameter(command),
      rotation: rotation,
      startSpan: startSpan,
      duration: duration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      initialHoldDuration: initialHoldDuration,
    );
  }

  Future<CockpitCommandExecution> _executeOptionalTargetGesture({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitGestureAction Function(CockpitTarget? target) actionBuilder,
  }) async {
    final locator = command.locator;
    if (locator == null) {
      return _executeResolvedGesture(
        command: command,
        stopwatch: stopwatch,
        resolution: null,
        actionBuilder: () => actionBuilder(null),
      );
    }

    final resolution = await _resolveInteractiveTarget(command);
    if (!resolution.isSuccess) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        snapshot: _liveSnapshot().toJson(),
        error: resolution.error!,
      );
    }

    return _executeResolvedGesture(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      actionBuilder: () => actionBuilder(resolution.target),
    );
  }

  Future<CockpitCommandExecution> _executeResolvedGesture({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitGestureAction Function() actionBuilder,
    CockpitTargetResolutionResult? resolution,
  }) async {
    final previousRouteName = _currentRouteName();
    await _prepareForAction(command, commandType: command.commandType);
    CockpitGestureAction action;
    try {
      action = actionBuilder();
    } on ArgumentError catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution?.locatorResolution,
        error: CockpitCommandError.invalidGestureParameters(
          message: error.message?.toString() ?? 'Invalid gesture parameters.',
        ),
      );
    }
    final result = await _executeGestureAction(
      command: command,
      stopwatch: stopwatch,
      resolution: resolution,
      action: action,
      previousRouteName: previousRouteName,
    );
    if (result != null) {
      return result;
    }
    return _failureExecution(
      command: command,
      durationMs: stopwatch.elapsedMilliseconds,
      error: CockpitCommandError.unsupportedCapability(
        message: 'Gesture handling is not available for this executor.',
      ),
    );
  }

  Future<CockpitCommandExecution?> _executeGestureAction({
    required CockpitCommand command,
    required Stopwatch stopwatch,
    required CockpitGestureAction action,
    required String? previousRouteName,
    CockpitTargetResolutionResult? resolution,
    List<Map<String, Object?>> warnings = const <Map<String, Object?>>[],
  }) async {
    final gestureHandler = _gestureHandler;
    if (gestureHandler == null) {
      return null;
    }

    final preflight = _preflightGestureHitTest(
      command: command,
      action: action,
      target: resolution?.target,
    );
    if (preflight?.error != null) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution?.locatorResolution,
        snapshot: _liveSnapshot().toJson(),
        error: preflight!.error!,
      );
    }

    try {
      await gestureHandler(action);
    } on ArgumentError catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution?.locatorResolution,
        error: CockpitCommandError.invalidGestureParameters(
          message: error.message?.toString() ?? 'Invalid gesture parameters.',
          details: <String, Object?>{'gestureType': command.commandType.name},
        ),
      );
    } on StateError catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution?.locatorResolution,
        error: CockpitCommandError.gestureExecutionFailed(
          message: error.message,
          details: <String, Object?>{
            'gestureType': command.commandType.name,
            if (command.locator != null) 'locator': command.locator!.toJson(),
          },
        ),
      );
    } on Object catch (error) {
      return _failureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        locatorResolution: resolution?.locatorResolution,
        error: CockpitCommandError.gestureExecutionFailed(
          message: 'Gesture execution failed unexpectedly.',
          details: <String, Object?>{
            'gestureType': command.commandType.name,
            'error': error.toString(),
          },
        ),
      );
    }
    await _stabilizeAfterAction(
      previousRouteName,
      commandType: command.commandType,
    );
    final routeExpectationFailure = await _validateExpectedRouteAfterAction(
      command: command,
      commandType: command.commandType,
      durationMs: stopwatch.elapsedMilliseconds,
      resolution: resolution,
      activationPath: _ActionActivationPath.gesture,
    );
    if (routeExpectationFailure != null) {
      return routeExpectationFailure;
    }
    return _buildSuccessWithOptionalCapture(
      command: command,
      resolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      degradationReason: preflight?.degradationReason,
      warnings: <Map<String, Object?>>[
        ...warnings,
        if (preflight?.warning != null) preflight!.warning!,
      ],
    );
  }

  _CockpitGesturePreflightResult? _preflightGestureHitTest({
    required CockpitCommand command,
    required CockpitGestureAction action,
    required CockpitTarget? target,
  }) {
    if (target == null) {
      return null;
    }
    final policy = _hitTestMissPolicy(command);
    if (policy == CockpitHitTestMissPolicy.ignore) {
      return null;
    }
    final probePosition = _gestureProbePosition(action, target);
    final result = CockpitTargetHitTestInspector.inspect(
      target,
      position: probePosition,
    );
    if (result == null || result.hit) {
      return null;
    }
    final details = <String, Object?>{
      'gestureType': command.commandType.name,
      'target': target.registrationId,
      if (target.displayLabel != null) 'targetLabel': target.displayLabel,
      'routeName': target.routeName,
      'hitTest': result.toJson(),
      'hitTestMissPolicy': policy.name,
    };
    if (policy == CockpitHitTestMissPolicy.fail) {
      return _CockpitGesturePreflightResult.error(
        CockpitCommandError.targetNotHittable(
          message:
              'The resolved target is visible in discovery data but is not '
              'hittable at the gesture position (off-viewport or covered by '
              'another widget). If it is scrolled out of view, run '
              'scrollUntilVisible with the same locator and retry; if it is '
              'covered, dismiss the covering surface first. Pass '
              'hitTestMissPolicy=warn or ignore to override.',
          details: details,
        ),
      );
    }
    return _CockpitGesturePreflightResult.warning(<String, Object?>{
      'code': 'hitTestMiss',
      'message':
          'The gesture target did not win hit testing at the resolved position; execution continued because hitTestMissPolicy=warn.',
      'details': details,
    });
  }

  _CockpitGesturePreflightResult? _preflightTargetHitTest({
    required CockpitCommand command,
    required CockpitCommandType commandType,
    required CockpitTarget target,
  }) {
    final policy = _hitTestMissPolicy(command);
    if (policy == CockpitHitTestMissPolicy.ignore) {
      return null;
    }
    final result = CockpitTargetHitTestInspector.inspect(target);
    if (result == null || result.hit) {
      return null;
    }
    final details = <String, Object?>{
      'commandType': commandType.name,
      'target': target.registrationId,
      if (target.displayLabel != null) 'targetLabel': target.displayLabel,
      'routeName': target.routeName,
      'hitTest': result.toJson(),
      'hitTestMissPolicy': policy.name,
    };
    if (policy == CockpitHitTestMissPolicy.fail) {
      return _CockpitGesturePreflightResult.error(
        CockpitCommandError.targetNotHittable(
          message:
              'The resolved target is visible but is not hittable because it is covered or outside the active viewport.',
          details: details,
        ),
      );
    }
    return _CockpitGesturePreflightResult.warning(<String, Object?>{
      'code': 'hitTestMiss',
      'message':
          'The resolved target did not win hit testing; execution continued because hitTestMissPolicy=warn.',
      'details': details,
    });
  }

  Offset? _gestureProbePosition(
    CockpitGestureAction action,
    CockpitTarget? target,
  ) {
    if (action.origin != null) {
      return action.origin;
    }
    final geometry =
        action.geometry ??
        (target == null
            ? null
            : CockpitTargetGeometryResolver.maybeFromTarget(target));
    if (geometry == null) {
      return null;
    }
    final anchor = action.anchor == CockpitGestureAnchor.textHitTestable
        ? CockpitGestureAnchor.center
        : action.anchor;
    final resolved = geometry.resolveAnchorPosition(anchor);
    return Offset(resolved.dx, resolved.dy);
  }

  CockpitTargetResolutionResult _resolve(
    CockpitCommand command, {
    CockpitCommandType? requiredCommand,
  }) {
    final locator = command.locator;
    if (locator == null) {
      if (requiredCommand == CockpitCommandType.dismiss) {
        return _registry.resolveCommand(requiredCommand!);
      }
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'Command requires a locator but none was provided.',
        ),
      );
    }
    return _context.locatorProbe?.call(
          locator,
          requiredCommand: requiredCommand,
        ) ??
        _registry.resolve(locator, requiredCommand: requiredCommand);
  }

  Future<CockpitTargetResolutionResult> _resolveInteractiveTarget(
    CockpitCommand command, {
    CockpitCommandType? requiredCommand,
  }) async {
    var resolution = _resolve(command, requiredCommand: requiredCommand);
    if (_shouldStopResolutionRetry(resolution)) {
      return resolution;
    }

    final locator = command.locator;
    if (locator == null || locator.kind == CockpitLocatorKind.route) {
      return _resolveWithRetry(command, requiredCommand: requiredCommand);
    }

    const revealDuration = Duration(milliseconds: 220);
    if (await _attemptEnsureVisible(
      locator,
      revealDuration,
      alignment: CockpitRevealAlignment.nearest,
      padding: 0,
      offset: 0,
    )) {
      resolution = _resolve(command, requiredCommand: requiredCommand);
      if (_shouldStopResolutionRetry(resolution)) {
        return resolution;
      }
    }

    if (_scrollStepHandler != null) {
      final reveal = await _executeScrollUntilVisible(
        CockpitCommand(
          commandId: '${command.commandId}-reveal',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: locator,
          snapshotOptions: const CockpitSnapshotOptions(maxTargets: 0),
          parameters: const <String, Object?>{
            'maxScrolls': 12,
            'viewportFraction': 0.8,
          },
        ),
        Stopwatch()..start(),
      );
      if (reveal.result.success) {
        resolution = _resolve(command, requiredCommand: requiredCommand);
        if (_shouldStopResolutionRetry(resolution)) {
          return resolution;
        }
      } else if (reveal.result.error case final error?) {
        return CockpitTargetResolutionResult.failure(
          error: CockpitCommandError(
            code: error.code,
            message: error.message,
            details: <String, Object?>{
              ...error.details,
              'action': command.commandType.name,
              'autoReveal': true,
            },
          ),
        );
      }
    }

    return _resolveWithRetry(command, requiredCommand: requiredCommand);
  }

  Future<CockpitTargetResolutionResult> _resolveWithRetry(
    CockpitCommand command, {
    int attempts = 3,
    CockpitCommandType? requiredCommand,
  }) async {
    var resolution = _resolve(command, requiredCommand: requiredCommand);
    if (!_shouldStopResolutionRetry(resolution)) {
      _liveSnapshot();
      resolution = _resolve(command, requiredCommand: requiredCommand);
    }
    if (_shouldStopResolutionRetry(resolution) || attempts <= 1) {
      return _enrichResolutionFailure(command, resolution);
    }

    final resolveTimeout = _durationFromOptionalPositiveInt(
      command,
      key: 'preActionTimeoutMs',
      fallback: _interactionPolicy.targetResolveTimeout,
    );
    final resolvePollInterval = _durationFromOptionalPositiveInt(
      command,
      key: 'preActionPollIntervalMs',
      fallback: _interactionPolicy.targetResolvePollInterval,
    );
    final stopwatch = Stopwatch()..start();
    var retryCount = 0;
    while (retryCount < attempts - 1 || stopwatch.elapsed < resolveTimeout) {
      await _postActionSettler();
      if (_usesTestBinding() && !_hasCustomWaitTickHandler) {
        await Future<void>.microtask(() {});
      } else {
        await _waitTickHandler(resolvePollInterval);
      }
      await _settleBeforeObservation();
      _liveSnapshot();
      resolution = _resolve(command, requiredCommand: requiredCommand);
      if (_shouldStopResolutionRetry(resolution)) {
        return _enrichResolutionFailure(command, resolution);
      }
      retryCount += 1;
    }
    return _enrichResolutionFailure(command, resolution);
  }

  bool _shouldStopResolutionRetry(CockpitTargetResolutionResult resolution) {
    return resolution.isSuccess ||
        resolution.error?.code != CockpitCommandError.targetNotFoundCode;
  }

  CockpitTargetResolutionResult _enrichResolutionFailure(
    CockpitCommand command,
    CockpitTargetResolutionResult resolution,
  ) {
    return _registry.withDiscoverySnapshot(() {
      final error = resolution.error;
      if (error == null ||
          error.code != CockpitCommandError.targetNotFoundCode ||
          command.locator == null) {
        return resolution;
      }
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: error.message,
          details: <String, Object?>{
            ...error.details,
            'routeName': _liveSnapshot().routeName,
            'visibleTargetCount': _registry.visibleTargets.length,
            'visibleTargetHints': _visibleTargetHints(),
            'visibleTextCandidates': _visibleTextCandidates(
              _registry.visibleTargets,
            ).take(12).toList(growable: false),
            'emptyRouteHint': ?_emptyRouteHint(),
          },
        ),
        matches: resolution.matches,
      );
    });
  }

  String? _emptyRouteHint() {
    final routeName = _liveSnapshot().routeName;
    if (routeName == null || routeName.isEmpty) {
      return null;
    }
    if (_registry.visibleTargets.isNotEmpty) {
      return null;
    }
    return 'The current route is ready but target discovery is still empty. Read app state or inspect UI before retrying, or keep route-crossing steps in one run-batch.';
  }

  List<Map<String, Object?>> _visibleTargetHints() {
    final prioritized = _registry.visibleTargets.toList(growable: false)
      ..sort((left, right) {
        final commandCompare = right.supportedCommands.length.compareTo(
          left.supportedCommands.length,
        );
        if (commandCompare != 0) {
          return commandCompare;
        }

        final leftSignalCount = _hintSignalCount(left);
        final rightSignalCount = _hintSignalCount(right);
        final signalCompare = rightSignalCount.compareTo(leftSignalCount);
        if (signalCompare != 0) {
          return signalCompare;
        }

        return left.registrationId.compareTo(right.registrationId);
      });

    final hints = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final target in prioritized) {
      final hint = <String, Object?>{
        if (target.cockpitId != null) 'cockpitId': target.cockpitId,
        if (target.semanticId != null) 'semanticId': target.semanticId,
        if (target.keyValue != null) 'key': target.keyValue,
        if (target.text != null) 'text': target.text,
        if (target.tooltip != null) 'tooltip': target.tooltip,
        if (target.typeName != null) 'type': target.typeName,
        if (target.routeName.isNotEmpty) 'route': target.routeName,
        if (target.supportedCommands.isNotEmpty)
          'supportedCommands': target.supportedCommands
              .map((command) => command.name)
              .toList(growable: false),
      };
      if (hint.isEmpty) {
        hint['registrationId'] = target.registrationId;
      }
      if (!seen.add(_targetHintSignature(hint))) {
        continue;
      }
      hints.add(hint);
      if (hints.length >= 8) {
        break;
      }
    }
    return hints;
  }

  int _hintSignalCount(CockpitTarget target) {
    var count = 0;
    if (target.cockpitId != null && target.cockpitId!.isNotEmpty) {
      count += 3;
    }
    if (target.semanticId != null && target.semanticId!.isNotEmpty) {
      count += 3;
    }
    if (target.keyValue != null && target.keyValue!.isNotEmpty) {
      count += 2;
    }
    if (target.text != null && target.text!.isNotEmpty) {
      count += 2;
    }
    if (target.tooltip != null && target.tooltip!.isNotEmpty) {
      count += 1;
    }
    return count;
  }

  String _targetHintSignature(Map<String, Object?> hint) {
    return <Object?>[
      hint['cockpitId'],
      hint['semanticId'],
      hint['key'],
      hint['text'],
      hint['tooltip'],
      hint['type'],
      hint['route'],
      hint['supportedCommands'],
    ].join('|');
  }

  List<Map<String, Object?>> _visibleScrollables() {
    final seen = <String>{};
    final scrollables = <Map<String, Object?>>[];
    for (final target in _liveSnapshot().visibleTargets) {
      final key = [
        target.scrollableKeyValue ?? '',
        target.scrollableTypeName ?? '',
        target.scrollablePath ?? '',
      ].join('|');
      if (key == '||' || !seen.add(key)) {
        continue;
      }
      scrollables.add(<String, Object?>{
        if (target.scrollableKeyValue != null) 'key': target.scrollableKeyValue,
        if (target.scrollableTypeName != null)
          'typeName': target.scrollableTypeName,
        if (target.scrollablePath != null) 'path': target.scrollablePath,
      });
      if (scrollables.length >= 8) {
        break;
      }
    }
    return scrollables;
  }

  Future<CockpitCommandExecution> _buildSuccessWithOptionalCapture({
    required CockpitCommand command,
    CockpitTargetResolutionResult? resolution,
    required int durationMs,
    String? degradationReason,
    bool? changed,
    List<Map<String, Object?>> warnings = const <Map<String, Object?>>[],
  }) async {
    final snapshot = _appendWarningsToSnapshot(
      _snapshotProvider(
        options: command.snapshotOptions ?? const CockpitSnapshotOptions.live(),
      ).toJson(),
      warnings,
    );
    final CockpitCaptureArtifacts? capture;
    try {
      capture = await _captureOrchestrator.captureAfterAction(command);
    } on Object catch (error) {
      if (command.captureFailurePolicy ==
          CockpitCaptureFailurePolicy.failCommand) {
        rethrow;
      }
      return _successExecution(
        command: command,
        durationMs: durationMs,
        locatorResolution: resolution?.locatorResolution,
        snapshot: snapshot,
        usedCaptureFallback: true,
        degradationReason: _mergeDegradationReasons(
          degradationReason,
          'afterActionCaptureFailed: $error',
        ),
        changed: changed,
      );
    }
    if (capture == null) {
      return _successExecution(
        command: command,
        durationMs: durationMs,
        locatorResolution: resolution?.locatorResolution,
        snapshot: snapshot,
        degradationReason: degradationReason,
        changed: changed,
      );
    }

    return _successExecution(
      command: command,
      durationMs: durationMs,
      locatorResolution: resolution?.locatorResolution,
      artifacts: capture.artifacts,
      snapshot: _appendWarningsToSnapshot(
        capture.snapshot ?? snapshot,
        warnings,
      ),
      requestedCaptureProfile: capture.requestedCaptureProfile,
      resolvedCaptureKind: capture.resolvedCaptureKind,
      usedCaptureFallback: capture.usedCaptureFallback,
      degradationReason: _mergeDegradationReasons(
        degradationReason,
        capture.degradationReason,
      ),
      changed: changed,
      artifactPayloads: capture.artifactPayloads,
    );
  }

  String? _mergeDegradationReasons(String? primary, String? secondary) {
    if (primary == null || primary.isEmpty) {
      return secondary;
    }
    if (secondary == null || secondary.isEmpty || primary == secondary) {
      return primary;
    }
    return '$primary; $secondary';
  }

  CockpitCommandExecution _successExecution({
    required CockpitCommand command,
    required int durationMs,
    CockpitLocatorResolution? locatorResolution,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, Object?>? snapshot,
    CockpitCaptureProfile? requestedCaptureProfile,
    CockpitCaptureKind? resolvedCaptureKind,
    bool usedCaptureFallback = false,
    String? degradationReason,
    bool? changed,
    Map<String, List<int>> artifactPayloads = const <String, List<int>>{},
  }) {
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        locatorResolution: locatorResolution,
        durationMs: durationMs,
        artifacts: artifacts,
        snapshot: snapshot,
        requestedCaptureProfile: requestedCaptureProfile,
        resolvedCaptureKind: resolvedCaptureKind,
        usedCaptureFallback: usedCaptureFallback,
        degradationReason: degradationReason,
        changed: changed,
      ),
      artifactPayloads: artifactPayloads,
    );
  }

  CockpitCommandExecution _failureExecution({
    required CockpitCommand command,
    required int durationMs,
    required CockpitCommandError error,
    CockpitLocatorResolution? locatorResolution,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, Object?>? snapshot,
  }) {
    return _registry.withDiscoverySnapshot(() {
      final enrichedError = (_boolParameter(command, 'probe') ?? false)
          ? error
          : _enrichFailureError(
              command: command,
              durationMs: durationMs,
              error: error,
              snapshot: snapshot,
            );
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: command.commandId,
          commandType: command.commandType,
          locatorResolution: locatorResolution,
          durationMs: durationMs,
          artifacts: artifacts,
          snapshot: snapshot,
          error: enrichedError,
        ),
      );
    });
  }

  CockpitCommandExecution _unsupportedExecution({
    required CockpitCommand command,
    required int durationMs,
    required CockpitTarget target,
  }) {
    return _failureExecution(
      command: command,
      durationMs: durationMs,
      error: CockpitCommandError.unsupportedCapability(
        message:
            '${command.commandType.name} is not supported by target ${target.registrationId}.',
        details: <String, Object?>{
          'target': target.registrationId,
          'commandType': command.commandType.name,
        },
      ),
    );
  }

  static Future<void> _defaultPostActionSettler() async {
    SchedulerBinding schedulerBinding;
    WidgetsBinding widgetsBinding;
    try {
      schedulerBinding = SchedulerBinding.instance;
      widgetsBinding = WidgetsBinding.instance;
    } on Object {
      return;
    }
    if (_isTestBinding(widgetsBinding)) {
      return;
    }
    await Future<void>.microtask(() {});
    if (schedulerBinding.schedulerPhase != SchedulerPhase.idle ||
        widgetsBinding.hasScheduledFrame) {
      try {
        await widgetsBinding.endOfFrame.timeout(
          const Duration(milliseconds: 250),
        );
      } on TimeoutException {
        // The following idle/route probes provide the authoritative wait.
      }
      await Future<void>.microtask(() {});
    }
  }

  static Future<void> _defaultWaitTickHandler(Duration duration) {
    return Future<void>.delayed(duration);
  }

  static Future<bool> _defaultKeyEventHandler(
    CockpitKeyEventRequest request,
    CockpitCommandType type,
  ) async {
    bool dispatchKeyEvent(KeyEvent event) {
      final hardwareHandled = HardwareKeyboard.instance.handleKeyEvent(event);
      final focusHandled =
          ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
            KeyMessage(<KeyEvent>[event], null),
          ) ??
          false;
      return hardwareHandled || focusHandled;
    }

    final physicalKey =
        request.physicalKey ?? PhysicalKeyboardKey(request.logicalKey.keyId);
    final keyEvent = switch (type) {
      CockpitCommandType.sendKeyEvent ||
      CockpitCommandType.sendKeyDownEvent => KeyDownEvent(
        physicalKey: physicalKey,
        logicalKey: request.logicalKey,
        timeStamp: Duration.zero,
        character:
            request.character ?? _fallbackCharacterFor(request.logicalKey),
        synthesized: true,
      ),
      CockpitCommandType.sendKeyUpEvent => KeyUpEvent(
        physicalKey: physicalKey,
        logicalKey: request.logicalKey,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
      _ => throw ArgumentError.value(
        type,
        'type',
        'Unsupported key event type.',
      ),
    };
    final handled = dispatchKeyEvent(keyEvent);
    if (type != CockpitCommandType.sendKeyEvent) {
      return handled;
    }
    final releaseHandled = dispatchKeyEvent(
      KeyUpEvent(
        physicalKey: physicalKey,
        logicalKey: request.logicalKey,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
    );
    return handled || releaseHandled;
  }

  static String? _fallbackCharacterFor(LogicalKeyboardKey logicalKey) {
    final label = logicalKey.keyLabel;
    return label.isEmpty ? null : label;
  }

  Future<void> _stabilizeAfterAction(
    String? previousRouteName, {
    CockpitCommandType? commandType,
    bool routeAlreadyCommitted = false,
  }) async {
    if (!routeAlreadyCommitted) {
      await _settleCoordinator.driveHiddenVisualFrames(commandType);
    }
    await _postActionSettler();
    await _waitForGestureCommit(commandType);
    final routeChanged =
        routeAlreadyCommitted || await _waitForRouteTargets(previousRouteName);
    await _settleBeforeObservation();
    await _waitForVisualContinuity(
      commandType: commandType,
      routeChanged: routeChanged,
    );
  }

  bool? _changedSince(_ActionCommitResult commit) {
    final before = commit.beforeActionFingerprint;
    if (before != null && _actionCommitFingerprint() != before) {
      return true;
    }
    final target = commit.interactedTarget;
    final beforeTargetState = commit.beforeTargetInteractionState;
    if (target != null && beforeTargetState != null) {
      final currentTargetState = _targetInteractionState(
        _currentTargetFor(target) ?? target,
      );
      if (currentTargetState != null &&
          currentTargetState != beforeTargetState) {
        return true;
      }
    }
    return null;
  }

  CockpitTarget? _currentTargetFor(CockpitTarget previous) {
    for (final target in _registry.routeReadyVisibleTargets) {
      if (target.registrationId == previous.registrationId) {
        return target;
      }
    }
    return null;
  }

  Future<_ActionCommitResult> _invokeActionAndAwaitCommit({
    required CockpitCommand command,
    required FutureOr<void> Function() action,
    required String? previousRouteName,
    required CockpitCommandType commandType,
    required Stopwatch stopwatch,
    required _ActionActivationPath activationPath,
    CockpitTargetResolutionResult? resolution,
  }) async {
    final beforeActionFingerprint = _actionCommitFingerprint();
    final interactedTarget = resolution?.target;
    final beforeTargetInteractionState = interactedTarget == null
        ? null
        : _targetInteractionState(interactedTarget);
    final routeNameBeforeAction = _currentRouteName();
    FutureOr<void> result;
    try {
      result = action();
    } on Object catch (error) {
      return _ActionCommitResult.failure(
        _actionFailureExecution(
          command: command,
          commandType: commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          resolution: resolution,
          error: error,
        ),
      );
    }
    if (result is! Future<void>) {
      return _ActionCommitResult(
        beforeActionFingerprint: beforeActionFingerprint,
        interactedTarget: interactedTarget,
        beforeTargetInteractionState: beforeTargetInteractionState,
        diagnostics: _actionDiagnostics(
          command: command,
          commandType: commandType,
          activationPath: activationPath,
          resolution: resolution,
          previousRouteName: previousRouteName,
          routeNameBeforeAction: routeNameBeforeAction,
          beforeActionFingerprint: beforeActionFingerprint,
          actionReturnedFuture: false,
          actionCompleted: true,
          commitOutcome: _ActionCommitOutcome.actionCompleted,
          routeCommitted: _routeChangedFrom(previousRouteName),
        ),
      );
    }

    Object? actionError;
    var actionCompleted = false;
    var waitingForActionCompletion = true;
    unawaited(
      result.then(
        (_) {
          actionCompleted = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!waitingForActionCompletion) {
            Zone.current.handleUncaughtError(error, stackTrace);
            return;
          }
          actionError = error;
          actionCompleted = true;
        },
      ),
    );

    final commitTimeout = _interactionPolicy.actionCommitTimeout;
    late final _ActionCommitOutcome commitOutcome;
    var routeCommitted = false;
    try {
      commitOutcome = await _waitForActionCommit(
        previousRouteName,
        () => actionCompleted,
        beforeActionFingerprint: beforeActionFingerprint,
        timeout: commitTimeout,
        didRouteCommit: () => routeCommitted = true,
      );
    } finally {
      waitingForActionCompletion = false;
    }
    if (actionError case final error?) {
      return _ActionCommitResult.failure(
        _actionFailureExecution(
          command: command,
          commandType: commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          resolution: resolution,
          error: error,
        ),
      );
    }
    if (commitOutcome == _ActionCommitOutcome.actionCompleted ||
        commitOutcome == _ActionCommitOutcome.uiCommitted) {
      return _ActionCommitResult(
        beforeActionFingerprint: beforeActionFingerprint,
        interactedTarget: interactedTarget,
        beforeTargetInteractionState: beforeTargetInteractionState,
        routeCommitted: routeCommitted,
        diagnostics: _actionDiagnostics(
          command: command,
          commandType: commandType,
          activationPath: activationPath,
          resolution: resolution,
          previousRouteName: previousRouteName,
          routeNameBeforeAction: routeNameBeforeAction,
          beforeActionFingerprint: beforeActionFingerprint,
          actionReturnedFuture: true,
          actionCompleted: actionCompleted,
          commitOutcome: commitOutcome,
          routeCommitted: routeCommitted,
        ),
      );
    }
    return _ActionCommitResult(
      beforeActionFingerprint: beforeActionFingerprint,
      interactedTarget: interactedTarget,
      beforeTargetInteractionState: beforeTargetInteractionState,
      diagnostics: _actionDiagnostics(
        command: command,
        commandType: commandType,
        activationPath: activationPath,
        resolution: resolution,
        previousRouteName: previousRouteName,
        routeNameBeforeAction: routeNameBeforeAction,
        beforeActionFingerprint: beforeActionFingerprint,
        actionReturnedFuture: true,
        actionCompleted: actionCompleted,
        commitOutcome: commitOutcome,
        routeCommitted: routeCommitted,
      ),
      warnings: <Map<String, Object?>>[
        <String, Object?>{
          'code': 'asyncActionStillRunning',
          'message':
              'The action callback returned a Future that did not complete before the UI commit window elapsed. '
              'The command continued after collecting a stable UI snapshot; use an explicit waitFor/assert command for business completion.',
          'details': <String, Object?>{
            'commandType': commandType.name,
            'timeoutMs': commitTimeout.inMilliseconds,
            'previousRouteName': ?previousRouteName,
            'routeName': _currentRouteName(),
          },
        },
      ],
    );
  }

  CockpitCommandExecution _actionFailureExecution({
    required CockpitCommand command,
    required CockpitCommandType commandType,
    required int durationMs,
    required Object error,
    CockpitTargetResolutionResult? resolution,
  }) {
    return _failureExecution(
      command: command,
      durationMs: durationMs,
      locatorResolution: resolution?.locatorResolution,
      snapshot: _liveSnapshot().toJson(),
      error: CockpitCommandError.gestureExecutionFailed(
        message: 'Action callback for ${commandType.name} failed: $error',
        details: <String, Object?>{
          'commandType': commandType.name,
          if (command.locator != null) 'locator': command.locator!.toJson(),
        },
      ),
    );
  }

  Future<_ActionCommitOutcome> _waitForActionCommit(
    String? previousRouteName,
    bool Function() actionCompleted, {
    required String beforeActionFingerprint,
    required Duration timeout,
    required void Function() didRouteCommit,
  }) async {
    if (timeout <= Duration.zero) {
      return _ActionCommitOutcome.actionCompleted;
    }
    final deadline = DateTime.now().add(timeout);
    var readinessProbeCount = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (actionCompleted()) {
        return _ActionCommitOutcome.actionCompleted;
      }
      await _waitTickHandler(const Duration(milliseconds: 16));
      if (actionCompleted()) {
        return _ActionCommitOutcome.actionCompleted;
      }
      final routeChanged = _routeChangedFrom(previousRouteName);
      if (routeChanged &&
          _hasRouteReadyVisibleTargetsWithBudget(readinessProbeCount)) {
        didRouteCommit();
        return _ActionCommitOutcome.uiCommitted;
      }
      if (routeChanged) {
        readinessProbeCount += 1;
      }
      if (_actionCommitFingerprint() != beforeActionFingerprint) {
        return _ActionCommitOutcome.uiCommitted;
      }
    }
    return _ActionCommitOutcome.timedOut;
  }

  Future<CockpitCommandExecution?> _validateExpectedRouteAfterAction({
    required CockpitCommand command,
    required CockpitCommandType commandType,
    required int durationMs,
    CockpitTargetResolutionResult? resolution,
    _ActionActivationPath? activationPath,
    Map<String, Object?>? actionDiagnostics,
    Duration? timeoutOverride,
  }) async {
    final routeName = _expectedRouteName(command);
    if (routeName == null) {
      return null;
    }
    final timeout = timeoutOverride ?? _actionExpectationTimeout(command);
    final minVisibleTargets = _minVisibleTargetsForWait(command);
    final reached = await _waitForExpectedRouteTargets(
      routeName,
      minVisibleTargets: minVisibleTargets,
      timeout: timeout,
    );
    if (reached) {
      return null;
    }
    final snapshot = _liveSnapshot();
    return _failureExecution(
      command: command,
      durationMs: durationMs,
      locatorResolution: resolution?.locatorResolution,
      snapshot: snapshot.toJson(),
      error: CockpitCommandError.timeout(
        message:
            'Timed out waiting for route "$routeName" after ${commandType.name}.',
        details: <String, Object?>{
          'commandType': commandType.name,
          'expectedRouteName': routeName,
          'routeName': snapshot.routeName,
          'minVisibleTargets': minVisibleTargets,
          'routeReadyVisibleTargetCount':
              _registry.routeReadyVisibleTargets.length,
          'visibleTargetCount': _registry.visibleTargets.length,
          'timeoutMs': timeout.inMilliseconds,
          'visibleTextCandidates': _visibleTextCandidates(
            _registry.visibleTargets,
          ),
          'targetDiscoveryDiagnostics': _registry.routeDiagnostics(
            hintLimit: 6,
          ),
          'failureDiagnostics': _failureDiagnostics(
            command: command,
            commandType: commandType,
            expectedRouteName: routeName,
            durationMs: durationMs,
            timeout: timeout,
            snapshot: snapshot,
            resolution: resolution,
            activationPath: activationPath,
            actionDiagnostics: actionDiagnostics,
          ),
        },
      ),
    );
  }

  Duration _actionExpectationTimeout(CockpitCommand command) {
    final explicitRouteTimeoutMs =
        _intParameter(command, 'routeTimeoutMs') ??
        _intParameter(command, 'expectedRouteTimeoutMs') ??
        _intParameter(command, 'actionExpectationTimeoutMs');
    if (explicitRouteTimeoutMs != null && explicitRouteTimeoutMs > 0) {
      return Duration(milliseconds: explicitRouteTimeoutMs);
    }
    return _interactionPolicy.actionCommitTimeout;
  }

  Map<String, Object?> _failureDiagnostics({
    required CockpitCommand command,
    required CockpitCommandType commandType,
    required String? expectedRouteName,
    required int durationMs,
    required Duration timeout,
    required CockpitSnapshot snapshot,
    CockpitTargetResolutionResult? resolution,
    _ActionActivationPath? activationPath,
    Map<String, Object?>? actionDiagnostics,
  }) {
    final diagnostics = <String, Object?>{
      'schemaVersion': 1,
      'platform': _platform,
      'transportType': _transportType,
      'commandId': command.commandId,
      'commandType': commandType.name,
      'errorCode': CockpitCommandError.timeoutCode,
      if (command.locator != null) 'locator': command.locator!.toJson(),
      'expectedRouteName': ?expectedRouteName,
      'routeName': snapshot.routeName,
      'durationMs': durationMs,
      'timeoutMs': timeout.inMilliseconds,
      'visibleTargetCount': _registry.visibleTargets.length,
      'routeReadyVisibleTargetCount': _registry.routeReadyVisibleTargets.length,
      'visibleTextCandidates': _visibleTextCandidates(
        _registry.visibleTargets,
      ).take(12).toList(growable: false),
      'targetDiscoveryDiagnostics': _registry.routeDiagnostics(hintLimit: 6),
      if (resolution?.locatorResolution != null)
        'locatorResolution': resolution!.locatorResolution!.toJson(),
      if (resolution?.target != null)
        'resolvedTarget': _diagnosticTargetSummary(resolution!.target!),
      'attemptedActivation':
          actionDiagnostics?['activation'] ?? activationPath?.name,
      ...?actionDiagnostics,
    };
    diagnostics['recommendedNextStep'] = _recommendedNextStepForFailure(
      commandType: commandType,
      expectedRouteName: expectedRouteName,
      diagnostics: diagnostics,
    );
    return diagnostics;
  }

  Map<String, Object?> _actionDiagnostics({
    required CockpitCommand command,
    required CockpitCommandType commandType,
    required _ActionActivationPath activationPath,
    required String? previousRouteName,
    required String? routeNameBeforeAction,
    required String beforeActionFingerprint,
    required bool actionReturnedFuture,
    required bool actionCompleted,
    required _ActionCommitOutcome commitOutcome,
    required bool routeCommitted,
    CockpitTargetResolutionResult? resolution,
  }) {
    final routeNameAfterAction = _currentRouteName();
    final afterActionFingerprint = _actionCommitFingerprint();
    return <String, Object?>{
      'activation': activationPath.name,
      'previousRouteName': ?previousRouteName,
      'routeNameBeforeAction': ?routeNameBeforeAction,
      'routeName': routeNameAfterAction,
      'routeChanged':
          previousRouteName != null &&
          routeNameAfterAction != previousRouteName,
      'routeCommitted': routeCommitted,
      'uiFingerprintChanged': afterActionFingerprint != beforeActionFingerprint,
      'actionReturnedFuture': actionReturnedFuture,
      'actionCompleted': actionCompleted,
      'commitOutcome': commitOutcome.name,
      if (resolution?.target != null)
        'resolvedTarget': _diagnosticTargetSummary(resolution!.target!),
      if (command.locator != null) 'locator': command.locator!.toJson(),
      'commandType': commandType.name,
    };
  }

  Map<String, Object?> _diagnosticTargetSummary(CockpitTarget target) {
    final geometry = CockpitTargetGeometryResolver.maybeFromTarget(target);
    return <String, Object?>{
      'registrationId': target.registrationId,
      if (target.cockpitId != null) 'cockpitId': target.cockpitId,
      if (target.semanticId != null) 'semanticId': target.semanticId,
      if (target.keyValue != null) 'key': target.keyValue,
      if (target.text != null) 'text': target.text,
      if (target.tooltip != null) 'tooltip': target.tooltip,
      if (target.typeName != null) 'type': target.typeName,
      if (target.path != null) 'path': target.path,
      if (target.routeName.isNotEmpty) 'route': target.routeName,
      if (target.supportedCommands.isNotEmpty)
        'supportedCommands': target.supportedCommands
            .map((command) => command.name)
            .toList(growable: false),
      'isVisible': target.isVisible,
      'hasDirectTap': target.onTap != null,
      'hasSemanticTap': target.onSemanticTap != null,
      'hasGestureGeometry': geometry != null,
      if (geometry != null) 'geometry': geometry.toJson(),
    };
  }

  String _recommendedNextStepForFailure({
    required CockpitCommandType commandType,
    required String? expectedRouteName,
    required Map<String, Object?> diagnostics,
  }) {
    if (expectedRouteName != null &&
        diagnostics['routeChanged'] == false &&
        diagnostics['uiFingerprintChanged'] == false) {
      return 'The target was resolved but the $commandType activation did not change route or UI state. Inspect activation, focus, and hit-test diagnostics; retry with gesture activation only if direct/semantic activation is proven not to fire.';
    }
    if (expectedRouteName != null &&
        diagnostics['routeName'] == expectedRouteName &&
        diagnostics['routeReadyVisibleTargetCount'] == 0) {
      return 'The route was reached but no route-ready targets were discovered. Inspect snapshot diagnostics for route binding or target discovery gaps.';
    }
    return 'Inspect failureDiagnostics before changing timeouts or platform-specific behavior.';
  }

  CockpitCommandError _enrichFailureError({
    required CockpitCommand command,
    required int durationMs,
    required CockpitCommandError error,
    Map<String, Object?>? snapshot,
  }) {
    if (error.details.containsKey('failureDiagnostics')) {
      return error;
    }
    return CockpitCommandError(
      code: error.code,
      message: error.message,
      details: <String, Object?>{
        ...error.details,
        'failureDiagnostics': _basicFailureDiagnostics(
          command: command,
          durationMs: durationMs,
          error: error,
          snapshot: snapshot,
        ),
      },
    );
  }

  Map<String, Object?> _basicFailureDiagnostics({
    required CockpitCommand command,
    required int durationMs,
    required CockpitCommandError error,
    Map<String, Object?>? snapshot,
  }) {
    final routeName = snapshot?['routeName'] as String? ?? _currentRouteName();
    return <String, Object?>{
      'schemaVersion': 1,
      'platform': _platform,
      'transportType': _transportType,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'errorCode': error.code,
      'errorMessage': error.message,
      if (command.locator != null) 'locator': command.locator!.toJson(),
      'routeName': routeName,
      'durationMs': durationMs,
      'visibleTargetCount': _registry.visibleTargets.length,
      'routeReadyVisibleTargetCount': _registry.routeReadyVisibleTargets.length,
      'visibleTextCandidates': _visibleTextCandidates(
        _registry.visibleTargets,
      ).take(12).toList(growable: false),
      'targetDiscoveryDiagnostics': _registry.routeDiagnostics(hintLimit: 6),
      'recommendedNextStep':
          'Inspect failureDiagnostics and existing error details before retrying or changing locators, timeouts, or platform-specific behavior.',
    };
  }

  String _actionCommitFingerprint() {
    final targets =
        _registry.registeredTargets
            .where(_isRouteReadyTarget)
            .map(
              (target) => <String?>[
                target.routeName,
                target.registrationId,
                target.cockpitId,
                target.semanticId,
                target.keyValue,
                target.text,
                target.tooltip,
                target.typeName,
                target.path,
              ].whereType<String>().join('\u001f'),
            )
            .toList(growable: false)
          ..sort();
    return <String?>[
      _currentRouteName(),
      targets.join('\u001e'),
    ].whereType<String>().join('\u001d');
  }

  String? _targetInteractionState(CockpitTarget target) {
    final diagnosticNode = target.diagnosticNodeProvider?.call();
    if (diagnosticNode is! Element || !diagnosticNode.mounted) {
      return null;
    }
    var state = _widgetInteractionState(diagnosticNode.widget);
    if (state != null) {
      return state;
    }
    diagnosticNode.visitAncestorElements((ancestor) {
      state = _widgetInteractionState(ancestor.widget);
      return state == null;
    });
    return state;
  }

  String? _widgetInteractionState(Widget widget) {
    if (widget is ChoiceChip) {
      return 'selected:${widget.selected}';
    }
    if (widget is FilterChip) {
      return 'selected:${widget.selected}';
    }
    if (widget is InputChip) {
      return 'selected:${widget.selected}';
    }
    if (widget is Checkbox) {
      return 'checked:${widget.value}';
    }
    if (widget is CheckboxListTile) {
      return 'checked:${widget.value}';
    }
    if (widget is Switch) {
      return 'checked:${widget.value}';
    }
    if (widget is SwitchListTile) {
      return 'checked:${widget.value}';
    }
    if (widget is CupertinoCheckbox) {
      return 'checked:${widget.value}';
    }
    if (widget is CupertinoSwitch) {
      return 'checked:${widget.value}';
    }
    if (widget is Radio) {
      return 'selected:${widget.groupValue == widget.value}';
    }
    if (widget is RadioListTile) {
      return 'selected:${widget.groupValue == widget.value}';
    }
    if (widget is CupertinoRadio) {
      return 'selected:${widget.groupValue == widget.value}';
    }
    if (widget is ToggleButtons) {
      final selection = widget.isSelected
          .map((value) => value ? '1' : '0')
          .join();
      return 'selected:$selection';
    }
    if (widget is SegmentedButton) {
      final selection =
          widget.selected.map((value) => '$value').toList(growable: false)
            ..sort();
      return 'selected:${selection.join('|')}';
    }
    if (widget is Slider) {
      return 'value:${widget.value}';
    }
    if (widget is RangeSlider) {
      return 'value:${widget.values.start}:${widget.values.end}';
    }
    if (widget is CupertinoSlider) {
      return 'value:${widget.value}';
    }
    if (widget is CupertinoSegmentedControl) {
      return 'selected:${widget.groupValue}';
    }
    if (widget is CupertinoSlidingSegmentedControl) {
      return 'selected:${widget.groupValue}';
    }
    if (widget is Semantics) {
      final properties = widget.properties;
      final states = <String?>[
        if (properties.checked != null) 'checked:${properties.checked}',
        if (properties.mixed != null) 'mixed:${properties.mixed}',
        if (properties.selected != null) 'selected:${properties.selected}',
        if (properties.toggled != null) 'toggled:${properties.toggled}',
        if (properties.value case final value? when value.isNotEmpty)
          'value:$value',
      ].whereType<String>().join('|');
      return states.isEmpty ? null : states;
    }
    return null;
  }

  String _observableUiFingerprint() {
    final targets =
        _registry.routeReadyVisibleTargets
            .map(
              (target) => <String?>[
                target.routeName,
                target.registrationId,
                target.cockpitId,
                target.semanticId,
                target.keyValue,
                target.text,
                target.tooltip,
                target.typeName,
                target.path,
              ].whereType<String>().join('\u001f'),
            )
            .toList(growable: false)
          ..sort();
    return <String?>[
      _currentRouteName(),
      targets.join('\u001e'),
    ].whereType<String>().join('\u001d');
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
    if (_settleCoordinator.isHiddenVisualSurface) {
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

  String? _expectedText(CockpitCommand command) {
    final value = command.parameters['text'];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    final locator = command.locator;
    if (locator != null && locator.kind == CockpitLocatorKind.text) {
      return locator.value;
    }
    return null;
  }

  bool _isSimpleLocatorFor(CockpitLocator locator, CockpitLocatorKind kind) {
    return locator.kind == kind &&
        locator.signalMap.length == 1 &&
        locator.ancestor == null &&
        locator.index == null &&
        locator.fallbacks.isEmpty;
  }

  CockpitTextMatchMode _textMatchModeParameter(CockpitCommand command) {
    final value = command.parameters['matchMode'];
    if (value == null) return CockpitTextMatchMode.exact;
    if (value is CockpitTextMatchMode) return value;
    try {
      return CockpitTextMatchMode.fromJson(value);
    } on FormatException catch (error) {
      throw ArgumentError(error.message);
    }
  }

  Future<void> _prepareForAction(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) async {
    await _postActionSettler();
    await _settleBeforeObservation();
    await _waitForPreActionContinuity(command, commandType: commandType);
  }

  CockpitLocatorResolution? _scrollLocatorResolution(CockpitCommand command) {
    final locator = command.locator;
    if (locator == null) {
      return null;
    }

    if (_isSimpleLocatorFor(locator, CockpitLocatorKind.text)) {
      final directProbe = _context.locatorProbe?.call(locator);
      if (directProbe?.isSuccess == true &&
          _isMeaningfullyVisibleTarget(directProbe!.target!)) {
        return directProbe.locatorResolution ??
            CockpitLocatorResolution(
              matchedKind: CockpitLocatorKind.text,
              matchedValue: locator.value,
            );
      }

      if (directProbe != null &&
          directProbe.error?.code != CockpitCommandError.ambiguousTargetCode) {
        return null;
      }

      // Scroll's postcondition is visibility, not unique mutability. A field
      // and its rendered label may both match the same exact text, so an
      // ambiguous Element probe must still fall through to the visible target
      // set. Action commands continue to require one unambiguous target.
      _liveSnapshot();
      if (_visibleTargetsContainMeaningfullyVisibleText(
        _registry.visibleTargets,
        locator.value,
        matchMode: locator.matchMode,
      )) {
        return CockpitLocatorResolution(
          matchedKind: CockpitLocatorKind.text,
          matchedValue: locator.value,
          matchedSignals: locator.matchMode == CockpitTextMatchMode.exact
              ? const <String, String>{}
              : <String, String>{
                  'text': locator.value,
                  'matchMode': locator.matchMode.name,
                },
        );
      }
    }
    if (_isSimpleLocatorFor(locator, CockpitLocatorKind.route) &&
        _currentRouteName() == locator.value) {
      return CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.route,
        matchedValue: locator.value,
      );
    }
    return null;
  }

  CockpitTargetResolutionResult _scrollResolutionSuccess(
    CockpitLocatorResolution locatorResolution,
  ) {
    return CockpitTargetResolutionResult.success(
      target: const CockpitTarget(
        registrationId: 'scroll-until-visible-satisfied',
        routeName: '',
      ),
      locatorResolution: locatorResolution,
    );
  }

  bool _allowsGenericScrollResolution(CockpitLocator locator) {
    return !_isSimpleLocatorFor(locator, CockpitLocatorKind.text) &&
        !_isSimpleLocatorFor(locator, CockpitLocatorKind.route);
  }

  bool _visibleTargetsContainMeaningfullyVisibleText(
    Iterable<CockpitTarget> visibleTargets,
    String expectedText, {
    CockpitTextMatchMode matchMode = CockpitTextMatchMode.exact,
  }) {
    final matches = visibleTargets
        .where(
          (target) =>
              _targetContainsText(target, expectedText, matchMode: matchMode),
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return false;
    }

    return matches.any(_isMeaningfullyVisibleTextTarget);
  }

  bool _isMeaningfullyVisibleTextTarget(CockpitTarget target) {
    return _isMeaningfullyVisibleTarget(target);
  }

  bool _isMeaningfullyVisibleTarget(CockpitTarget target) {
    final hitTest = CockpitTargetHitTestInspector.inspect(target);
    if (hitTest == null) {
      return true;
    }
    return hitTest.withinTargetBounds && hitTest.hit;
  }

  String? _expectedRouteName(CockpitCommand command) {
    final value =
        command.parameters['expectedRouteName'] ??
        command.parameters['expectedRoute'] ??
        command.parameters['routeName'] ??
        command.parameters['route'];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    final locator = command.locator;
    if (locator != null && locator.kind == CockpitLocatorKind.route) {
      return locator.value;
    }
    return null;
  }

  int _minVisibleTargetsForWait(CockpitCommand command) {
    final explicitMin = _intParameter(command, 'minVisibleTargets');
    if (explicitMin != null) {
      if (explicitMin < 0) {
        throw ArgumentError('minVisibleTargets must be zero or positive.');
      }
      return explicitMin;
    }
    final explicitTargetReadiness = _boolParameter(
      command,
      'requireVisibleTargets',
    );
    if (explicitTargetReadiness != null) {
      return explicitTargetReadiness ? 1 : 0;
    }
    return _expectedRouteName(command) == null ? 0 : 1;
  }

  bool _hasEnoughVisibleTargets(int minVisibleTargets) {
    return minVisibleTargets <= 0 ||
        _registry.routeReadyVisibleTargets.length >= minVisibleTargets;
  }

  Future<bool> _waitForExpectedRouteTargets(
    String routeName, {
    required int minVisibleTargets,
    required Duration timeout,
  }) async {
    if (_isExpectedRouteReady(
      routeName,
      minVisibleTargets: minVisibleTargets,
    )) {
      return true;
    }
    if (timeout <= Duration.zero) {
      return false;
    }

    SchedulerBinding schedulerBinding;
    WidgetsBinding widgetsBinding;
    try {
      schedulerBinding = SchedulerBinding.instance;
      widgetsBinding = WidgetsBinding.instance;
    } on Object {
      return false;
    }

    final deadline = DateTime.now().add(timeout);
    final testBindingWithCustomTick =
        _isTestBinding(widgetsBinding) && _hasCustomWaitTickHandler;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.microtask(() {});
      if (schedulerBinding.schedulerPhase != SchedulerPhase.idle ||
          schedulerBinding.hasScheduledFrame) {
        if (testBindingWithCustomTick && schedulerBinding.hasScheduledFrame) {
          await _waitTickHandler(const Duration(milliseconds: 16));
        } else {
          await _awaitFrameIfScheduled(schedulerBinding, widgetsBinding);
        }
      }
      if (_isExpectedRouteReady(
        routeName,
        minVisibleTargets: minVisibleTargets,
      )) {
        return true;
      }
      await _waitTickHandler(const Duration(milliseconds: 16));
    }

    return _isExpectedRouteReady(
      routeName,
      minVisibleTargets: minVisibleTargets,
    );
  }

  bool _isExpectedRouteReady(
    String routeName, {
    required int minVisibleTargets,
  }) {
    final visibleTargets = _registry.visibleTargets;
    if (_currentRouteName() == routeName &&
        _registry.routeReadyVisibleTargets.length >= minVisibleTargets) {
      return true;
    }
    final discoveredRouteTargetCount = visibleTargets
        .where((target) => target.routeName == routeName)
        .length;
    if (discoveredRouteTargetCount < minVisibleTargets ||
        discoveredRouteTargetCount == 0) {
      return false;
    }
    _routeNameSynchronizer?.call(routeName);
    return _currentRouteName() == routeName;
  }

  Duration _durationParameter(
    CockpitCommand command, {
    required String key,
    required int fallbackMs,
  }) {
    final value = _intParameter(command, key);
    if (value == null) {
      return Duration(milliseconds: fallbackMs);
    }
    if (value <= 0) {
      throw ArgumentError('$key must be positive.');
    }
    return Duration(milliseconds: value);
  }

  Duration _optionalDurationParameter(CockpitCommand command, String key) {
    final value = _intParameter(command, key);
    if (value == null) {
      return Duration.zero;
    }
    if (value <= 0) {
      throw ArgumentError('$key must be positive.');
    }
    return Duration(milliseconds: value);
  }

  Duration _durationFromOptionalPositiveInt(
    CockpitCommand command, {
    required String key,
    required Duration fallback,
  }) {
    final value = _intParameter(command, key);
    if (value == null) {
      return fallback;
    }
    if (value <= 0) {
      throw ArgumentError('$key must be positive.');
    }
    return Duration(milliseconds: value);
  }

  int? _intParameter(CockpitCommand command, String key) {
    final value = command.parameters[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  double? _doubleParameter(CockpitCommand command, String key) {
    final value = command.parameters[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  Offset? _pointParameter(CockpitCommand command) {
    final x = _doubleParameter(command, 'x');
    final y = _doubleParameter(command, 'y');
    if (x == null || y == null) {
      return null;
    }
    return Offset(x, y);
  }

  Offset? _startPointParameter(CockpitCommand command) {
    final x =
        _doubleParameter(command, 'startX') ?? _doubleParameter(command, 'x');
    final y =
        _doubleParameter(command, 'startY') ?? _doubleParameter(command, 'y');
    if (x == null || y == null) {
      return null;
    }
    return Offset(x, y);
  }

  bool _allowMissedHit(CockpitCommand command) {
    return _boolParameter(command, 'allowMissedHit') == true ||
        _boolParameter(command, 'warnIfMissed') == false;
  }

  CockpitHitTestMissPolicy _hitTestMissPolicy(CockpitCommand command) {
    if (_allowMissedHit(command)) {
      return CockpitHitTestMissPolicy.ignore;
    }
    return CockpitHitTestMissPolicy.maybeFromJson(
          command.parameters['hitTestMissPolicy'],
        ) ??
        _interactionPolicy.hitTestMissPolicy;
  }

  CockpitTextInputRequest? _textInputRequest(CockpitCommand command) {
    final text = command.parameters['text'];
    final stringText = text is String ? text : null;
    final selectionBase = _intParameter(command, 'selectionBase');
    final selectionExtent =
        _intParameter(command, 'selectionExtent') ?? selectionBase;
    final composingBase = _intParameter(command, 'composingBase');
    final composingExtent =
        _intParameter(command, 'composingExtent') ?? composingBase;
    final inputAction = CockpitTextInputAction.maybeFromJson(
      command.parameters['inputAction'],
    );
    final requestFocus = _boolParameter(command, 'requestFocus') ?? true;
    final clearExisting = _boolParameter(command, 'clearExisting') ?? false;

    if (stringText == null &&
        selectionBase == null &&
        selectionExtent == null &&
        composingBase == null &&
        composingExtent == null &&
        inputAction == null &&
        !requestFocus &&
        !clearExisting) {
      return null;
    }

    return CockpitTextInputRequest(
      text: stringText,
      selectionBase: selectionBase,
      selectionExtent: selectionExtent,
      composingBase: composingBase,
      composingExtent: composingExtent,
      inputAction: inputAction,
      requestFocus: requestFocus,
      clearExisting: clearExisting,
    );
  }

  CockpitKeyEventRequest? _keyEventRequest(CockpitCommand command) {
    if (!command.parameters.containsKey('logicalKey')) {
      return null;
    }
    return CockpitKeyEventRequest.fromJson(command.parameters);
  }

  CockpitGestureProfile _gestureProfileParameter(
    CockpitCommand command, {
    CockpitGestureProfile fallback = CockpitGestureProfile.userLike,
  }) {
    return CockpitGestureProfile.maybeFromJson(
          command.parameters['gestureProfile'],
        ) ??
        fallback;
  }

  CockpitRevealAlignment? _revealAlignmentParameter(CockpitCommand command) {
    return CockpitRevealAlignment.tryParse(
      command.parameters['revealAlignment'],
    );
  }

  CockpitGestureAnchor _gestureAnchorParameter(CockpitCommand command) {
    return CockpitGestureAnchor.maybeFromJson(
      command.parameters['anchor'] ?? command.parameters['gestureAnchor'],
    );
  }

  _TapActivation _tapActivationParameter(CockpitCommand command) {
    final value = command.parameters['activation'];
    if (value is _TapActivation) {
      return value;
    }
    if (value == null) {
      return _TapActivation.auto;
    }
    if (value is! String) {
      throw ArgumentError('activation must be a string.');
    }
    return switch (value.trim().toLowerCase()) {
      '' || 'auto' => _TapActivation.auto,
      'direct' || 'handler' || 'flutter' => _TapActivation.direct,
      'semantic' || 'semantics' || 'accessibility' => _TapActivation.semantic,
      'gesture' || 'pointer' || 'native' => _TapActivation.gesture,
      _ => throw ArgumentError(
        'activation must be one of auto, direct, semantic, or gesture.',
      ),
    };
  }

  Map<String, Object?>? _appendWarningsToSnapshot(
    Map<String, Object?>? snapshot,
    List<Map<String, Object?>> warnings,
  ) {
    if (snapshot == null || warnings.isEmpty) {
      return snapshot;
    }
    final existingWarnings =
        (snapshot['warnings'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((entry) => Map<String, Object?>.from(entry))
            .toList(growable: true);
    existingWarnings.addAll(
      warnings.map((warning) => Map<String, Object?>.from(warning)),
    );
    return <String, Object?>{...snapshot, 'warnings': existingWarnings};
  }

  String? _stringParameter(CockpitCommand command, String key) {
    final value = command.parameters[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  CockpitLocator? _locatorParameter(CockpitCommand command, String key) {
    final value = command.parameters[key];
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return CockpitLocator.fromJson(Map<String, Object?>.from(value));
  }

  bool? _boolParameter(CockpitCommand command, String key) {
    final value = command.parameters[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'y':
        case 'on':
          return true;
        case 'false':
        case '0':
        case 'no':
        case 'n':
        case 'off':
          return false;
      }
    }
    return null;
  }

  PointerDeviceKind _pointerDeviceKindParameter(
    CockpitCommand command, {
    bool allowTrackpad = false,
  }) {
    final rawValue = command.parameters['deviceKind'];
    if (rawValue == null) {
      return _defaultPointerDeviceKindForPlatform();
    }
    final value = switch (rawValue) {
      PointerDeviceKind() => rawValue,
      String() => switch (rawValue.trim().toLowerCase()) {
        'touch' => PointerDeviceKind.touch,
        'mouse' => PointerDeviceKind.mouse,
        'stylus' => PointerDeviceKind.stylus,
        'invertedstylus' ||
        'inverted_stylus' => PointerDeviceKind.invertedStylus,
        'trackpad' => PointerDeviceKind.trackpad,
        'unknown' => PointerDeviceKind.unknown,
        _ => throw ArgumentError(
          'deviceKind must be one of touch, mouse, stylus, invertedStylus, trackpad, or unknown.',
        ),
      },
      _ => throw ArgumentError('deviceKind must be a string.'),
    };
    if (value == PointerDeviceKind.trackpad && !allowTrackpad) {
      throw ArgumentError(
        '${command.commandType.name} does not support deviceKind "trackpad". Use panZoom or a directional gesture that can map to trackpad pan/zoom events.',
      );
    }
    return value;
  }

  PointerDeviceKind _defaultPointerDeviceKindForPlatform() {
    final normalized = _platform.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return switch (normalized) {
      'macos' ||
      'darwin' ||
      'windows' ||
      'linux' ||
      'web' ||
      'chrome' => PointerDeviceKind.mouse,
      _ => PointerDeviceKind.touch,
    };
  }

  int _buttonsParameter(CockpitCommand command) {
    final rawValue =
        command.parameters['buttons'] ?? command.parameters['button'];
    if (rawValue == null) {
      return kPrimaryButton;
    }
    if (rawValue is int) {
      if (rawValue <= 0) {
        throw ArgumentError('buttons must be a positive integer bitmask.');
      }
      return rawValue;
    }
    if (rawValue is! String) {
      throw ArgumentError('buttons must be an integer or a string alias.');
    }

    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError('buttons must not be empty.');
    }
    var mask = 0;
    for (final token in normalized.split(RegExp(r'[\s,+|]+'))) {
      if (token.isEmpty) {
        continue;
      }
      mask |= switch (token) {
        'primary' || 'left' || 'tap' => kPrimaryButton,
        'secondary' || 'right' => kSecondaryButton,
        'tertiary' || 'middle' => kTertiaryButton,
        'back' => kBackMouseButton,
        'forward' => kForwardMouseButton,
        _ => throw ArgumentError(
          'buttons must use aliases primary, secondary, tertiary, back, or forward.',
        ),
      };
    }
    if (mask <= 0) {
      throw ArgumentError('buttons must resolve to at least one input button.');
    }
    return mask;
  }

  AxisDirection? _axisDirectionParameter(Object? value) {
    return switch (value) {
      'left' => AxisDirection.left,
      'right' => AxisDirection.right,
      'up' => AxisDirection.up,
      'down' => AxisDirection.down,
      _ => null,
    };
  }

  bool _visibleTargetsContainText(
    Iterable<CockpitTarget> visibleTargets,
    String expectedText, {
    CockpitTextMatchMode matchMode = CockpitTextMatchMode.contains,
  }) {
    return visibleTargets.any(
      (target) =>
          _targetContainsText(target, expectedText, matchMode: matchMode),
    );
  }

  List<String> _visibleTextCandidates(Iterable<CockpitTarget> visibleTargets) {
    final candidates = <String>{};
    for (final target in visibleTargets) {
      for (final value in <String?>[
        target.text,
        target.tooltip,
        target.displayLabel,
      ]) {
        if (value != null && value.isNotEmpty) {
          candidates.add(value);
        }
      }
    }
    return candidates.toList(growable: false);
  }

  bool _targetContainsText(
    CockpitTarget target,
    String expectedText, {
    CockpitTextMatchMode matchMode = CockpitTextMatchMode.contains,
  }) {
    return <String?>[target.text, target.tooltip, target.displayLabel].any(
      (candidate) => _textSignalMatches(candidate, expectedText, matchMode),
    );
  }

  bool _textSignalMatches(
    String? candidate,
    String expectedText,
    CockpitTextMatchMode matchMode,
  ) {
    final normalizedCandidate = _normalizeText(candidate);
    final normalizedExpected = _normalizeText(expectedText);
    if (normalizedCandidate == null) {
      return false;
    }
    return switch (matchMode) {
      CockpitTextMatchMode.exact =>
        normalizedExpected != null && normalizedCandidate == normalizedExpected,
      CockpitTextMatchMode.contains =>
        normalizedExpected != null &&
            normalizedCandidate.contains(normalizedExpected),
      CockpitTextMatchMode.fuzzy =>
        normalizedExpected != null &&
            cockpitFuzzyTextMatches(normalizedCandidate, normalizedExpected),
      CockpitTextMatchMode.regex => RegExp(
        expectedText.trim(),
      ).hasMatch(normalizedCandidate),
    };
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _describeWaitCondition(CockpitCommand command) {
    final routeName = _expectedRouteName(command);
    if (routeName != null) {
      return 'route "$routeName"';
    }
    final expectedText = _expectedText(command);
    if (expectedText != null) {
      return 'text "$expectedText"';
    }
    final locator = command.locator;
    if (locator != null) {
      return '${locator.kind.name} "${locator.value}"';
    }
    return null;
  }

  Future<void> _settleBeforeObservation() async {
    await _settleCoordinator.settleBeforeObservation();
  }

  String? _currentRouteName() => _registry.routeName;

  bool _routeChangedFrom(String? previousRouteName) {
    return previousRouteName != null &&
        _currentRouteName() != previousRouteName;
  }

  bool _isRouteReadyTarget(CockpitTarget target) {
    if (!target.isVisible) {
      return false;
    }
    final routeName = _currentRouteName();
    return routeName == null ||
        routeName.isEmpty ||
        target.routeName == routeName;
  }

  bool _hasRouteReadyVisibleTargets() {
    return _registry.hasRouteReadyVisibleTargets;
  }

  Future<bool> _waitForRouteTargets(String? previousRouteName) async {
    if (previousRouteName == null) {
      return false;
    }

    SchedulerBinding schedulerBinding;
    WidgetsBinding widgetsBinding;
    try {
      schedulerBinding = SchedulerBinding.instance;
      widgetsBinding = WidgetsBinding.instance;
    } on Object {
      return false;
    }
    final testBindingWithCustomTick =
        _isTestBinding(widgetsBinding) && _hasCustomWaitTickHandler;
    if (_isTestBinding(widgetsBinding) && !_hasCustomWaitTickHandler) {
      return false;
    }

    var readinessProbeCount = 0;
    for (var attempt = 0; attempt < 25; attempt += 1) {
      await Future<void>.microtask(() {});
      if (schedulerBinding.schedulerPhase != SchedulerPhase.idle ||
          schedulerBinding.hasScheduledFrame) {
        if (testBindingWithCustomTick && schedulerBinding.hasScheduledFrame) {
          await _waitTickHandler(const Duration(milliseconds: 16));
        } else {
          await _awaitFrameIfScheduled(schedulerBinding, widgetsBinding);
        }
      }

      final routeChanged = _routeChangedFrom(previousRouteName);
      if (routeChanged &&
          _hasRouteReadyVisibleTargetsWithBudget(readinessProbeCount)) {
        return true;
      }
      if (routeChanged) {
        readinessProbeCount += 1;
      }
      if (!routeChanged && !schedulerBinding.hasScheduledFrame) {
        return false;
      }

      if (schedulerBinding.hasScheduledFrame) {
        if (testBindingWithCustomTick) {
          await _waitTickHandler(const Duration(milliseconds: 16));
        } else {
          await _awaitFrameIfScheduled(schedulerBinding, widgetsBinding);
        }
      } else {
        await _waitTickHandler(const Duration(milliseconds: 16));
      }
    }
    return _routeChangedFrom(previousRouteName);
  }

  bool _hasRouteReadyVisibleTargetsWithBudget(int probeCount) {
    if (_registry.registeredTargets.any(_isRouteReadyTarget)) {
      return true;
    }
    if (probeCount >= _routeTargetReadinessProbeLimit) {
      return false;
    }
    return _hasRouteReadyVisibleTargets();
  }

  Future<void> _waitForVisualContinuity({
    required CockpitCommandType? commandType,
    required bool routeChanged,
  }) async {
    if (_usesTestBinding() && !_hasCustomWaitTickHandler) {
      return;
    }
    if (_settleCoordinator.isHiddenVisualSurface) {
      return;
    }
    final delay = _visualContinuityDelay(
      commandType: commandType,
      routeChanged: routeChanged,
    );
    if (delay <= Duration.zero) {
      return;
    }
    await _waitTickHandler(delay);
  }

  Future<void> _waitForPreActionContinuity(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) async {
    if (_usesTestBinding() && !_hasCustomWaitTickHandler) {
      return;
    }
    if (_settleCoordinator.isHiddenVisualSurface) {
      return;
    }
    final delay = _preActionVisualDelay(command, commandType: commandType);
    if (delay <= Duration.zero) {
      return;
    }
    await _waitTickHandler(delay);
  }

  Duration _preActionVisualDelay(
    CockpitCommand command, {
    required CockpitCommandType commandType,
  }) {
    final isVisualMutation = switch (commandType) {
      CockpitCommandType.tap ||
      CockpitCommandType.hover ||
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
      CockpitCommandType.wheel ||
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
    if (!isVisualMutation) {
      return Duration.zero;
    }
    return _durationFromOptionalPositiveInt(
      command,
      key: 'preActionVisualDelayMs',
      fallback: _isRecordingActive()
          ? _maxDuration(
              _interactionPolicy.preActionVisualDelay,
              _interactionPolicy.recordingPreActionVisualDelay,
            )
          : _interactionPolicy.preActionVisualDelay,
    );
  }

  Duration _visualContinuityDelay({
    required CockpitCommandType? commandType,
    required bool routeChanged,
  }) {
    final isVisualMutation = switch (commandType) {
      CockpitCommandType.tap ||
      CockpitCommandType.hover ||
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
      CockpitCommandType.wheel ||
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
    if (!isVisualMutation && !routeChanged) {
      return Duration.zero;
    }
    if (_isRecordingActive()) {
      return routeChanged
          ? _maxDuration(
              _interactionPolicy.routeTransitionVisualDelay,
              _interactionPolicy.recordingActionVisualDelay,
            )
          : _interactionPolicy.recordingActionVisualDelay;
    }
    return routeChanged
        ? _interactionPolicy.routeTransitionVisualDelay
        : _interactionPolicy.actionVisualDelay;
  }

  Duration _maxDuration(Duration left, Duration right) {
    return left >= right ? left : right;
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

  static bool _isTestBinding(WidgetsBinding widgetsBinding) {
    return widgetsBinding.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  static bool _defaultRecordingActivityProbe() => false;

  static bool _usesTestBinding() {
    try {
      return _isTestBinding(WidgetsBinding.instance);
    } on Object {
      return false;
    }
  }

  static CockpitSnapshotProvider _defaultSnapshotProvider(
    CockpitTargetRegistry registry,
  ) {
    return ({options = const CockpitSnapshotOptions()}) =>
        registry.snapshot().copyWith(focus: cockpitBuildFocusSnapshot());
  }

  CockpitSnapshot _liveSnapshot() {
    return _snapshotProvider(options: const CockpitSnapshotOptions.live());
  }

  CockpitSnapshotOptions _defaultSnapshotOptionsForReason(
    CockpitScreenshotReason reason,
  ) {
    return switch (reason) {
      CockpitScreenshotReason.assertionFailure =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.baseline =>
        const CockpitSnapshotOptions.baseline(),
      CockpitScreenshotReason.acceptance =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.beforeAction ||
      CockpitScreenshotReason.afterAction =>
        const CockpitSnapshotOptions.live(),
    };
  }
}

final class _CockpitGesturePreflightResult {
  const _CockpitGesturePreflightResult._({
    this.error,
    this.warning,
    this.degradationReason,
  });

  const _CockpitGesturePreflightResult.error(CockpitCommandError error)
    : this._(error: error);

  const _CockpitGesturePreflightResult.warning(Map<String, Object?> warning)
    : this._(warning: warning, degradationReason: 'hitTestMissWarning');

  final CockpitCommandError? error;
  final Map<String, Object?>? warning;
  final String? degradationReason;
}

final class _ActionCommitResult {
  const _ActionCommitResult({
    this.warnings = const <Map<String, Object?>>[],
    this.routeCommitted = false,
    this.diagnostics = const <String, Object?>{},
    this.beforeActionFingerprint,
    this.interactedTarget,
    this.beforeTargetInteractionState,
  }) : failure = null;

  const _ActionCommitResult.failure(this.failure)
    : warnings = const <Map<String, Object?>>[],
      routeCommitted = false,
      diagnostics = const <String, Object?>{},
      beforeActionFingerprint = null,
      interactedTarget = null,
      beforeTargetInteractionState = null;

  final List<Map<String, Object?>> warnings;
  final CockpitCommandExecution? failure;
  final bool routeCommitted;
  final Map<String, Object?> diagnostics;
  final String? beforeActionFingerprint;
  final CockpitTarget? interactedTarget;
  final String? beforeTargetInteractionState;
}
