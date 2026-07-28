import 'dart:math' as math;

import 'package:cockpit_protocol/cockpit_protocol.dart';

final class CockpitTestLoweredAction {
  const CockpitTestLoweredAction({
    required this.command,
    required this.requestedPlane,
    required this.actualPlane,
  });

  final CockpitCommand command;
  final CockpitTestPlane requestedPlane;
  final CockpitTestPlane actualPlane;
}

enum CockpitTestActionBackend { flutter, system }

final class CockpitTestLoweringResult {
  const CockpitTestLoweringResult.success(this.value) : error = null;

  const CockpitTestLoweringResult.failure(this.error) : value = null;

  final CockpitTestLoweredAction? value;
  final CockpitTestError? error;

  bool get isSuccess => value != null;
}

final class CockpitTestActionLowerer {
  const CockpitTestActionLowerer() : backend = CockpitTestActionBackend.flutter;

  const CockpitTestActionLowerer.system()
    : backend = CockpitTestActionBackend.system;

  final CockpitTestActionBackend backend;

  CockpitTestLoweringResult lower({
    required CockpitTestAction action,
    required String commandId,
    required int timeoutMs,
    required CockpitTestPlane requestedPlane,
    required CockpitCapabilities capabilities,
  }) {
    if (backend == CockpitTestActionBackend.flutter &&
        requestedPlane != CockpitTestPlane.semantic) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'The Flutter backend executes only the semantic plane; requested '
        '${requestedPlane.name}.',
      );
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.system) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'System actions require a non-Flutter target backend.',
      );
    }
    final locatorResult = backend == CockpitTestActionBackend.flutter
        ? _lowerFlutterLocator(action.locator, capabilities)
        : _lowerSystemLocator(action.locator, capabilities);
    if (locatorResult.error != null) {
      return CockpitTestLoweringResult.failure(locatorResult.error!);
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.assertText &&
        action.value<String>(CockpitTestActionField.matchMode) != null &&
        action.value<String>(CockpitTestActionField.matchMode) != 'exact') {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'The Flutter backend currently supports exact assertText matching.',
      );
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.setTextEditingValue &&
        (action.values.containsKey(CockpitTestActionField.composingStart) ||
            action.values.containsKey(CockpitTestActionField.composingEnd))) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'The Flutter backend does not support composing ranges.',
      );
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.scrollUntilVisible) {
      final direction = action.value<String>(CockpitTestActionField.direction);
      if (direction == 'left' || direction == 'right') {
        return _failure(
          CockpitTestErrorCode.unsupportedAction,
          'The Flutter backend currently supports vertical scrolling only.',
        );
      }
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.swipe) {
      final distance = action
          .value<num>(CockpitTestActionField.distance)!
          .toDouble();
      if (distance < 0.15 || distance > 0.95) {
        return _failure(
          CockpitTestErrorCode.unsupportedAction,
          'The Flutter backend supports swipe distance from 0.15 through '
          '0.95 without parameter coercion.',
        );
      }
    }
    if (backend == CockpitTestActionBackend.flutter &&
        action.kind == CockpitTestActionKind.fling) {
      final dx = action.value<num>(CockpitTestActionField.dx)!.toDouble();
      final dy = action.value<num>(CockpitTestActionField.dy)!.toDouble();
      final velocity = action
          .value<num>(CockpitTestActionField.velocity)!
          .toDouble();
      if ((math.sqrt(dx * dx + dy * dy) / velocity * 1000).round() <= 0) {
        return _failure(
          CockpitTestErrorCode.unsupportedAction,
          'The Flutter backend cannot represent this fling velocity.',
        );
      }
    }
    if (action.kind == CockpitTestActionKind.waitFor) {
      return lowerCondition(
        condition: action.condition!,
        commandId: commandId,
        timeoutMs: timeoutMs,
        requestedPlane: requestedPlane,
        capabilities: capabilities,
      );
    }
    final commandType = _commandType(action);
    if (!capabilities.supportedCommands.contains(commandType)) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'Target does not support ${action.kind.name}.',
      );
    }
    final parameters = <String, Object?>{
      ..._parameters(action),
      if (backend == CockpitTestActionBackend.system &&
          action.value<String>(CockpitTestActionField.matchMode) != null)
        'matchMode': action.value<String>(CockpitTestActionField.matchMode),
      if (backend == CockpitTestActionBackend.system && action.locator != null)
        'cockpitTestLocator': action.locator!.toJson(),
    };
    final command = CockpitCommand(
      commandId: commandId,
      commandType: commandType,
      locator: locatorResult.locator,
      parameters: parameters,
      capturePolicy: CockpitCapturePolicy.none,
      timeoutMs: timeoutMs,
      snapshotOptions: _snapshotOptions(action),
      screenshotRequest: _screenshotRequest(action, locatorResult.locator),
    );
    return CockpitTestLoweringResult.success(
      CockpitTestLoweredAction(
        command: command,
        requestedPlane: requestedPlane,
        actualPlane: backend == CockpitTestActionBackend.flutter
            ? CockpitTestPlane.semantic
            : requestedPlane,
      ),
    );
  }

  CockpitTestLoweringResult lowerCondition({
    required CockpitTestCondition condition,
    required String commandId,
    required int timeoutMs,
    required CockpitTestPlane requestedPlane,
    required CockpitCapabilities capabilities,
  }) {
    if (backend == CockpitTestActionBackend.flutter &&
        requestedPlane != CockpitTestPlane.semantic) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'Condition cannot execute on ${requestedPlane.name} in Flutter.',
      );
    }
    final locatorResult = backend == CockpitTestActionBackend.flutter
        ? _lowerFlutterLocator(condition.locator, capabilities)
        : _lowerSystemLocator(condition.locator, capabilities);
    if (locatorResult.error != null) {
      return CockpitTestLoweringResult.failure(locatorResult.error!);
    }
    if (backend == CockpitTestActionBackend.flutter &&
        condition.kind == CockpitTestConditionKind.text &&
        condition.matchMode != null &&
        condition.matchMode != CockpitTextMatchMode.exact) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'The Flutter backend currently supports exact text conditions.',
      );
    }
    final commandType = switch (condition.kind) {
      CockpitTestConditionKind.visible ||
      CockpitTestConditionKind.route => CockpitCommandType.waitFor,
      CockpitTestConditionKind.text => CockpitCommandType.assertText,
      CockpitTestConditionKind.uiIdle => CockpitCommandType.waitForUiIdle,
      CockpitTestConditionKind.networkIdle =>
        CockpitCommandType.waitForNetworkIdle,
    };
    if (!capabilities.supportedCommands.contains(commandType)) {
      return _failure(
        CockpitTestErrorCode.unsupportedAction,
        'Target does not support ${condition.kind.name} conditions.',
      );
    }
    return CockpitTestLoweringResult.success(
      CockpitTestLoweredAction(
        command: CockpitCommand(
          commandId: commandId,
          commandType: commandType,
          locator: locatorResult.locator,
          parameters: <String, Object?>{
            ..._conditionParameters(condition),
            if (backend == CockpitTestActionBackend.system &&
                condition.matchMode != null)
              'matchMode': condition.matchMode!.name,
            if (backend == CockpitTestActionBackend.system &&
                condition.locator != null)
              'cockpitTestLocator': condition.locator!.toJson(),
          },
          capturePolicy: CockpitCapturePolicy.none,
          timeoutMs: timeoutMs,
        ),
        requestedPlane: requestedPlane,
        actualPlane: backend == CockpitTestActionBackend.flutter
            ? CockpitTestPlane.semantic
            : requestedPlane,
      ),
    );
  }

  CockpitTestLoweringResult _failure(
    CockpitTestErrorCode code,
    String message,
  ) => CockpitTestLoweringResult.failure(
    CockpitTestError(code: code, message: message),
  );
}

final class _LocatorLoweringResult {
  const _LocatorLoweringResult.success(this.locator) : error = null;
  const _LocatorLoweringResult.failure(this.error) : locator = null;

  final CockpitLocator? locator;
  final CockpitTestError? error;
}

_LocatorLoweringResult _lowerFlutterLocator(
  CockpitTestLocator? locator,
  CockpitCapabilities capabilities,
) {
  if (locator == null) {
    return const _LocatorLoweringResult.success(null);
  }
  if (locator.degraded || locator.hasNativeOnlyConstraints) {
    return _LocatorLoweringResult.failure(
      CockpitTestError(
        code: CockpitTestErrorCode.unsupportedLocator,
        message:
            'The Flutter backend cannot faithfully lower coordinate, visual, '
            'state, child, descendant, or spatial locator constraints.',
      ),
    );
  }
  for (final signal in locator.signals) {
    final kind = switch (signal.strategy) {
      CockpitTestLocatorStrategy.text => CockpitLocatorKind.text,
      CockpitTestLocatorStrategy.label => CockpitLocatorKind.tooltip,
      CockpitTestLocatorStrategy.testId => CockpitLocatorKind.key,
      CockpitTestLocatorStrategy.type => CockpitLocatorKind.type,
      CockpitTestLocatorStrategy.path => CockpitLocatorKind.path,
      CockpitTestLocatorStrategy.nativeId ||
      CockpitTestLocatorStrategy.role ||
      CockpitTestLocatorStrategy.coordinate ||
      CockpitTestLocatorStrategy.visual => null,
    };
    if (kind == null) {
      return _LocatorLoweringResult.failure(
        CockpitTestError(
          code: CockpitTestErrorCode.unsupportedLocator,
          message:
              'The Flutter backend cannot faithfully lower locator signal '
              '${signal.strategy.name}.',
        ),
      );
    }
    if (!capabilities.supportedLocatorStrategies.contains(kind)) {
      return _LocatorLoweringResult.failure(
        CockpitTestError(
          code: CockpitTestErrorCode.unsupportedLocator,
          message: 'Target does not support locator strategy ${kind.name}.',
        ),
      );
    }
  }
  CockpitLocator? ancestor;
  if (locator.ancestor != null) {
    final lowered = _lowerFlutterLocator(locator.ancestor, capabilities);
    if (lowered.error != null) {
      return lowered;
    }
    ancestor = lowered.locator;
  }
  final fallbacks = <CockpitLocator>[];
  for (final fallback in locator.fallbacks) {
    final lowered = _lowerFlutterLocator(fallback, capabilities);
    if (lowered.error != null) {
      return lowered;
    }
    fallbacks.add(lowered.locator!);
  }
  return _LocatorLoweringResult.success(
    CockpitLocator(
      key: locator.testId,
      text: locator.text,
      tooltip: locator.label,
      matchMode: locator.matchMode,
      type: locator.type,
      path: locator.path,
      index: locator.index,
      ancestor: ancestor,
      fallbacks: fallbacks,
    ),
  );
}

_LocatorLoweringResult _lowerSystemLocator(
  CockpitTestLocator? locator,
  CockpitCapabilities capabilities,
) {
  if (locator == null) {
    return const _LocatorLoweringResult.success(null);
  }
  for (final candidate in locator.tree) {
    final strategies = <CockpitTestLocatorStrategy>[
      ...candidate.signals.map((signal) => signal.strategy),
      if (candidate.x != null || candidate.y != null)
        CockpitTestLocatorStrategy.coordinate,
      if (candidate.visual != null) CockpitTestLocatorStrategy.visual,
    ];
    for (final strategy in strategies) {
      final kind = switch (strategy) {
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
      if (!capabilities.supportedLocatorStrategies.contains(kind)) {
        return _LocatorLoweringResult.failure(
          CockpitTestError(
            code: CockpitTestErrorCode.unsupportedLocator,
            message:
                'System target does not support locator strategy '
                '${strategy.name}.',
          ),
        );
      }
    }
  }
  return const _LocatorLoweringResult.success(null);
}

CockpitCommandType _commandType(
  CockpitTestAction action,
) => switch (action.kind) {
  CockpitTestActionKind.tap => CockpitCommandType.tap,
  CockpitTestActionKind.longPress => CockpitCommandType.longPress,
  CockpitTestActionKind.doubleTap => CockpitCommandType.doubleTap,
  CockpitTestActionKind.enterText => CockpitCommandType.enterText,
  CockpitTestActionKind.eraseText => CockpitCommandType.eraseText,
  CockpitTestActionKind.copyText => CockpitCommandType.copyText,
  CockpitTestActionKind.pasteText => CockpitCommandType.pasteText,
  CockpitTestActionKind.focusTextInput => CockpitCommandType.focusTextInput,
  CockpitTestActionKind.setTextEditingValue =>
    CockpitCommandType.setTextEditingValue,
  CockpitTestActionKind.sendTextInputAction =>
    CockpitCommandType.sendTextInputAction,
  CockpitTestActionKind.sendKeyEvent => CockpitCommandType.sendKeyEvent,
  CockpitTestActionKind.sendKeyDownEvent => CockpitCommandType.sendKeyDownEvent,
  CockpitTestActionKind.sendKeyUpEvent => CockpitCommandType.sendKeyUpEvent,
  CockpitTestActionKind.drag => CockpitCommandType.drag,
  CockpitTestActionKind.fling => CockpitCommandType.fling,
  CockpitTestActionKind.swipe => CockpitCommandType.swipe,
  CockpitTestActionKind.pinchZoom => CockpitCommandType.pinchZoom,
  CockpitTestActionKind.rotate => CockpitCommandType.rotate,
  CockpitTestActionKind.panZoom => CockpitCommandType.panZoom,
  CockpitTestActionKind.multiTouch => CockpitCommandType.multiTouch,
  CockpitTestActionKind.scrollUntilVisible =>
    CockpitCommandType.scrollUntilVisible,
  CockpitTestActionKind.back => CockpitCommandType.back,
  CockpitTestActionKind.showOnScreen => CockpitCommandType.showOnScreen,
  CockpitTestActionKind.increase => CockpitCommandType.increase,
  CockpitTestActionKind.decrease => CockpitCommandType.decrease,
  CockpitTestActionKind.dismiss => CockpitCommandType.dismiss,
  CockpitTestActionKind.dismissKeyboard => CockpitCommandType.dismissKeyboard,
  CockpitTestActionKind.clearNetworkActivity =>
    CockpitCommandType.clearNetworkActivity,
  CockpitTestActionKind.waitForNetworkIdle =>
    CockpitCommandType.waitForNetworkIdle,
  CockpitTestActionKind.waitForUiIdle => CockpitCommandType.waitForUiIdle,
  CockpitTestActionKind.assertVisible =>
    action.value<bool>(CockpitTestActionField.expected) == false
        ? CockpitCommandType.waitFor
        : CockpitCommandType.assertVisible,
  CockpitTestActionKind.assertText => CockpitCommandType.assertText,
  CockpitTestActionKind.assertScreenshot => CockpitCommandType.assertScreenshot,
  CockpitTestActionKind.travel => CockpitCommandType.travel,
  CockpitTestActionKind.system => CockpitCommandType.system,
  CockpitTestActionKind.captureScreenshot =>
    CockpitCommandType.captureScreenshot,
  CockpitTestActionKind.collectSnapshot => CockpitCommandType.collectSnapshot,
  CockpitTestActionKind.waitFor => throw StateError(
    'waitFor is lowered through its condition.',
  ),
};

Map<String, Object?> _parameters(CockpitTestAction action) {
  final parameters = <String, Object?>{};
  for (final entry in action.values.entries) {
    switch (entry.key) {
      case CockpitTestActionField.keyRequest:
        parameters.addAll(
          Map<String, Object?>.from(entry.value! as Map<Object?, Object?>),
        );
      case CockpitTestActionField.selectionStart:
        parameters['selectionBase'] = entry.value;
      case CockpitTestActionField.selectionEnd:
        parameters['selectionExtent'] = entry.value;
      case CockpitTestActionField.composingStart ||
          CockpitTestActionField.composingEnd:
        throw const FormatException(
          'The Flutter backend does not support composing ranges.',
        );
      case CockpitTestActionField.distance:
        parameters['distanceFactor'] = entry.value;
      case CockpitTestActionField.direction:
        if (action.kind == CockpitTestActionKind.scrollUntilVisible) {
          parameters['reverse'] = entry.value == 'up';
        } else {
          parameters[entry.key.wireName] = entry.value;
        }
      case CockpitTestActionField.velocity:
        break;
      case CockpitTestActionField.artifactName:
        parameters['name'] = entry.value;
      case CockpitTestActionField.systemName:
        parameters['action'] = entry.value;
      case CockpitTestActionField.systemParameters:
        parameters['parameters'] = entry.value;
      case CockpitTestActionField.quietMs
          when action.kind == CockpitTestActionKind.waitForUiIdle ||
              action.kind == CockpitTestActionKind.waitForNetworkIdle:
        parameters['quietWindowMs'] = entry.value;
      case CockpitTestActionField.captureOptions ||
          CockpitTestActionField.snapshotOptions ||
          CockpitTestActionField.expected ||
          CockpitTestActionField.matchMode:
        break;
      default:
        parameters[entry.key.wireName] = entry.value;
    }
  }
  if (action.kind == CockpitTestActionKind.fling) {
    final dx = action.value<num>(CockpitTestActionField.dx)!.toDouble();
    final dy = action.value<num>(CockpitTestActionField.dy)!.toDouble();
    final velocity = action
        .value<num>(CockpitTestActionField.velocity)!
        .toDouble();
    final distance = math.sqrt(dx * dx + dy * dy);
    parameters['durationMs'] = (distance / velocity * 1000).round();
  }
  if (action.kind == CockpitTestActionKind.assertVisible &&
      action.value<bool>(CockpitTestActionField.expected) == false) {
    parameters['absent'] = true;
  }
  return Map<String, Object?>.unmodifiable(parameters);
}

Map<String, Object?> _conditionParameters(CockpitTestCondition condition) =>
    switch (condition.kind) {
      CockpitTestConditionKind.visible => <String, Object?>{
        if (condition.expected == false) 'absent': true,
      },
      CockpitTestConditionKind.text => <String, Object?>{
        'text': condition.text,
      },
      CockpitTestConditionKind.route => <String, Object?>{
        'routeName': condition.route,
      },
      CockpitTestConditionKind.uiIdle ||
      CockpitTestConditionKind.networkIdle => <String, Object?>{
        if (condition.quietMs != null) 'quietMs': condition.quietMs,
      },
    };

CockpitSnapshotOptions? _snapshotOptions(CockpitTestAction action) {
  final value = action.values[CockpitTestActionField.snapshotOptions];
  return value is Map<Object?, Object?>
      ? CockpitSnapshotOptions.fromJson(Map<String, Object?>.from(value))
      : null;
}

CockpitScreenshotRequest? _screenshotRequest(
  CockpitTestAction action,
  CockpitLocator? loweredLocator,
) {
  if (action.kind != CockpitTestActionKind.captureScreenshot &&
      action.kind != CockpitTestActionKind.assertScreenshot) {
    return null;
  }
  final assertion = action.kind == CockpitTestActionKind.assertScreenshot;
  final options = action.values[CockpitTestActionField.captureOptions];
  final json = options is Map<Object?, Object?>
      ? Map<String, Object?>.from(options)
      : <String, Object?>{};
  return CockpitScreenshotRequest(
    reason: json['reason'] == null
        ? assertion
              ? CockpitScreenshotReason.baseline
              : CockpitScreenshotReason.acceptance
        : CockpitScreenshotReason.fromJson(json['reason']),
    name:
        action.value<String>(CockpitTestActionField.artifactName) ??
        (assertion ? 'screenshot-assertion' : 'screenshot'),
    includeSnapshot:
        json['includeSnapshot'] as bool? ??
        (assertion && action.locator != null),
    attachToStep: json['attachToStep'] as bool? ?? true,
    snapshotOptions: json['snapshotOptions'] is Map<Object?, Object?>
        ? CockpitSnapshotOptions.fromJson(
            Map<String, Object?>.from(
              json['snapshotOptions']! as Map<Object?, Object?>,
            ),
          )
        : null,
    profile: json['profile'] == null
        ? null
        : CockpitCaptureProfile.fromJson(json['profile']),
    allowFallback: json['allowFallback'] as bool?,
    cropLocator: assertion ? loweredLocator : null,
  );
}
