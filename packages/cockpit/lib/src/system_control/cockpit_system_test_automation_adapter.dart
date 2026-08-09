import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../adapters/cockpit_automation_adapter.dart';
import 'cockpit_macos_accessibility_tree.dart';
import 'cockpit_native_ui_snapshot.dart';
import 'cockpit_system_control_action_service.dart';
import 'cockpit_system_control_service.dart';
import 'cockpit_system_test_target.dart';
import 'cockpit_visual_matcher.dart';

final class CockpitSystemTestAutomationAdapter
    implements CockpitAutomationAdapter {
  CockpitSystemTestAutomationAdapter({
    required CockpitSystemTestTarget target,
    required CockpitSystemControlService controlService,
    required CockpitSystemControlActionService actionService,
    required String workspaceRoot,
    DateTime Function()? utcNow,
    Future<void> Function(Duration)? delay,
    CockpitVisualMatcher? visualMatcher,
    CockpitMacosAccessibilityElementPresser? macosAccessibilityElementPresser,
  }) : _target = target,
       _controlService = controlService,
       _actionService = actionService,
       _visualMatcher =
           visualMatcher ?? CockpitVisualMatcher(workspaceRoot: workspaceRoot),
       _macosAccessibilityElementPresser =
           macosAccessibilityElementPresser ??
           cockpitPressMacosAccessibilityElement,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _delay = delay ?? Future<void>.delayed;

  final CockpitSystemTestTarget _target;
  final CockpitSystemControlService _controlService;
  final CockpitSystemControlActionService _actionService;
  final CockpitVisualMatcher _visualMatcher;
  final CockpitMacosAccessibilityElementPresser
  _macosAccessibilityElementPresser;
  final DateTime Function() _utcNow;
  final Future<void> Function(Duration) _delay;

  bool get _flutterAwareNative =>
      _target.targetKind == CockpitTargetKind.flutterApp;

  @override
  Future<CockpitCapabilities> describeCapabilities() async {
    final describe = await _controlService.describe(
      CockpitSystemControlDescribeRequest(
        platform: _target.platform,
        deviceId: _target.deviceId,
        appId: _target.appId,
        processId: _target.processId,
        metadata: _target.metadata,
      ),
    );
    final available = describe.profile.availableActions.toSet();
    final hasTree = available.contains(CockpitSystemControlAction.readUiTree);
    final hasScreenshot = available.contains(
      CockpitSystemControlAction.captureScreenshot,
    );
    final supportedCommands = <CockpitCommandType>{
      CockpitCommandType.system,
      if (available.contains(
        CockpitSystemControlAction.tap,
      )) ...<CockpitCommandType>[
        CockpitCommandType.tap,
        CockpitCommandType.doubleTap,
        CockpitCommandType.focusTextInput,
      ],
      if (available.contains(CockpitSystemControlAction.longPress))
        CockpitCommandType.longPress,
      if (available.contains(CockpitSystemControlAction.typeText))
        CockpitCommandType.enterText,
      if (available.contains(
        CockpitSystemControlAction.pressKey,
      )) ...<CockpitCommandType>[
        CockpitCommandType.sendKeyEvent,
        CockpitCommandType.sendTextInputAction,
        CockpitCommandType.eraseText,
      ],
      if (hasTree &&
          available.contains(CockpitSystemControlAction.setClipboard))
        CockpitCommandType.copyText,
      if (available.contains(CockpitSystemControlAction.getClipboard) &&
          available.contains(CockpitSystemControlAction.typeText))
        CockpitCommandType.pasteText,
      if (available.contains(CockpitSystemControlAction.setLocation))
        CockpitCommandType.travel,
      if (available.contains(
        CockpitSystemControlAction.drag,
      )) ...<CockpitCommandType>[
        CockpitCommandType.drag,
        CockpitCommandType.fling,
        CockpitCommandType.swipe,
      ],
      if (available.contains(CockpitSystemControlAction.pressBack))
        CockpitCommandType.back,
      if (available.contains(CockpitSystemControlAction.dismissKeyboard))
        CockpitCommandType.dismissKeyboard,
      if (hasTree) ...<CockpitCommandType>[
        CockpitCommandType.waitFor,
        CockpitCommandType.waitForUiIdle,
        CockpitCommandType.assertVisible,
        CockpitCommandType.assertText,
        CockpitCommandType.collectSnapshot,
        if (available.contains(CockpitSystemControlAction.drag))
          CockpitCommandType.scrollUntilVisible,
      ],
      if (hasScreenshot) ...<CockpitCommandType>[
        CockpitCommandType.captureScreenshot,
        CockpitCommandType.assertScreenshot,
      ],
    };
    return CockpitCapabilities(
      platform: describe.profile.platform,
      transportType: 'system-control',
      supportsInAppControl: false,
      supportsFlutterViewCapture: false,
      supportsNativeScreenCapture: hasScreenshot,
      supportsHostAutomation: true,
      supportedCommands: supportedCommands.toList(growable: false),
      supportedLocatorStrategies: <CockpitLocatorKind>[
        if (hasTree) ...const <CockpitLocatorKind>[
          CockpitLocatorKind.text,
          CockpitLocatorKind.tooltip,
          CockpitLocatorKind.nativeId,
          CockpitLocatorKind.testId,
          CockpitLocatorKind.role,
          CockpitLocatorKind.type,
          CockpitLocatorKind.path,
        ],
        if (hasTree) CockpitLocatorKind.coordinate,
        if (hasScreenshot) CockpitLocatorKind.visual,
      ],
    );
  }

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await _execute(command, stopwatch);
    } on TimeoutException {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError.timeout(
          message: 'System command exceeded its deadline.',
        ),
      );
    } on FormatException catch (error) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: CockpitCommandError.invalidGestureParametersCode,
          message: error.message,
        ),
      );
    } on _SystemObservationException catch (error) {
      return _failure(command, stopwatch, error.error);
    } on Object catch (error) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: 'systemDriverFailed',
          message: 'System driver failed: $error',
        ),
      );
    }
  }

  Future<CockpitCommandExecution> _execute(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async => switch (command.commandType) {
    CockpitCommandType.tap => _tap(command, stopwatch),
    CockpitCommandType.longPress => _longPress(command, stopwatch),
    CockpitCommandType.doubleTap => _doubleTap(command, stopwatch),
    CockpitCommandType.focusTextInput => _tap(command, stopwatch),
    CockpitCommandType.enterText => _enterText(command, stopwatch),
    CockpitCommandType.eraseText => _eraseText(command, stopwatch),
    CockpitCommandType.copyText => _copyText(command, stopwatch),
    CockpitCommandType.pasteText => _pasteText(command, stopwatch),
    CockpitCommandType.sendKeyEvent ||
    CockpitCommandType.sendTextInputAction => _pressKey(command, stopwatch),
    CockpitCommandType.drag ||
    CockpitCommandType.fling ||
    CockpitCommandType.swipe => _drag(command, stopwatch),
    CockpitCommandType.scrollUntilVisible => _scrollUntilVisible(
      command,
      stopwatch,
    ),
    CockpitCommandType.back => _simpleAction(
      command,
      stopwatch,
      CockpitSystemControlAction.pressBack,
    ),
    CockpitCommandType.dismissKeyboard => _simpleAction(
      command,
      stopwatch,
      CockpitSystemControlAction.dismissKeyboard,
    ),
    CockpitCommandType.waitFor ||
    CockpitCommandType.assertVisible => _waitFor(command, stopwatch),
    CockpitCommandType.assertText => _assertText(command, stopwatch),
    CockpitCommandType.assertScreenshot => _assertScreenshot(
      command,
      stopwatch,
    ),
    CockpitCommandType.captureScreenshot => _captureEvidence(
      command,
      stopwatch,
    ),
    CockpitCommandType.travel => _travel(command, stopwatch),
    CockpitCommandType.system => _systemAction(command, stopwatch),
    CockpitCommandType.waitForUiIdle => _waitForUiIdle(command, stopwatch),
    CockpitCommandType.collectSnapshot => _collectSnapshot(command, stopwatch),
    _ => Future<CockpitCommandExecution>.value(
      _failure(
        command,
        stopwatch,
        CockpitCommandError.unsupportedCapability(
          message:
              'System driver does not support ${command.commandType.name}.',
        ),
      ),
    ),
  };

  Future<CockpitCommandExecution> _systemAction(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final name = command.parameters['action'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('system action requires a non-empty name.');
    }
    CockpitSystemControlAction? action;
    for (final candidate in CockpitSystemControlAction.values) {
      if (candidate.name == name) {
        action = candidate;
        break;
      }
    }
    if (action == null) {
      throw FormatException('Unknown system action $name.');
    }
    if (const <CockpitSystemControlAction>{
      CockpitSystemControlAction.captureScreenshot,
      CockpitSystemControlAction.startRecording,
      CockpitSystemControlAction.stopRecording,
    }.contains(action)) {
      throw FormatException(
        '${action.name} must use the dedicated case evidence operation.',
      );
    }
    final rawParameters = command.parameters['parameters'];
    if (rawParameters != null && rawParameters is! Map<Object?, Object?>) {
      throw const FormatException(
        'system action parameters must be an object.',
      );
    }
    final result = await _runAction(
      action,
      rawParameters == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawParameters as Map<Object?, Object?>),
      _deadline(command),
    );
    return _fromAction(command, stopwatch, result, null);
  }

  Future<CockpitCommandExecution> _tap(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final point = await _resolveStablePoint(command, deadline);
    if (point.error != null) {
      return _failure(
        command,
        stopwatch,
        point.error!,
        artifacts: point.artifacts,
        artifactSourcePaths: point.artifactSourcePaths,
      );
    }
    final nativePath = point.nativePath;
    final processId = _target.processId;
    if (_target.platform.trim().toLowerCase() == 'macos' &&
        processId != null &&
        processId > 0 &&
        nativePath != null) {
      try {
        final remaining = _remaining(deadline);
        final pressed = await _macosAccessibilityElementPresser(
          processId: processId,
          nativePath: nativePath,
          timeout: remaining,
        ).timeout(remaining);
        if (pressed) {
          return _success(
            command,
            stopwatch,
            resolution: point.resolution,
            artifacts: point.artifacts,
            artifactSourcePaths: point.artifactSourcePaths,
          );
        }
      } on CockpitMacosAccessibilityException catch (error) {
        return _failure(
          command,
          stopwatch,
          _macosAccessibilityActionError(error),
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
    }
    final result = await _runAction(
      CockpitSystemControlAction.tap,
      <String, Object?>{'x': point.x, 'y': point.y},
      deadline,
    );
    return _fromAction(
      command,
      stopwatch,
      result,
      point.resolution,
      artifacts: point.artifacts,
      artifactSourcePaths: point.artifactSourcePaths,
    );
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) {
      throw TimeoutException('System command deadline elapsed.');
    }
    return remaining;
  }

  CockpitCommandError _macosAccessibilityActionError(
    CockpitMacosAccessibilityException error,
  ) {
    final details = <String, Object?>{'systemErrorCode': error.code};
    if (const <String>{
      'macosAccessibilityPermissionDenied',
      'macosAccessibilityPermissionStale',
    }.contains(error.code)) {
      return CockpitCommandError.unsupportedCapability(
        message: error.message,
        details: details,
      );
    }
    if (error.code == 'macosAccessibilityTargetStale') {
      return CockpitCommandError.targetNotHittable(
        message: error.message,
        details: details,
      );
    }
    return CockpitCommandError(
      code: 'systemDriverFailed',
      message: error.message,
      details: details,
    );
  }

  Future<CockpitCommandExecution> _longPress(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final point = await _resolveStablePoint(command, deadline);
    if (point.error != null) {
      return _failure(
        command,
        stopwatch,
        point.error!,
        artifacts: point.artifacts,
        artifactSourcePaths: point.artifactSourcePaths,
      );
    }
    final result = await _runAction(
      CockpitSystemControlAction.longPress,
      <String, Object?>{
        'x': point.x,
        'y': point.y,
        if (command.parameters['durationMs'] case final int durationMs)
          'durationMs': durationMs,
      },
      deadline,
    );
    return _fromAction(
      command,
      stopwatch,
      result,
      point.resolution,
      artifacts: point.artifacts,
      artifactSourcePaths: point.artifactSourcePaths,
    );
  }

  Future<CockpitCommandExecution> _doubleTap(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final point = await _resolveStablePoint(command, deadline);
    if (point.error != null) {
      return _failure(
        command,
        stopwatch,
        point.error!,
        artifacts: point.artifacts,
        artifactSourcePaths: point.artifactSourcePaths,
      );
    }
    for (var index = 0; index < 2; index += 1) {
      final result = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!result.success) {
        return _fromAction(
          command,
          stopwatch,
          result,
          point.resolution,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      if (index == 0) await _delay(_boundedDelay(deadline, 80));
    }
    return _success(
      command,
      stopwatch,
      resolution: point.resolution,
      artifacts: point.artifacts,
      artifactSourcePaths: point.artifactSourcePaths,
    );
  }

  Future<CockpitCommandExecution> _enterText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final locator = _locator(command);
    CockpitLocatorResolution? resolution;
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[];
    Map<String, String> sourcePaths = const <String, String>{};
    if (locator != null) {
      final point = await _resolveStablePoint(command, deadline);
      if (point.error != null) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      final focus = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!focus.success) {
        return _fromAction(
          command,
          stopwatch,
          focus,
          point.resolution,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      resolution = point.resolution;
      artifacts = point.artifacts;
      sourcePaths = point.artifactSourcePaths;
    }
    final text = command.parameters['text'];
    if (text is! String) {
      throw const FormatException('enterText requires a string text value.');
    }
    final result = await _runAction(
      CockpitSystemControlAction.typeText,
      <String, Object?>{'text': text},
      deadline,
    );
    return _fromAction(
      command,
      stopwatch,
      result,
      resolution,
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
    );
  }

  Future<CockpitCommandExecution> _eraseText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final locator = _locator(command);
    CockpitLocatorResolution? resolution;
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[];
    Map<String, String> sourcePaths = const <String, String>{};
    int? inferredCharacters;
    if (locator != null) {
      final point = await _resolveStablePoint(command, deadline);
      if (point.error != null) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      final focus = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!focus.success) {
        return _fromAction(
          command,
          stopwatch,
          focus,
          point.resolution,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      resolution = point.resolution;
      artifacts = point.artifacts;
      sourcePaths = point.artifactSourcePaths;
      inferredCharacters = point.textLength;
    }
    var remaining =
        command.parameters['characters'] as int? ?? inferredCharacters ?? 1000;
    while (remaining > 0) {
      final repeat = remaining.clamp(1, 500);
      final result = await _runAction(
        CockpitSystemControlAction.pressKey,
        <String, Object?>{'key': 'backspace', 'repeat': repeat},
        deadline,
      );
      if (!result.success) {
        return _fromAction(
          command,
          stopwatch,
          result,
          resolution,
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      remaining -= repeat;
    }
    return _success(
      command,
      stopwatch,
      resolution: resolution,
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
    );
  }

  Future<CockpitCommandExecution> _copyText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final locator = _locator(command);
    if (locator == null) {
      throw const FormatException('copyText requires a locator.');
    }
    final deadline = _deadline(command);
    final resolved = await _resolveNativeNode(locator, deadline);
    final error = _resolutionError(resolved);
    if (error != null) return _failure(command, stopwatch, error);
    final node = resolved.node!;
    final text = <String>['text', 'value', 'label', 'name']
        .map((key) => node.attributes[key]?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (text == null) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError.assertionFailed(
          message: 'Resolved target does not expose copyable text.',
        ),
      );
    }
    final result = await _runAction(
      CockpitSystemControlAction.setClipboard,
      <String, Object?>{'text': text},
      deadline,
    );
    return _fromAction(
      command,
      stopwatch,
      result,
      _locatorResolution(resolved),
    );
  }

  Future<CockpitCommandExecution> _pasteText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    CockpitLocatorResolution? resolution;
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[];
    Map<String, String> sourcePaths = const <String, String>{};
    final locator = _locator(command);
    if (locator != null) {
      final point = await _resolveStablePoint(command, deadline);
      if (point.error != null) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      final focus = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!focus.success) {
        return _fromAction(
          command,
          stopwatch,
          focus,
          point.resolution,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      resolution = point.resolution;
      artifacts = point.artifacts;
      sourcePaths = point.artifactSourcePaths;
    }
    final clipboard = await _runAction(
      CockpitSystemControlAction.getClipboard,
      const <String, Object?>{},
      deadline,
    );
    if (!clipboard.success) {
      return _fromAction(
        command,
        stopwatch,
        clipboard,
        resolution,
        artifacts: artifacts,
        artifactSourcePaths: sourcePaths,
      );
    }
    final result = await _runAction(
      CockpitSystemControlAction.typeText,
      <String, Object?>{'text': clipboard.stdout ?? ''},
      deadline,
    );
    return _fromAction(
      command,
      stopwatch,
      result,
      resolution,
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
    );
  }

  Future<CockpitCommandExecution> _travel(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final rawRoute = command.parameters['route'];
    if (rawRoute is! List<Object?>) {
      throw const FormatException('travel requires a route array.');
    }
    final deadline = _deadline(command);
    final intervalMs = command.parameters['intervalMs'] as int? ?? 0;
    for (var index = 0; index < rawRoute.length; index += 1) {
      final rawPoint = rawRoute[index];
      if (rawPoint is! Map<Object?, Object?>) {
        throw const FormatException('travel route points must be objects.');
      }
      final point = Map<String, Object?>.from(rawPoint);
      final result = await _runAction(
        CockpitSystemControlAction.setLocation,
        <String, Object?>{
          'latitude': point['latitude'],
          'longitude': point['longitude'],
        },
        deadline,
      );
      if (!result.success) return _fromAction(command, stopwatch, result, null);
      if (index < rawRoute.length - 1) {
        final delayMs = point['delayMs'] as int? ?? intervalMs;
        if (delayMs > 0) await _delay(_boundedDelay(deadline, delayMs));
      }
    }
    return _success(command, stopwatch);
  }

  Future<CockpitCommandExecution> _pressKey(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final key = _keyName(command.parameters);
    if (key == null) {
      throw const FormatException('Key action requires a supported key name.');
    }
    return _fromAction(
      command,
      stopwatch,
      await _runAction(CockpitSystemControlAction.pressKey, <String, Object?>{
        'key': key,
      }, _deadline(command)),
      null,
    );
  }

  Future<CockpitCommandExecution> _drag(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final locator = _locator(command);
    CockpitLocatorResolution? resolution;
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[];
    Map<String, String> sourcePaths = const <String, String>{};
    int startX;
    int startY;
    int viewportWidth;
    int viewportHeight;
    if (locator != null) {
      final point = await _resolveStablePoint(command, deadline);
      if (point.error != null) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      startX = point.x!;
      startY = point.y!;
      viewportWidth = point.viewportWidth!;
      viewportHeight = point.viewportHeight!;
      resolution = point.resolution;
      artifacts = point.artifacts;
      sourcePaths = point.artifactSourcePaths;
    } else {
      final snapshot = await _readSnapshot(deadline);
      viewportWidth = snapshot.viewportWidth;
      viewportHeight = snapshot.viewportHeight;
      startX = (viewportWidth / 2).round();
      startY = (viewportHeight / 2).round();
    }
    final delta = _gestureDelta(command, viewportWidth, viewportHeight);
    final endX = (startX + delta.$1).round().clamp(0, viewportWidth - 1);
    final endY = (startY + delta.$2).round().clamp(0, viewportHeight - 1);
    final result =
        await _runAction(CockpitSystemControlAction.drag, <String, Object?>{
          'startX': startX,
          'startY': startY,
          'endX': endX,
          'endY': endY,
          'durationMs': command.parameters['durationMs'] is int
              ? command.parameters['durationMs']
              : 300,
        }, deadline);
    return _fromAction(
      command,
      stopwatch,
      result,
      resolution,
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
    );
  }

  Future<CockpitCommandExecution> _scrollUntilVisible(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final locator = _locator(command);
    if (locator == null) {
      throw const FormatException('scrollUntilVisible requires a locator.');
    }
    final deadline = _deadline(command);
    final maxScrolls = command.parameters['maxScrolls'] as int? ?? 10;
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[];
    Map<String, String> sourcePaths = const <String, String>{};
    for (var attempt = 0; attempt <= maxScrolls; attempt += 1) {
      final point = await _resolvePoint(command, deadline);
      artifacts = point.artifacts;
      sourcePaths = point.artifactSourcePaths;
      if (point.error == null) {
        return _success(
          command,
          stopwatch,
          resolution: point.resolution,
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      if (point.error!.code != CockpitCommandError.targetNotFoundCode) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      if (attempt == maxScrolls) break;
      final viewportWidth = point.viewportWidth;
      final viewportHeight = point.viewportHeight;
      if (viewportWidth == null || viewportHeight == null) break;
      final upward = command.parameters['reverse'] == true;
      final x = (viewportWidth * 0.5).round();
      final startY = (viewportHeight * (upward ? 0.3 : 0.75)).round();
      final endY = (viewportHeight * (upward ? 0.75 : 0.3)).round();
      final result =
          await _runAction(CockpitSystemControlAction.drag, <String, Object?>{
            'startX': x,
            'startY': startY,
            'endX': x,
            'endY': endY,
            'durationMs': command.parameters['durationMs'] as int? ?? 350,
          }, deadline);
      if (!result.success) {
        return _fromAction(
          command,
          stopwatch,
          result,
          null,
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      await _delay(_boundedDelay(deadline, 150));
    }
    return _failure(
      command,
      stopwatch,
      CockpitCommandError.targetNotFound(
        message: 'Target was not visible after the bounded scroll search.',
      ),
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
    );
  }

  Future<CockpitCommandExecution> _waitFor(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    if (command.parameters['routeName'] != null) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError.unsupportedCapability(
          message: 'A black-box system driver cannot observe Flutter routes.',
        ),
      );
    }
    final locator = _locator(command);
    if (locator == null) {
      throw const FormatException('waitFor requires a native locator.');
    }
    final absent = command.parameters['absent'] == true;
    final deadline = _deadline(command);
    _ResolvedPoint? lastPoint;
    StateError? lastObservationError;
    do {
      late final _ResolvedPoint point;
      try {
        point = await _resolvePoint(command, deadline);
      } on StateError catch (error) {
        lastObservationError = error;
        await _delay(_boundedDelay(deadline, 150));
        continue;
      }
      lastPoint = point;
      final found = point.error == null;
      if (!found &&
          point.error!.code != CockpitCommandError.targetNotFoundCode) {
        return _failure(
          command,
          stopwatch,
          point.error!,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      if (found != absent) {
        return _success(
          command,
          stopwatch,
          resolution: found ? point.resolution : null,
          artifacts: point.artifacts,
          artifactSourcePaths: point.artifactSourcePaths,
        );
      }
      await _delay(_boundedDelay(deadline, 150));
    } while (_utcNow().isBefore(deadline));
    if (lastPoint == null) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: 'systemDriverFailed',
          message: 'Native UI could not be observed before the deadline.',
          details: <String, Object?>{
            if (lastObservationError != null)
              'lastError': '$lastObservationError',
          },
        ),
      );
    }
    return _failure(
      command,
      stopwatch,
      CockpitCommandError.targetNotFound(
        message: absent
            ? 'Target remained visible until the deadline.'
            : 'Target was not visible before the deadline.',
      ),
      artifacts: lastPoint.artifacts,
      artifactSourcePaths: lastPoint.artifactSourcePaths,
    );
  }

  Future<CockpitCommandExecution> _assertText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final expected = command.parameters['text'];
    if (expected is! String) {
      throw const FormatException('assertText requires a string text value.');
    }
    final snapshot = await _readSnapshot(_deadline(command));
    final locator = _locator(command);
    CockpitNativeUiResolution? resolution;
    Iterable<String> values;
    if (locator == null) {
      values = snapshot.nodes
          .where((node) => node.visible)
          .expand((node) => node.textValues);
    } else {
      resolution = _resolve(snapshot, locator);
      final error = _resolutionError(resolution);
      if (error != null) return _failure(command, stopwatch, error);
      values = resolution.node?.textValues ?? const <String>[];
    }
    final mode = command.parameters['matchMode'] as String? ?? 'exact';
    if (!values.any((actual) => _textMatches(actual, expected, mode))) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError.assertionFailed(
          message: 'Expected text was not present in the native UI tree.',
        ),
      );
    }
    return _success(
      command,
      stopwatch,
      resolution: resolution == null ? null : _locatorResolution(resolution),
    );
  }

  Future<CockpitCommandExecution> _assertScreenshot(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final baseline = command.parameters['baseline'];
    if (baseline is! String || baseline.trim().isEmpty) {
      throw const FormatException(
        'assertScreenshot requires a non-empty baseline path.',
      );
    }
    final pixelTolerance =
        (command.parameters['pixelTolerance'] as num?)?.toDouble() ?? 0.1;
    final maxDifferingPixelRatio =
        (command.parameters['maxDifferingPixelRatio'] as num?)?.toDouble() ??
        0.01;
    final stem = _artifactStem(
      command.parameters['name'] as String? ??
          command.parameters['artifactName'] as String? ??
          command.commandId,
    );
    CockpitNativeUiResolution? cropResolution;
    CockpitVisualCrop? crop;
    final cropLocator = _locator(command);
    if (cropLocator != null) {
      final ui = await _readSnapshot(_deadline(command));
      cropResolution = _resolve(ui, cropLocator);
      final resolutionError = _resolutionError(cropResolution);
      if (resolutionError != null) {
        return _failure(command, stopwatch, resolutionError);
      }
      final bounds = cropResolution.node?.bounds;
      if (bounds == null || !bounds.hasArea) {
        return _failure(
          command,
          stopwatch,
          CockpitCommandError.targetNotHittable(
            message: 'Screenshot crop target does not expose usable bounds.',
          ),
        );
      }
      crop = CockpitVisualCrop(
        left: bounds.left / ui.viewportWidth,
        top: bounds.top / ui.viewportHeight,
        right: bounds.right / ui.viewportWidth,
        bottom: bounds.bottom / ui.viewportHeight,
      );
    }
    final captured = await _captureScreenshot(
      name: '$stem-actual',
      deadline: _deadline(command),
    );
    if (captured.error != null) {
      return _failure(command, stopwatch, captured.error!);
    }
    final comparison = await _visualMatcher.compareScreenshot(
      screenshotPath: captured.sourcePath!,
      baselineReference: baseline,
      pixelTolerance: pixelTolerance,
      maxDifferingPixelRatio: maxDifferingPixelRatio,
      crop: crop,
    );
    final baselinePath =
        'visual/$stem-baseline${p.extension(comparison.baselineSourcePath)}';
    final actualPath = 'visual/$stem-actual.png';
    final diffPath = 'visual/$stem-diff.png';
    final artifacts = <CockpitArtifactRef>[
      CockpitArtifactRef(role: 'screenshotActual', relativePath: actualPath),
      CockpitArtifactRef(
        role: 'screenshotBaseline',
        relativePath: baselinePath,
      ),
      CockpitArtifactRef(role: 'screenshotDiff', relativePath: diffPath),
    ];
    final sourcePaths = <String, String>{
      baselinePath: comparison.baselineSourcePath,
    };
    final payloads = <String, List<int>>{
      actualPath: comparison.actualPng,
      diffPath: comparison.diffPng,
    };
    final snapshot = <String, Object?>{
      'adapter': 'visual',
      'matchingPixelRatio': comparison.matchingPixelRatio,
      'differingPixelRatio': comparison.differingPixelRatio,
      'differingPixelCount': comparison.differingPixelCount,
      'totalPixelCount': comparison.totalPixelCount,
      'pixelTolerance': comparison.pixelTolerance,
      'maxDifferingPixelRatio': comparison.maxDifferingPixelRatio,
      'captureScope': crop == null ? 'screen' : 'element',
      if (crop != null) 'crop': crop.toJson(),
      'actualSize': <String, Object?>{
        'width': comparison.width,
        'height': comparison.height,
      },
      'baselineSize': <String, Object?>{
        'width': comparison.baselineWidth,
        'height': comparison.baselineHeight,
      },
      'dimensionMismatch': comparison.dimensionMismatch,
    };
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: comparison.matched,
        commandId: command.commandId,
        commandType: command.commandType,
        locatorResolution: cropResolution == null
            ? null
            : _locatorResolution(cropResolution),
        durationMs: stopwatch.elapsedMilliseconds,
        artifacts: artifacts,
        snapshot: snapshot,
        error: comparison.matched
            ? null
            : CockpitCommandError.assertionFailed(
                message: comparison.dimensionMismatch
                    ? 'Screenshot dimensions do not match the baseline.'
                    : 'Too many screenshot pixels differ from the baseline.',
                details: snapshot,
              ),
      ),
      artifactSourcePaths: sourcePaths,
      artifactPayloads: payloads,
    );
  }

  Future<CockpitCommandExecution> _captureEvidence(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final captured = await _captureScreenshot(
      name: _artifactStem(
        command.screenshotRequest?.name ??
            command.parameters['name'] as String? ??
            command.parameters['artifactName'] as String? ??
            command.commandId,
      ),
      deadline: _deadline(command),
    );
    if (captured.error case final error?) {
      return _failure(command, stopwatch, error);
    }
    final artifact = captured.artifact!;
    return _success(
      command,
      stopwatch,
      artifacts: <CockpitArtifactRef>[artifact],
      artifactSourcePaths: <String, String>{
        artifact.relativePath: captured.sourcePath!,
      },
    );
  }

  Future<CockpitCommandExecution> _waitForUiIdle(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final quietMs =
        command.parameters['quietWindowMs'] as int? ??
        command.parameters['quietMs'] as int? ??
        500;
    String? previousDigest;
    DateTime? stableSince;
    do {
      final snapshot = await _readSnapshot(deadline);
      final digest = sha256.convert(utf8.encode(snapshot.raw)).toString();
      if (digest == previousDigest) {
        stableSince ??= _utcNow();
        if (_utcNow().difference(stableSince).inMilliseconds >= quietMs) {
          return _success(command, stopwatch);
        }
      } else {
        previousDigest = digest;
        stableSince = null;
      }
      await _delay(_boundedDelay(deadline, 100));
    } while (_utcNow().isBefore(deadline));
    return _failure(
      command,
      stopwatch,
      CockpitCommandError.timeout(
        message: 'Native UI tree did not become stable before the deadline.',
      ),
    );
  }

  Future<CockpitCommandExecution> _collectSnapshot(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final snapshot = await _readSnapshot(_deadline(command));
    final digest = sha256.convert(utf8.encode(snapshot.raw)).toString();
    final path = 'snapshots/native-${digest.substring(0, 16)}.xml';
    final artifact = CockpitArtifactRef(
      role: 'nativeUiTree',
      relativePath: path,
    );
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: stopwatch.elapsedMilliseconds,
        artifacts: <CockpitArtifactRef>[artifact],
        snapshot: <String, Object?>{
          'source': 'nativeAccessibilityTree',
          'adapter': _flutterAwareNative ? 'flutterAwareNative' : 'native',
          'nodeCount': snapshot.nodes.length,
          'viewport': <String, Object?>{
            'width': snapshot.viewportWidth,
            'height': snapshot.viewportHeight,
          },
          'sha256': digest,
        },
      ),
      artifactPayloads: <String, List<int>>{path: utf8.encode(snapshot.raw)},
    );
  }

  Future<CockpitCommandExecution> _simpleAction(
    CockpitCommand command,
    Stopwatch stopwatch,
    CockpitSystemControlAction action,
  ) async => _fromAction(
    command,
    stopwatch,
    await _runAction(action, const <String, Object?>{}, _deadline(command)),
    null,
  );

  Future<_ResolvedPoint> _resolvePoint(
    CockpitCommand command,
    DateTime deadline,
  ) async {
    final locator = _locator(command);
    if (locator == null) {
      return _ResolvedPoint.error(
        CockpitCommandError.targetNotFound(
          message: '${command.commandType.name} requires a target locator.',
        ),
      );
    }
    CockpitNativeUiSnapshot? snapshot;
    _SystemScreenshot? screenshot;
    double? bestVisualSimilarity;
    int? visualViewportWidth;
    int? visualViewportHeight;
    final artifacts = <CockpitArtifactRef>[];
    final sourcePaths = <String, String>{};
    for (final candidate in locator.flattened) {
      if (candidate.strategy == CockpitTestLocatorStrategy.visual) {
        screenshot ??= await _captureScreenshot(
          name: '${_artifactStem(command.commandId)}-locator',
          deadline: deadline,
        );
        if (screenshot.error != null) continue;
        _addArtifact(
          artifacts,
          sourcePaths,
          screenshot.artifact!,
          screenshot.sourcePath!,
        );
        final threshold = candidate.threshold ?? 0.9;
        final match = await _visualMatcher.findTemplate(
          screenshotPath: screenshot.sourcePath!,
          templateReference: candidate.visual!,
          threshold: threshold,
        );
        if (bestVisualSimilarity == null ||
            match.similarity > bestVisualSimilarity) {
          bestVisualSimilarity = match.similarity;
        }
        visualViewportWidth = match.screenshotWidth;
        visualViewportHeight = match.screenshotHeight;
        final templatePath =
            'visual/${sha256.convert(utf8.encode(candidate.visual!)).toString().substring(0, 16)}-template${p.extension(match.templateSourcePath)}';
        _addArtifact(
          artifacts,
          sourcePaths,
          CockpitArtifactRef(
            role: 'visualLocatorTemplate',
            relativePath: templatePath,
          ),
          match.templateSourcePath,
        );
        if (!match.matched) continue;
        return _ResolvedPoint(
          x: match.x + match.width ~/ 2,
          y: match.y + match.height ~/ 2,
          viewportWidth: match.screenshotWidth,
          viewportHeight: match.screenshotHeight,
          resolution: CockpitLocatorResolution(
            matchedKind: CockpitLocatorKind.visual,
            matchedValue: candidate.visual!,
            matchedSignals: <String, String>{
              'adapter': 'visual',
              'similarity': match.similarity.toStringAsFixed(6),
              'threshold': threshold.toStringAsFixed(6),
              'x': '${match.x}',
              'y': '${match.y}',
              'width': '${match.width}',
              'height': '${match.height}',
            },
          ),
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      snapshot ??= await _readSnapshot(deadline);
      final resolution = snapshot.resolveSingle(
        candidate,
        flutterAware: _flutterAwareNative,
      );
      if (resolution.ambiguous) {
        return _ResolvedPoint.error(
          _resolutionError(resolution)!,
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      if (!resolution.found) continue;
      final x = resolution.centerX;
      final y = resolution.centerY;
      if (x == null || y == null) {
        return _ResolvedPoint.error(
          CockpitCommandError.targetNotHittable(
            message: 'Resolved native target does not expose usable bounds.',
          ),
          artifacts: artifacts,
          artifactSourcePaths: sourcePaths,
        );
      }
      return _ResolvedPoint(
        x: x,
        y: y,
        viewportWidth: snapshot.viewportWidth,
        viewportHeight: snapshot.viewportHeight,
        nativePath: resolution.node?.attributes['nativepath'],
        textLength: resolution.node?.textValues
            .map((value) => value.length)
            .maxOrNull,
        resolution: _locatorResolution(resolution),
        artifacts: artifacts,
        artifactSourcePaths: sourcePaths,
      );
    }
    return _ResolvedPoint.error(
      CockpitCommandError.targetNotFound(
        message: 'No locator candidate matched the current application UI.',
        details: <String, Object?>{
          'bestVisualSimilarity': ?bestVisualSimilarity,
        },
      ),
      artifacts: artifacts,
      artifactSourcePaths: sourcePaths,
      viewportWidth: visualViewportWidth ?? snapshot?.viewportWidth,
      viewportHeight: visualViewportHeight ?? snapshot?.viewportHeight,
    );
  }

  Future<_ResolvedPoint> _resolveStablePoint(
    CockpitCommand command,
    DateTime deadline,
  ) async {
    var previous = await _resolvePoint(command, deadline);
    if (previous.error != null || !_requiresStablePoint(previous)) {
      return previous;
    }
    final candidateDeadline = _utcNow().add(const Duration(seconds: 2));
    final stabilityDeadline = deadline.isBefore(candidateDeadline)
        ? deadline
        : candidateDeadline;
    for (var sample = 0; sample < 8; sample += 1) {
      final remaining = stabilityDeadline.difference(_utcNow());
      if (remaining <= Duration.zero) break;
      const interval = Duration(milliseconds: 50);
      await _delay(remaining < interval ? remaining : interval);
      final current = await _resolvePoint(command, deadline);
      if (current.error != null) {
        if (current.error!.code != CockpitCommandError.targetNotFoundCode) {
          return current;
        }
        previous = current;
        continue;
      }
      if (previous.error == null && _sameResolvedPoint(previous, current)) {
        return current;
      }
      previous = current;
    }
    return _ResolvedPoint.error(
      CockpitCommandError.targetNotHittable(
        message: 'Native target bounds did not stabilize before input.',
        details: <String, Object?>{
          if (previous.x != null) 'lastX': previous.x,
          if (previous.y != null) 'lastY': previous.y,
          'stabilityWindowMs': 2000,
        },
      ),
      viewportWidth: previous.viewportWidth,
      viewportHeight: previous.viewportHeight,
      artifacts: previous.artifacts,
      artifactSourcePaths: previous.artifactSourcePaths,
    );
  }

  bool _requiresStablePoint(_ResolvedPoint point) =>
      switch (point.resolution?.matchedKind) {
        CockpitLocatorKind.coordinate ||
        CockpitLocatorKind.visual ||
        null => false,
        _ => true,
      };

  bool _sameResolvedPoint(_ResolvedPoint left, _ResolvedPoint right) {
    final leftX = left.x;
    final leftY = left.y;
    final rightX = right.x;
    final rightY = right.y;
    if (leftX == null || leftY == null || rightX == null || rightY == null) {
      return false;
    }
    return (leftX - rightX).abs() <= 1 &&
        (leftY - rightY).abs() <= 1 &&
        left.nativePath == right.nativePath &&
        left.resolution?.matchedKind == right.resolution?.matchedKind &&
        left.resolution?.matchedValue == right.resolution?.matchedValue;
  }

  Future<CockpitNativeUiResolution> _resolveNativeNode(
    CockpitTestLocator locator,
    DateTime deadline,
  ) async {
    final snapshot = await _readSnapshot(deadline);
    for (final candidate in locator.flattened) {
      if (candidate.strategy == CockpitTestLocatorStrategy.visual ||
          candidate.strategy == CockpitTestLocatorStrategy.coordinate) {
        continue;
      }
      final resolution = snapshot.resolveSingle(
        candidate,
        flutterAware: _flutterAwareNative,
      );
      if (resolution.found || resolution.ambiguous) return resolution;
    }
    return CockpitNativeUiResolution.notFound(
      locator,
      adapter: _flutterAwareNative ? 'flutterAwareNative' : 'native',
    );
  }

  Future<_SystemScreenshot> _captureScreenshot({
    required String name,
    required DateTime deadline,
  }) async {
    final result = await _runAction(
      CockpitSystemControlAction.captureScreenshot,
      <String, Object?>{'name': name},
      deadline,
    );
    final sourcePath = result.sourceFilePath;
    final artifact = result.artifact;
    if (!result.success || sourcePath == null || artifact == null) {
      final details = <String, Object?>{
        if (result.errorCode != null) 'systemErrorCode': result.errorCode,
        if (result.errorDetails.isNotEmpty)
          'systemErrorDetails': result.errorDetails,
      };
      return _SystemScreenshot.error(
        result.availability == CockpitSystemControlAvailability.blocked
            ? CockpitCommandError.unsupportedCapability(
                message: result.errorMessage ?? 'System screenshot is blocked.',
                details: details,
              )
            : CockpitCommandError.captureFailed(
                message:
                    result.errorMessage ?? 'System screenshot capture failed.',
                details: details,
              ),
      );
    }
    return _SystemScreenshot(
      sourcePath: sourcePath,
      artifact: CockpitArtifactRef.fromJson(artifact),
    );
  }

  CockpitTestLocator? _locator(CockpitCommand command) {
    final value = command.parameters['cockpitTestLocator'];
    return value == null
        ? null
        : CockpitTestLocator.fromJson(value, path: r'$.cockpitTestLocator');
  }

  CockpitNativeUiResolution _resolve(
    CockpitNativeUiSnapshot snapshot,
    CockpitTestLocator locator,
  ) => snapshot.resolve(locator, flutterAware: _flutterAwareNative);

  Future<CockpitNativeUiSnapshot> _readSnapshot(DateTime deadline) async {
    final result = await _runAction(
      CockpitSystemControlAction.readUiTree,
      const <String, Object?>{},
      deadline,
    );
    if (!result.success) {
      if (result.availability != CockpitSystemControlAvailability.available) {
        throw _SystemObservationException(_actionError(result));
      }
      throw StateError(
        result.errorMessage ?? 'Native UI tree could not be read.',
      );
    }
    if (result.stdout == null || result.stdout!.trim().isEmpty) {
      throw _SystemObservationException(
        CockpitCommandError(
          code: 'systemDriverFailed',
          message: 'Native UI tree read completed without a tree.',
          details: <String, Object?>{
            if (result.strategy != null) 'strategy': result.strategy,
          },
        ),
      );
    }
    return CockpitNativeUiSnapshot.parse(result.stdout!);
  }

  Future<CockpitSystemControlActionResult> _runAction(
    CockpitSystemControlAction action,
    Map<String, Object?> parameters,
    DateTime deadline,
  ) {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) throw TimeoutException('deadline elapsed');
    return _actionService.run(
      CockpitSystemControlActionRequest(
        platform: _target.platform,
        deviceId: _target.deviceId,
        appId: _target.appId,
        processId: _target.processId,
        metadata: _target.metadata,
        action: action,
        parameters: parameters,
        timeout: remaining,
      ),
    );
  }

  CockpitCommandExecution _fromAction(
    CockpitCommand command,
    Stopwatch stopwatch,
    CockpitSystemControlActionResult action,
    CockpitLocatorResolution? resolution, {
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, String> artifactSourcePaths = const <String, String>{},
  }) => action.success
      ? _success(
          command,
          stopwatch,
          resolution: resolution,
          artifacts: artifacts,
          artifactSourcePaths: artifactSourcePaths,
        )
      : _failure(
          command,
          stopwatch,
          _actionError(action),
          artifacts: artifacts,
          artifactSourcePaths: artifactSourcePaths,
        );

  CockpitCommandError _actionError(CockpitSystemControlActionResult action) =>
      CockpitCommandError(
        code: action.availability == CockpitSystemControlAvailability.available
            ? 'systemActionFailed'
            : CockpitCommandError.unsupportedCapabilityCode,
        message:
            action.errorMessage ??
            'System action ${action.action.name} failed.',
        details: <String, Object?>{
          if (action.errorCode != null) 'systemErrorCode': action.errorCode,
          if (action.strategy != null) 'strategy': action.strategy,
          if (action.requires.isNotEmpty) 'requires': action.requires,
          if (action.limitations.isNotEmpty) 'limitations': action.limitations,
        },
      );

  CockpitCommandExecution _success(
    CockpitCommand command,
    Stopwatch stopwatch, {
    CockpitLocatorResolution? resolution,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, String> artifactSourcePaths = const <String, String>{},
  }) => CockpitCommandExecution(
    result: CockpitCommandResult(
      success: true,
      commandId: command.commandId,
      commandType: command.commandType,
      locatorResolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
      artifacts: artifacts,
    ),
    artifactSourcePaths: artifactSourcePaths,
  );

  CockpitCommandExecution _failure(
    CockpitCommand command,
    Stopwatch stopwatch,
    CockpitCommandError error, {
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, String> artifactSourcePaths = const <String, String>{},
  }) => CockpitCommandExecution(
    result: CockpitCommandResult(
      success: false,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: stopwatch.elapsedMilliseconds,
      artifacts: artifacts,
      error: error,
    ),
    artifactSourcePaths: artifactSourcePaths,
  );

  DateTime _deadline(CockpitCommand command) => _utcNow().add(
    Duration(milliseconds: command.timeoutMs?.clamp(1, 120000) ?? 15000),
  );

  Duration _boundedDelay(DateTime deadline, int milliseconds) {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) throw TimeoutException('deadline elapsed');
    final requested = Duration(milliseconds: milliseconds);
    return remaining < requested ? remaining : requested;
  }
}

final class _ResolvedPoint {
  _ResolvedPoint({
    required this.x,
    required this.y,
    required this.viewportWidth,
    required this.viewportHeight,
    this.nativePath,
    this.textLength,
    required this.resolution,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, String> artifactSourcePaths = const <String, String>{},
  }) : artifacts = List<CockpitArtifactRef>.unmodifiable(artifacts),
       artifactSourcePaths = Map<String, String>.unmodifiable(
         artifactSourcePaths,
       ),
       error = null;

  _ResolvedPoint.error(
    this.error, {
    this.viewportWidth,
    this.viewportHeight,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, String> artifactSourcePaths = const <String, String>{},
  }) : artifacts = List<CockpitArtifactRef>.unmodifiable(artifacts),
       artifactSourcePaths = Map<String, String>.unmodifiable(
         artifactSourcePaths,
       ),
       x = null,
       y = null,
       nativePath = null,
       textLength = null,
       resolution = null;

  final int? x;
  final int? y;
  final int? viewportWidth;
  final int? viewportHeight;
  final String? nativePath;
  final int? textLength;
  final CockpitLocatorResolution? resolution;
  final List<CockpitArtifactRef> artifacts;
  final Map<String, String> artifactSourcePaths;
  final CockpitCommandError? error;
}

final class _SystemScreenshot {
  const _SystemScreenshot({required this.sourcePath, required this.artifact})
    : error = null;

  const _SystemScreenshot.error(this.error)
    : sourcePath = null,
      artifact = null;

  final String? sourcePath;
  final CockpitArtifactRef? artifact;
  final CockpitCommandError? error;
}

final class _SystemObservationException implements Exception {
  const _SystemObservationException(this.error);

  final CockpitCommandError error;
}

String _artifactStem(String value) {
  final normalized = p
      .basenameWithoutExtension(value)
      .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (normalized.isNotEmpty) return normalized;
  return sha256.convert(utf8.encode(value)).toString().substring(0, 16);
}

void _addArtifact(
  List<CockpitArtifactRef> artifacts,
  Map<String, String> sourcePaths,
  CockpitArtifactRef artifact,
  String sourcePath,
) {
  if (!sourcePaths.containsKey(artifact.relativePath)) {
    artifacts.add(artifact);
    sourcePaths[artifact.relativePath] = sourcePath;
  }
}

CockpitCommandError? _resolutionError(CockpitNativeUiResolution resolution) {
  if (resolution.found) return null;
  if (resolution.ambiguous) {
    return CockpitCommandError.ambiguousTarget(
      message: 'Native locator matched ${resolution.matchCount} targets.',
      details: <String, Object?>{
        'adapter': resolution.adapter,
        'matchCount': resolution.matchCount,
      },
    );
  }
  return CockpitCommandError.targetNotFound(
    message:
        'Native locator ${resolution.locator.strategy.name} did not match.',
  );
}

CockpitLocatorResolution _locatorResolution(
  CockpitNativeUiResolution resolution,
) {
  final kind = switch (resolution.locator.strategy) {
    CockpitTestLocatorStrategy.text => CockpitLocatorKind.text,
    CockpitTestLocatorStrategy.label => CockpitLocatorKind.tooltip,
    CockpitTestLocatorStrategy.nativeId => CockpitLocatorKind.nativeId,
    CockpitTestLocatorStrategy.testId => CockpitLocatorKind.testId,
    CockpitTestLocatorStrategy.role => CockpitLocatorKind.role,
    CockpitTestLocatorStrategy.type => CockpitLocatorKind.type,
    CockpitTestLocatorStrategy.path => CockpitLocatorKind.path,
    CockpitTestLocatorStrategy.coordinate => CockpitLocatorKind.coordinate,
    CockpitTestLocatorStrategy.visual => CockpitLocatorKind.visual,
  };
  final value =
      resolution.locator.value ??
      '${resolution.locator.x},${resolution.locator.y}';
  final matchedSignals = <String, String>{
    'adapter': resolution.adapter,
    ...resolution.locator.signalMap,
    if (resolution.locator.matchMode != CockpitTextMatchMode.exact)
      'matchMode': resolution.locator.matchMode.name,
    for (final state in resolution.locator.stateMap.entries)
      state.key: state.value.toString(),
    for (final relation in <String, CockpitTestLocator?>{
      'ancestor': resolution.locator.ancestor,
      'child': resolution.locator.child,
      'descendant': resolution.locator.descendant,
      'above': resolution.locator.above,
      'below': resolution.locator.below,
      'leftOf': resolution.locator.leftOf,
      'rightOf': resolution.locator.rightOf,
    }.entries)
      if (relation.value != null)
        relation.key: jsonEncode(relation.value!.toJson()),
  };
  return CockpitLocatorResolution(
    matchedKind: kind,
    matchedValue: value,
    matchedSignals: matchedSignals,
  );
}

(double, double) _gestureDelta(
  CockpitCommand command,
  int viewportWidth,
  int viewportHeight,
) {
  if (command.commandType == CockpitCommandType.swipe) {
    final distance =
        (command.parameters['distanceFactor'] as num?)?.toDouble() ?? 0.5;
    final direction = command.parameters['direction'] as String? ?? 'up';
    return switch (direction) {
      'up' => (0, -viewportHeight * distance),
      'down' => (0, viewportHeight * distance),
      'left' => (-viewportWidth * distance, 0),
      'right' => (viewportWidth * distance, 0),
      _ => throw const FormatException('Unsupported swipe direction.'),
    };
  }
  final dx = (command.parameters['dx'] as num?)?.toDouble();
  final dy = (command.parameters['dy'] as num?)?.toDouble();
  if (dx == null || dy == null) {
    throw const FormatException('Drag requires numeric dx and dy values.');
  }
  return (dx, dy);
}

String? _keyName(Map<String, Object?> parameters) {
  final inputAction = parameters['inputAction'];
  if (inputAction is String) {
    return switch (inputAction.toLowerCase()) {
      'done' || 'go' || 'search' || 'send' || 'next' || 'newline' => 'enter',
      'previous' => 'tab',
      _ => null,
    };
  }
  for (final key in const <String>[
    'key',
    'keyLabel',
    'logicalKey',
    'logicalKeyLabel',
    'character',
  ]) {
    final value = parameters[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

bool _textMatches(String actual, String expected, String mode) =>
    switch (mode) {
      'exact' => actual == expected,
      'contains' => actual.contains(expected),
      'prefix' => actual.startsWith(expected),
      'suffix' => actual.endsWith(expected),
      'regex' => RegExp(expected).hasMatch(actual),
      _ => throw const FormatException('Unsupported text match mode.'),
    };
