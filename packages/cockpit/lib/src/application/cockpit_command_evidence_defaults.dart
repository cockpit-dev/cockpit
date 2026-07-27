import 'package:cockpit_protocol/cockpit_protocol.dart';

CockpitCommand cockpitCommandWithAiEvidenceDefaults(CockpitCommand command) {
  final explicitCaptureCommand = _withExplicitScreenshotRequest(command);
  if (explicitCaptureCommand != null) {
    return explicitCaptureCommand;
  }

  if (!_shouldDefaultToAfterActionCapture(command)) {
    return command;
  }

  return command.copyWith(
    capturePolicy: CockpitCapturePolicy.afterAction,
    captureFailurePolicy: CockpitCaptureFailurePolicy.degradeCommand,
    screenshotRequest:
        command.screenshotRequest ??
        CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.afterAction,
          name: command.commandId,
          includeSnapshot: false,
          attachToStep: true,
        ),
  );
}

CockpitCommand? _withExplicitScreenshotRequest(CockpitCommand command) {
  if (command.commandType != CockpitCommandType.captureScreenshot ||
      command.screenshotRequest != null) {
    return null;
  }

  final name = _stringParameter(command, 'name') ?? command.commandId;
  final reasonValue =
      _stringParameter(command, 'reason') ??
      _stringParameter(command, 'purpose') ??
      CockpitScreenshotReason.acceptance.jsonValue;
  return command.copyWith(
    screenshotRequest: CockpitScreenshotRequest(
      reason: _screenshotReasonFromLegacyValue(reasonValue),
      name: name,
      includeSnapshot: _boolParameter(command, 'includeSnapshot') ?? false,
      attachToStep: _boolParameter(command, 'attachToStep') ?? true,
      snapshotOptions: command.snapshotOptions,
    ),
  );
}

CockpitScreenshotReason _screenshotReasonFromLegacyValue(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'diagnostic' ||
    'diagnostics' ||
    'debug' ||
    'investigation' => CockpitScreenshotReason.assertionFailure,
    _ => CockpitScreenshotReason.fromJson(value),
  };
}

String? _stringParameter(CockpitCommand command, String key) {
  final value = command.parameters[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

bool? _boolParameter(CockpitCommand command, String key) {
  final value = command.parameters[key];
  return value is bool ? value : null;
}

bool cockpitCommandUsesAiEvidenceDefaults(CockpitCommand command) {
  return _shouldDefaultToAfterActionCapture(command);
}

bool cockpitCommandTypeIsAiEvidenceKeyOperation(
  CockpitCommandType commandType,
) {
  return _isKeyOperation(commandType);
}

bool _shouldDefaultToAfterActionCapture(CockpitCommand command) {
  if (command.commandType == CockpitCommandType.captureScreenshot ||
      command.commandType == CockpitCommandType.collectSnapshot) {
    return false;
  }
  if (command.capturePolicy != CockpitCapturePolicy.none) {
    return false;
  }
  if (command.screenshotRequest != null) {
    return _isKeyOperation(command.commandType);
  }
  return _isKeyOperation(command.commandType);
}

bool _isKeyOperation(CockpitCommandType commandType) {
  return switch (commandType) {
    CockpitCommandType.tap ||
    CockpitCommandType.enterText ||
    CockpitCommandType.eraseText ||
    CockpitCommandType.pasteText ||
    CockpitCommandType.focusTextInput ||
    CockpitCommandType.setTextEditingValue ||
    CockpitCommandType.sendTextInputAction ||
    CockpitCommandType.sendKeyEvent ||
    CockpitCommandType.sendKeyDownEvent ||
    CockpitCommandType.sendKeyUpEvent ||
    CockpitCommandType.longPress ||
    CockpitCommandType.doubleTap ||
    CockpitCommandType.drag ||
    CockpitCommandType.fling ||
    CockpitCommandType.swipe ||
    CockpitCommandType.pinchZoom ||
    CockpitCommandType.rotate ||
    CockpitCommandType.panZoom ||
    CockpitCommandType.multiTouch ||
    CockpitCommandType.scrollUntilVisible ||
    CockpitCommandType.back ||
    CockpitCommandType.showOnScreen ||
    CockpitCommandType.increase ||
    CockpitCommandType.decrease ||
    CockpitCommandType.dismiss ||
    CockpitCommandType.dismissKeyboard ||
    CockpitCommandType.system ||
    CockpitCommandType.travel => true,
    CockpitCommandType.copyText ||
    CockpitCommandType.clearNetworkActivity ||
    CockpitCommandType.waitForNetworkIdle ||
    CockpitCommandType.waitForUiIdle ||
    CockpitCommandType.waitFor ||
    CockpitCommandType.assertVisible ||
    CockpitCommandType.assertText ||
    CockpitCommandType.assertScreenshot ||
    CockpitCommandType.captureScreenshot ||
    CockpitCommandType.collectSnapshot => false,
  };
}
