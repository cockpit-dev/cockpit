import 'dart:async';
import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';

import '../adapters/cockpit_automation_adapter.dart';
import 'cockpit_native_ui_snapshot.dart';
import 'cockpit_system_control_action_service.dart';
import 'cockpit_system_control_service.dart';
import 'cockpit_system_test_target.dart';

final class CockpitSystemTestAutomationAdapter
    implements CockpitAutomationAdapter {
  CockpitSystemTestAutomationAdapter({
    required CockpitSystemTestTarget target,
    required CockpitSystemControlService controlService,
    required CockpitSystemControlActionService actionService,
    DateTime Function()? utcNow,
    Future<void> Function(Duration)? delay,
  }) : _target = target,
       _controlService = controlService,
       _actionService = actionService,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _delay = delay ?? Future<void>.delayed;

  final CockpitSystemTestTarget _target;
  final CockpitSystemControlService _controlService;
  final CockpitSystemControlActionService _actionService;
  final DateTime Function() _utcNow;
  final Future<void> Function(Duration) _delay;

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
      ],
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
      if (available.contains(CockpitSystemControlAction.captureScreenshot))
        CockpitCommandType.captureScreenshot,
    };
    return CockpitCapabilities(
      platform: describe.profile.platform,
      transportType: 'system-control',
      supportsInAppControl: false,
      supportsFlutterViewCapture: false,
      supportsNativeScreenCapture: available.contains(
        CockpitSystemControlAction.captureScreenshot,
      ),
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
        if (hasTree &&
            (available.contains(CockpitSystemControlAction.tap) ||
                available.contains(CockpitSystemControlAction.drag)))
          CockpitLocatorKind.coordinate,
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
    final point = await _resolvePoint(command, deadline);
    if (point.error != null) return _failure(command, stopwatch, point.error!);
    final result = await _runAction(
      CockpitSystemControlAction.tap,
      <String, Object?>{'x': point.x, 'y': point.y},
      deadline,
    );
    return _fromAction(command, stopwatch, result, point.resolution);
  }

  Future<CockpitCommandExecution> _longPress(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final point = await _resolvePoint(command, deadline);
    if (point.error != null) return _failure(command, stopwatch, point.error!);
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
    return _fromAction(command, stopwatch, result, point.resolution);
  }

  Future<CockpitCommandExecution> _doubleTap(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final point = await _resolvePoint(command, deadline);
    if (point.error != null) return _failure(command, stopwatch, point.error!);
    for (var index = 0; index < 2; index += 1) {
      final result = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!result.success) {
        return _fromAction(command, stopwatch, result, point.resolution);
      }
      if (index == 0) await _delay(_boundedDelay(deadline, 80));
    }
    return _success(command, stopwatch, resolution: point.resolution);
  }

  Future<CockpitCommandExecution> _enterText(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final locator = _locator(command);
    CockpitLocatorResolution? resolution;
    if (locator != null) {
      final point = await _resolvePoint(command, deadline);
      if (point.error != null) {
        return _failure(command, stopwatch, point.error!);
      }
      final focus = await _runAction(
        CockpitSystemControlAction.tap,
        <String, Object?>{'x': point.x, 'y': point.y},
        deadline,
      );
      if (!focus.success) {
        return _fromAction(command, stopwatch, focus, point.resolution);
      }
      resolution = point.resolution;
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
    return _fromAction(command, stopwatch, result, resolution);
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
    final snapshot = await _readSnapshot(deadline);
    final locator = _locator(command);
    CockpitNativeUiResolution? target;
    if (locator != null) {
      target = snapshot.resolve(locator);
      final error = _resolutionError(target);
      if (error != null) return _failure(command, stopwatch, error);
    }
    final startX = target?.centerX ?? (snapshot.viewportWidth / 2).round();
    final startY = target?.centerY ?? (snapshot.viewportHeight / 2).round();
    final delta = _gestureDelta(command, snapshot);
    final endX = (startX + delta.$1).round().clamp(
      0,
      snapshot.viewportWidth - 1,
    );
    final endY = (startY + delta.$2).round().clamp(
      0,
      snapshot.viewportHeight - 1,
    );
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
      target == null ? null : _locatorResolution(target),
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
    for (var attempt = 0; attempt <= maxScrolls; attempt += 1) {
      final snapshot = await _readSnapshot(deadline);
      final resolution = snapshot.resolve(locator);
      if (resolution.found) {
        return _success(
          command,
          stopwatch,
          resolution: _locatorResolution(resolution),
        );
      }
      if (resolution.ambiguous) {
        return _failure(command, stopwatch, _resolutionError(resolution)!);
      }
      if (attempt == maxScrolls) break;
      final upward = command.parameters['reverse'] == true;
      final x = (snapshot.viewportWidth * 0.5).round();
      final startY = (snapshot.viewportHeight * (upward ? 0.3 : 0.75)).round();
      final endY = (snapshot.viewportHeight * (upward ? 0.75 : 0.3)).round();
      final result =
          await _runAction(CockpitSystemControlAction.drag, <String, Object?>{
            'startX': x,
            'startY': startY,
            'endX': x,
            'endY': endY,
            'durationMs': command.parameters['durationMs'] as int? ?? 350,
          }, deadline);
      if (!result.success) return _fromAction(command, stopwatch, result, null);
      await _delay(_boundedDelay(deadline, 150));
    }
    return _failure(
      command,
      stopwatch,
      CockpitCommandError.targetNotFound(
        message: 'Target was not visible after the bounded scroll search.',
      ),
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
    StateError? lastReadError;
    do {
      CockpitNativeUiSnapshot snapshot;
      try {
        snapshot = await _readSnapshot(deadline);
        lastReadError = null;
      } on StateError catch (error) {
        lastReadError = error;
        await _delay(_boundedDelay(deadline, 150));
        continue;
      }
      final resolution = snapshot.resolve(locator);
      if (resolution.ambiguous) {
        return _failure(command, stopwatch, _resolutionError(resolution)!);
      }
      if (resolution.found != absent) {
        return _success(
          command,
          stopwatch,
          resolution: resolution.found ? _locatorResolution(resolution) : null,
        );
      }
      await _delay(_boundedDelay(deadline, 150));
    } while (_utcNow().isBefore(deadline));
    if (lastReadError != null) throw lastReadError;
    return _failure(
      command,
      stopwatch,
      CockpitCommandError.targetNotFound(
        message: absent
            ? 'Target remained visible until the deadline.'
            : 'Target was not visible before the deadline.',
      ),
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
      resolution = snapshot.resolve(locator);
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

  Future<CockpitCommandExecution> _waitForUiIdle(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) async {
    final deadline = _deadline(command);
    final quietMs = command.parameters['quietMs'] as int? ?? 500;
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
    final resolution = (await _readSnapshot(deadline)).resolve(locator);
    final error = _resolutionError(resolution);
    if (error != null) return _ResolvedPoint.error(error);
    final x = resolution.centerX;
    final y = resolution.centerY;
    if (x == null || y == null) {
      return _ResolvedPoint.error(
        CockpitCommandError.targetNotHittable(
          message: 'Resolved native target does not expose usable bounds.',
        ),
      );
    }
    return _ResolvedPoint(
      x: x,
      y: y,
      resolution: _locatorResolution(resolution),
    );
  }

  CockpitTestLocator? _locator(CockpitCommand command) {
    final value = command.parameters['cockpitTestLocator'];
    return value == null
        ? null
        : CockpitTestLocator.fromJson(value, path: r'$.cockpitTestLocator');
  }

  Future<CockpitNativeUiSnapshot> _readSnapshot(DateTime deadline) async {
    final result = await _runAction(
      CockpitSystemControlAction.readUiTree,
      const <String, Object?>{},
      deadline,
    );
    if (!result.success ||
        result.stdout == null ||
        result.stdout!.trim().isEmpty) {
      throw StateError(
        result.errorMessage ?? 'Native UI tree could not be read.',
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
    CockpitLocatorResolution? resolution,
  ) => action.success
      ? _success(command, stopwatch, resolution: resolution)
      : _failure(
          command,
          stopwatch,
          CockpitCommandError(
            code:
                action.availability ==
                    CockpitSystemControlAvailability.available
                ? 'systemActionFailed'
                : CockpitCommandError.unsupportedCapabilityCode,
            message:
                action.errorMessage ??
                'System action ${action.action.name} failed.',
            details: <String, Object?>{
              if (action.errorCode != null) 'systemErrorCode': action.errorCode,
              if (action.strategy != null) 'strategy': action.strategy,
              if (action.requires.isNotEmpty) 'requires': action.requires,
              if (action.limitations.isNotEmpty)
                'limitations': action.limitations,
            },
          ),
        );

  CockpitCommandExecution _success(
    CockpitCommand command,
    Stopwatch stopwatch, {
    CockpitLocatorResolution? resolution,
  }) => CockpitCommandExecution(
    result: CockpitCommandResult(
      success: true,
      commandId: command.commandId,
      commandType: command.commandType,
      locatorResolution: resolution,
      durationMs: stopwatch.elapsedMilliseconds,
    ),
  );

  CockpitCommandExecution _failure(
    CockpitCommand command,
    Stopwatch stopwatch,
    CockpitCommandError error,
  ) => CockpitCommandExecution(
    result: CockpitCommandResult(
      success: false,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: stopwatch.elapsedMilliseconds,
      error: error,
    ),
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
  const _ResolvedPoint({
    required this.x,
    required this.y,
    required this.resolution,
  }) : error = null;

  const _ResolvedPoint.error(this.error)
    : x = null,
      y = null,
      resolution = null;

  final int? x;
  final int? y;
  final CockpitLocatorResolution? resolution;
  final CockpitCommandError? error;
}

CockpitCommandError? _resolutionError(CockpitNativeUiResolution resolution) {
  if (resolution.found) return null;
  if (resolution.ambiguous) {
    return CockpitCommandError.ambiguousTarget(
      message: 'Native locator matched ${resolution.matchCount} targets.',
      details: <String, Object?>{'matchCount': resolution.matchCount},
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
  return CockpitLocatorResolution(
    matchedKind: kind,
    matchedValue: value,
    matchedSignals: <String, String>{kind.name: value},
  );
}

(double, double) _gestureDelta(
  CockpitCommand command,
  CockpitNativeUiSnapshot snapshot,
) {
  if (command.commandType == CockpitCommandType.swipe) {
    final distance =
        (command.parameters['distanceFactor'] as num?)?.toDouble() ?? 0.5;
    final direction = command.parameters['direction'] as String? ?? 'up';
    return switch (direction) {
      'up' => (0, -snapshot.viewportHeight * distance),
      'down' => (0, snapshot.viewportHeight * distance),
      'left' => (-snapshot.viewportWidth * distance, 0),
      'right' => (snapshot.viewportWidth * distance, 0),
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
