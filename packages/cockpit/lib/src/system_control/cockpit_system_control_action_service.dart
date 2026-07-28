import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../capture/cockpit_adb_capture_adapter.dart';
import '../capture/cockpit_linux_capture_adapter.dart';
import '../capture/cockpit_macos_capture_adapter.dart';
import '../capture/cockpit_simctl_capture_adapter.dart';
import '../capture/cockpit_windows_capture_adapter.dart';
import '../capture/cockpit_wda_capture_adapter.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../recording/cockpit_adb_recording_adapter.dart';
import '../recording/cockpit_linux_recording_adapter.dart';
import '../recording/cockpit_macos_recording_adapter.dart';
import '../recording/cockpit_simctl_recording_adapter.dart';
import '../recording/cockpit_windows_recording_adapter.dart';
import 'cockpit_system_control_adapter.dart';
import 'cockpit_ios_webdriver_agent_client.dart';
import 'cockpit_system_control_parameters.dart';
import 'cockpit_system_control_service.dart';

export 'cockpit_system_control_action.dart';
export 'cockpit_system_control_profile.dart';

typedef CockpitSystemControlRunActionFunction =
    Future<CockpitSystemControlActionResult> Function(
      CockpitSystemControlActionRequest request,
    );
typedef CockpitSystemControlCaptureAdapterFactory =
    CockpitCaptureAdapter? Function(CockpitSystemControlActionRequest request);
typedef CockpitSystemControlRecordingAdapterFactory =
    CockpitRecordingAdapter? Function(
      CockpitSystemControlActionRequest request,
    );
typedef CockpitIosWdaRunner =
    Future<String> Function(
      CockpitIosWdaCommand command, {
      required Duration timeout,
    });

final class CockpitSystemControlActionService {
  CockpitSystemControlActionService({
    CockpitProcessManager? processManager,
    CockpitSystemControlRegistry registry =
        const CockpitSystemControlRegistry(),
    CockpitSystemControlService? systemControlService,
    CockpitSystemControlCaptureAdapterFactory? captureAdapterFactory,
    CockpitSystemControlRecordingAdapterFactory? recordingAdapterFactory,
    CockpitIosWdaRunner? iosWdaRunner,
  }) : _processManager = processManager ?? const LocalCockpitProcessManager(),
       _registry = registry,
       _systemControlService =
           systemControlService ??
           CockpitSystemControlService(
             processManager:
                 processManager ?? const LocalCockpitProcessManager(),
             registry: registry,
           ),
       _captureAdapterFactory =
           captureAdapterFactory ?? _defaultCaptureAdapterFor,
       _recordingAdapterFactory =
           recordingAdapterFactory ?? _defaultRecordingAdapterFor,
       _iosWdaRunner = iosWdaRunner ?? CockpitIosWebDriverAgentClient().run;

  final CockpitProcessManager _processManager;
  final CockpitSystemControlRegistry _registry;
  final CockpitSystemControlService _systemControlService;
  final CockpitSystemControlCaptureAdapterFactory _captureAdapterFactory;
  final CockpitSystemControlRecordingAdapterFactory _recordingAdapterFactory;
  final CockpitIosWdaRunner _iosWdaRunner;

  Future<CockpitSystemControlActionResult> run(
    CockpitSystemControlActionRequest request,
  ) async {
    final describe = await _systemControlService.describe(
      CockpitSystemControlDescribeRequest(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        metadata: request.metadata,
      ),
    );
    final profile = describe.profile;
    final capability = profile.capabilityFor(request.action);
    if (capability == null) {
      return _notExecutable(
        request,
        availability: CockpitSystemControlAvailability.unsupported,
        recommendedNextStep: 'readSystemCapabilities',
        errorCode: 'unsupportedSystemAction',
        errorMessage:
            '${request.action.name} is not declared for ${profile.platform}.',
      );
    }
    if (capability.availability != CockpitSystemControlAvailability.available) {
      return _notExecutable(
        request,
        availability: capability.availability,
        recommendedNextStep: profile.recommendedNextStep,
        errorCode: 'systemActionNotAvailable',
        errorMessage:
            '${request.action.name} is ${capability.availability.name} on ${profile.platform}.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }
    final payloadError = _validateDeclaredPayload(request, capability);
    if (payloadError != null) {
      return payloadError;
    }

    // Probe-discovered metadata (for example an auto-discovered WDA endpoint)
    // must reach command resolution and macro sub-steps.
    final effectiveRequest = CockpitSystemControlActionRequest(
      platform: request.platform,
      deviceId: request.deviceId,
      appId: request.appId,
      processId: request.processId,
      metadata: describe.metadata,
      action: request.action,
      parameters: request.parameters,
      timeout: request.timeout,
    );

    if (request.action == CockpitSystemControlAction.captureScreenshot) {
      return _captureScreenshot(effectiveRequest, profile, capability);
    }
    if (request.action == CockpitSystemControlAction.startRecording) {
      return _startRecording(effectiveRequest, profile, capability);
    }
    if (request.action == CockpitSystemControlAction.stopRecording) {
      return _stopRecording(effectiveRequest, profile, capability);
    }
    if (request.action == CockpitSystemControlAction.preparePermissions) {
      return _preparePermissions(effectiveRequest, profile, capability);
    }
    if (request.action == CockpitSystemControlAction.stabilizeForScreenshot) {
      return _stabilizeForScreenshot(effectiveRequest, profile, capability);
    }

    final command = _registry
        .resolve(request.platform)
        .resolveCommand(effectiveRequest);
    if (command.hasError) {
      return _notExecutable(
        request,
        availability: capability.availability,
        recommendedNextStep: _recommendedNextStepForCommandError(command),
        errorCode: command.errorCode,
        errorMessage: command.errorMessage,
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }

    if (command.executable == cockpitIosWdaCommandExecutable) {
      return _runIosWebDriverAgentCommand(request, capability, command);
    }

    return _runProcessCommand(request, capability, command);
  }

  Future<CockpitSystemControlActionResult> _preparePermissions(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability,
  ) async {
    final permissions = cockpitReadSystemControlStringListParameter(
      request.parameters,
      'permissions',
    );
    final mode = cockpitReadSystemControlStringParameter(
      request.parameters,
      'mode',
      allowedValues: const <String>['grant', 'revoke', 'reset'],
    );
    final recover = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'recover',
    );
    final appId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appId',
    );
    final packageId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'packageId',
    );
    if (permissions.isInvalid ||
        mode.isInvalid ||
        recover.isInvalid ||
        appId.isInvalid ||
        packageId.isInvalid) {
      return _invalidEvidencePayload(
        request,
        capability,
        'preparePermissions accepts permissions, mode, recover, appId, and packageId parameters declared by system capabilities.',
      );
    }
    if (!permissions.isValid || permissions.value!.isEmpty) {
      return _notExecutable(
        request,
        availability: capability.availability,
        recommendedNextStep: 'fixActionPayload',
        errorCode: 'missingSystemActionParameter',
        errorMessage: 'preparePermissions requires at least one permission.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }

    final normalizedMode = mode.value ?? 'grant';
    final permissionAction = switch (normalizedMode) {
      'grant' => CockpitSystemControlAction.grantPermission,
      'revoke' => CockpitSystemControlAction.revokePermission,
      'reset' => CockpitSystemControlAction.resetPermission,
      _ => CockpitSystemControlAction.grantPermission,
    };
    final steps = <_SystemMacroStep>[];
    for (final permission in permissions.value!) {
      final trimmed = permission.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      steps.add(
        _SystemMacroStep(
          action: permissionAction,
          parameters: <String, Object?>{
            ..._macroTargetParameters(request),
            'permission': trimmed,
          },
          label: '${permissionAction.name}:$trimmed',
        ),
      );
    }
    if (steps.isEmpty) {
      return _notExecutable(
        request,
        availability: capability.availability,
        recommendedNextStep: 'fixActionPayload',
        errorCode: 'missingSystemActionParameter',
        errorMessage: 'preparePermissions requires non-empty permissions.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }
    if (recover.value ?? true) {
      steps.add(
        _SystemMacroStep(
          action: CockpitSystemControlAction.recoverToApp,
          parameters: _macroTargetParameters(request),
        ),
      );
    }
    return _runMacroSteps(
      request,
      profile,
      capability,
      steps: steps,
      recommendedNextStepOnSuccess: 'readPostActionState',
    );
  }

  Future<CockpitSystemControlActionResult> _stabilizeForScreenshot(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability,
  ) async {
    final dismissKeyboard = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'dismissKeyboard',
    );
    final collapseSystemUi = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'collapseSystemUi',
    );
    final recover = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'recover',
    );
    final orientation = cockpitReadSystemControlStringParameter(
      request.parameters,
      'orientation',
      allowedValues: const <String>[
        'portrait',
        'landscape',
        'reversePortrait',
        'reverseLandscape',
        'auto',
      ],
    );
    final statusBar = cockpitReadSystemControlStringParameter(
      request.parameters,
      'statusBar',
      allowedValues: const <String>['default', 'clear', 'stable'],
    );
    final time = cockpitReadSystemControlStringParameter(
      request.parameters,
      'time',
    );
    final appearance = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appearance',
      allowedValues: const <String>['light', 'dark', 'auto'],
    );
    final appId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appId',
    );
    final packageId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'packageId',
    );
    if (dismissKeyboard.isInvalid ||
        collapseSystemUi.isInvalid ||
        recover.isInvalid ||
        orientation.isInvalid ||
        statusBar.isInvalid ||
        time.isInvalid ||
        appearance.isInvalid ||
        appId.isInvalid ||
        packageId.isInvalid) {
      return _invalidEvidencePayload(
        request,
        capability,
        'stabilizeForScreenshot accepts dismissKeyboard, collapseSystemUi, recover, orientation, statusBar, time, appearance, appId, and packageId parameters declared by system capabilities.',
      );
    }

    final steps = <_SystemMacroStep>[];
    if (dismissKeyboard.value ?? true) {
      steps.add(
        const _SystemMacroStep(
          action: CockpitSystemControlAction.dismissKeyboard,
          optional: true,
        ),
      );
    }
    if (collapseSystemUi.value ?? true) {
      steps.add(
        const _SystemMacroStep(
          action: CockpitSystemControlAction.collapseSystemUi,
          optional: true,
        ),
      );
    }
    if (orientation.value != null && orientation.value != 'auto') {
      steps.add(
        _SystemMacroStep(
          action: CockpitSystemControlAction.setOrientation,
          parameters: <String, Object?>{'orientation': orientation.value},
          optional: true,
        ),
      );
    }
    if (appearance.value != null && appearance.value != 'auto') {
      steps.add(
        _SystemMacroStep(
          action: CockpitSystemControlAction.setAppearance,
          parameters: <String, Object?>{'appearance': appearance.value},
          optional: true,
        ),
      );
    }
    switch (statusBar.value) {
      case 'clear':
        steps.add(
          const _SystemMacroStep(
            action: CockpitSystemControlAction.clearStatusBar,
            optional: true,
          ),
        );
      case 'stable':
        steps.add(
          _SystemMacroStep(
            action: CockpitSystemControlAction.setStatusBar,
            parameters: <String, Object?>{
              'time': time.value ?? '9:41',
              'dataNetwork': 'wifi',
              'wifiMode': 'active',
              'wifiBars': 3,
              'cellularMode': 'active',
              'cellularBars': 4,
              'batteryState': 'charged',
              'batteryLevel': 100,
            },
            optional: true,
          ),
        );
      case 'default':
      case null:
        break;
    }
    if (recover.value ?? true) {
      steps.add(
        _SystemMacroStep(
          action: CockpitSystemControlAction.recoverToApp,
          parameters: _macroTargetParameters(request),
          optional: true,
        ),
      );
    }
    return _runMacroSteps(
      request,
      profile,
      capability,
      steps: steps,
      recommendedNextStepOnSuccess: 'captureScreenshot',
    );
  }

  Future<CockpitSystemControlActionResult> _runIosWebDriverAgentCommand(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlCapability capability,
    CockpitResolvedSystemControlCommand command,
  ) async {
    try {
      final stdout = await _iosWdaRunner(
        CockpitIosWebDriverAgentClient.commandFromArguments(command.arguments),
        timeout: request.timeout,
      );
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: true,
        command: <String>[command.executable!, ...command.arguments],
        stdout: stdout,
        recommendedNextStep: 'readPostActionState',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    } on Object catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        command: <String>[command.executable!, ...command.arguments],
        recommendedNextStep: 'inspectWebDriverAgentFailure',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        errorCode: 'webDriverAgentActionFailed',
        errorMessage: _describeSystemControlError(error),
      );
    }
  }

  CockpitSystemControlActionResult? _validateDeclaredPayload(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlCapability capability,
  ) {
    final parametersByName = <String, CockpitSystemControlParameter>{
      for (final parameter in capability.parameters) parameter.name: parameter,
    };
    for (final entry in request.parameters.entries) {
      final parameter = parametersByName[entry.key];
      if (parameter == null) {
        return _notExecutable(
          request,
          availability: capability.availability,
          recommendedNextStep: 'fixActionPayload',
          errorCode: 'invalidSystemActionParameter',
          errorMessage:
              '${request.action.name} does not accept parameter ${entry.key}. Use read-system-capabilities parameters.',
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
        );
      }
      final typeErrorMessage = _validateSystemControlValueType(
        request.action,
        parameter,
        entry.value,
      );
      if (typeErrorMessage != null) {
        return _notExecutable(
          request,
          availability: capability.availability,
          recommendedNextStep: 'fixActionPayload',
          errorCode: 'invalidSystemActionParameter',
          errorMessage: typeErrorMessage,
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
        );
      }
      final errorMessage = _validateSystemControlAllowedValue(
        request.action,
        parameter,
        entry.value,
      );
      if (errorMessage != null) {
        return _notExecutable(
          request,
          availability: capability.availability,
          recommendedNextStep: 'fixActionPayload',
          errorCode: 'invalidSystemActionParameter',
          errorMessage: errorMessage,
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
        );
      }
    }
    for (final parameter in capability.parameters) {
      if (!parameter.required) {
        continue;
      }
      if (_isSystemControlParameterAbsent(
        request.parameters[parameter.name],
        parameter,
      )) {
        return _notExecutable(
          request,
          availability: capability.availability,
          recommendedNextStep: 'fixActionPayload',
          errorCode: 'missingSystemActionParameter',
          errorMessage:
              '${request.action.name} requires ${parameter.name}. Use read-system-capabilities parameters.',
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
        );
      }
    }
    return null;
  }

  Future<CockpitSystemControlActionResult> _captureScreenshot(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability,
  ) async {
    final name = cockpitReadSystemControlStringParameter(
      request.parameters,
      'name',
    );
    final outputPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'outputPath',
    );
    if (name.isInvalid || outputPath.isInvalid) {
      return _invalidEvidencePayload(
        request,
        capability,
        'captureScreenshot accepts string name and outputPath parameters.',
      );
    }
    final adapter = _captureAdapterFactory(request);
    if (adapter == null) {
      return _notExecutable(
        request,
        availability: CockpitSystemControlAvailability.blocked,
        recommendedNextStep: profile.recommendedNextStep,
        errorCode: 'systemCaptureUnavailable',
        errorMessage:
            'No capture adapter is available for ${request.platform}.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }

    try {
      final execution = await adapter.capture(
        CockpitCommand(
          commandId: 'system-capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          timeoutMs: request.timeout.inMilliseconds,
          screenshotRequest: CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: name.value ?? 'system-screenshot',
          ),
        ),
      );
      final result = execution.result;
      final artifact = result.artifacts.isEmpty ? null : result.artifacts.first;
      final sourcePath = artifact == null
          ? null
          : execution.artifactSourcePaths[artifact.relativePath];
      if (result.success && (sourcePath == null || sourcePath.isEmpty)) {
        return CockpitSystemControlActionResult(
          platform: request.platform,
          deviceId: request.deviceId,
          appId: request.appId,
          processId: request.processId,
          action: request.action,
          availability: capability.availability,
          success: false,
          recommendedNextStep: 'inspectCaptureFailure',
          errorCode: 'systemCaptureMissingArtifact',
          errorMessage:
              'Capture adapter reported success without a source artifact path.',
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
          artifact: artifact?.toJson(),
        );
      }
      String? finalSourcePath = sourcePath;
      if (result.success && sourcePath != null && outputPath.value != null) {
        finalSourcePath = await _copyArtifactToOutputPath(
          sourcePath: sourcePath,
          outputPath: outputPath.value!,
        );
      }

      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: result.success,
        recommendedNextStep: result.success
            ? 'readPostActionState'
            : 'inspectCaptureFailure',
        errorCode: result.success ? null : 'systemCaptureFailed',
        errorMessage: result.error?.message,
        errorDetails: <String, Object?>{
          if (result.error case final error?) 'driverError': error.toJson(),
        },
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        artifact: artifact?.toJson(),
        sourceFilePath: finalSourcePath,
      );
    } on Object catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        recommendedNextStep: 'inspectCaptureFailure',
        errorCode: 'systemCaptureFailed',
        errorMessage: _describeSystemControlError(error),
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }
  }

  Future<CockpitSystemControlActionResult> _startRecording(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability,
  ) async {
    final recordingRequest = _recordingRequestFromParameters(
      request.parameters,
    );
    if (recordingRequest == null) {
      return _invalidEvidencePayload(
        request,
        capability,
        'startRecording accepts string name, purpose, mode, and layer parameters declared by system capabilities.',
      );
    }
    final adapter = _recordingAdapterFactory(request);
    if (adapter == null) {
      return _notExecutable(
        request,
        availability: CockpitSystemControlAvailability.blocked,
        recommendedNextStep: profile.recommendedNextStep,
        errorCode: 'systemRecordingUnavailable',
        errorMessage:
            'No recording adapter is available for ${request.platform}.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }

    try {
      final recordingSession = await adapter.startRecording(recordingRequest);
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: true,
        recommendedNextStep: 'runFlowThenStopRecording',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        recordingSession: recordingSession.toJson(),
      );
    } on Object catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        recommendedNextStep: 'inspectRecordingFailure',
        errorCode: 'systemRecordingFailed',
        errorMessage: _describeSystemControlError(error),
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }
  }

  Future<CockpitSystemControlActionResult> _stopRecording(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability,
  ) async {
    final outputPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'outputPath',
    );
    if (outputPath.isInvalid) {
      return _invalidEvidencePayload(
        request,
        capability,
        'stopRecording accepts a string outputPath parameter.',
      );
    }
    final adapter = _recordingAdapterFactory(request);
    if (adapter == null) {
      return _notExecutable(
        request,
        availability: CockpitSystemControlAvailability.blocked,
        recommendedNextStep: profile.recommendedNextStep,
        errorCode: 'systemRecordingUnavailable',
        errorMessage:
            'No recording adapter is available for ${request.platform}.',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }

    try {
      final recordingResult = await adapter.stopRecording();
      final success = recordingResult.state == CockpitRecordingState.completed;
      var finalSourcePath = recordingResult.sourceFilePath;
      if (success && (finalSourcePath == null || finalSourcePath.isEmpty)) {
        return CockpitSystemControlActionResult(
          platform: request.platform,
          deviceId: request.deviceId,
          appId: request.appId,
          processId: request.processId,
          action: request.action,
          availability: capability.availability,
          success: false,
          recommendedNextStep: 'inspectRecordingFailure',
          errorCode: 'systemRecordingMissingArtifact',
          errorMessage:
              'Recording adapter reported completion without a source file path.',
          strategy: capability.strategy,
          requires: capability.requires,
          limitations: capability.limitations,
          artifact: recordingResult.artifact?.toJson(),
          recordingResult: recordingResult.toJson(),
        );
      }
      if (success && finalSourcePath != null && outputPath.value != null) {
        finalSourcePath = await _copyArtifactToOutputPath(
          sourcePath: finalSourcePath,
          outputPath: outputPath.value!,
        );
      }
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: success,
        recommendedNextStep: success
            ? 'readPostActionState'
            : 'inspectRecordingFailure',
        errorCode: success ? null : 'systemRecordingFailed',
        errorMessage: recordingResult.failureReason,
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        artifact: recordingResult.artifact?.toJson(),
        sourceFilePath: finalSourcePath,
        recordingResult: finalSourcePath == recordingResult.sourceFilePath
            ? recordingResult.toJson()
            : recordingResult
                  .copyWith(sourceFilePath: finalSourcePath)
                  .toJson(),
      );
    } on Object catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        recommendedNextStep: 'inspectRecordingFailure',
        errorCode: 'systemRecordingFailed',
        errorMessage: _describeSystemControlError(error),
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
      );
    }
  }

  CockpitSystemControlActionResult _notExecutable(
    CockpitSystemControlActionRequest request, {
    required CockpitSystemControlAvailability availability,
    required String recommendedNextStep,
    required String? errorCode,
    required String? errorMessage,
    String? strategy,
    List<String> requires = const <String>[],
    List<String> limitations = const <String>[],
  }) {
    return CockpitSystemControlActionResult(
      platform: request.platform,
      deviceId: request.deviceId,
      appId: request.appId,
      processId: request.processId,
      action: request.action,
      availability: availability,
      success: false,
      recommendedNextStep: recommendedNextStep,
      errorCode: errorCode,
      errorMessage: errorMessage,
      strategy: strategy,
      requires: requires,
      limitations: limitations,
    );
  }

  Future<CockpitSystemControlActionResult> _runMacroSteps(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlProfile profile,
    CockpitSystemControlCapability capability, {
    required List<_SystemMacroStep> steps,
    required String recommendedNextStepOnSuccess,
  }) async {
    final stepResults = <Map<String, Object?>>[];
    var success = true;
    String? errorCode;
    String? errorMessage;
    for (final step in steps) {
      final stepCapability = profile.capabilityFor(step.action);
      if (stepCapability == null ||
          stepCapability.availability !=
              CockpitSystemControlAvailability.available) {
        final availability =
            stepCapability?.availability ??
            CockpitSystemControlAvailability.unsupported;
        final skipped = <String, Object?>{
          'label': step.label ?? step.action.name,
          'action': step.action.name,
          'availability': availability.name,
          'success': step.optional,
          'skipped': true,
          if (stepCapability != null) 'strategy': stepCapability.strategy,
          if (stepCapability?.requires.isNotEmpty ?? false)
            'requires': stepCapability!.requires,
          if (stepCapability?.limitations.isNotEmpty ?? false)
            'limitations': stepCapability!.limitations,
        };
        stepResults.add(skipped);
        if (!step.optional) {
          success = false;
          errorCode = 'systemMacroStepNotAvailable';
          errorMessage =
              '${step.action.name} is ${availability.name} on ${profile.platform}.';
          break;
        }
        continue;
      }
      final subRequest = CockpitSystemControlActionRequest(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        metadata: request.metadata,
        action: step.action,
        parameters: <String, Object?>{...step.parameters},
        timeout: request.timeout,
      );
      final payloadError = _validateDeclaredPayload(subRequest, stepCapability);
      if (payloadError != null) {
        stepResults.add(<String, Object?>{
          'label': step.label ?? step.action.name,
          'action': step.action.name,
          'availability': stepCapability.availability.name,
          'success': false,
          if (step.optional) 'optional': true,
          'errorCode': payloadError.errorCode,
          'errorMessage': payloadError.errorMessage,
        });
        if (step.optional) {
          continue;
        }
        success = false;
        errorCode = payloadError.errorCode;
        errorMessage = payloadError.errorMessage;
        break;
      }
      final command = _registry
          .resolve(request.platform)
          .resolveCommand(subRequest);
      if (command.hasError) {
        stepResults.add(<String, Object?>{
          'label': step.label ?? step.action.name,
          'action': step.action.name,
          'availability': stepCapability.availability.name,
          'success': false,
          if (step.optional) 'optional': true,
          'errorCode': command.errorCode,
          'errorMessage': command.errorMessage,
        });
        if (step.optional) {
          continue;
        }
        success = false;
        errorCode = command.errorCode;
        errorMessage = command.errorMessage;
        break;
      }
      final stepResult = await _runResolvedCommand(
        subRequest,
        stepCapability,
        command,
      );
      stepResults.add(<String, Object?>{
        'label': step.label ?? step.action.name,
        'action': step.action.name,
        'availability': stepResult.availability.name,
        'success': stepResult.success,
        if (step.optional) 'optional': true,
        if (stepResult.strategy != null) 'strategy': stepResult.strategy,
        if (stepResult.command.isNotEmpty) 'command': stepResult.command,
        if (stepResult.exitCode != null) 'exitCode': stepResult.exitCode,
        if (stepResult.stdout != null && stepResult.stdout!.isNotEmpty)
          'stdout': stepResult.stdout,
        if (stepResult.stderr != null && stepResult.stderr!.isNotEmpty)
          'stderr': stepResult.stderr,
        if (stepResult.errorCode != null) 'errorCode': stepResult.errorCode,
        if (stepResult.errorMessage != null)
          'errorMessage': stepResult.errorMessage,
      });
      if (!stepResult.success) {
        if (step.optional) {
          continue;
        }
        success = false;
        errorCode = stepResult.errorCode ?? 'systemMacroStepFailed';
        errorMessage =
            stepResult.errorMessage ??
            '${step.action.name} failed during ${request.action.name}.';
        break;
      }
    }
    return CockpitSystemControlActionResult(
      platform: request.platform,
      deviceId: request.deviceId,
      appId: request.appId,
      processId: request.processId,
      action: request.action,
      availability: capability.availability,
      success: success,
      stdout: const JsonEncoder.withIndent(
        '  ',
      ).convert(<String, Object?>{'steps': stepResults}),
      recommendedNextStep: success
          ? recommendedNextStepOnSuccess
          : 'inspectSystemMacroFailure',
      strategy: capability.strategy,
      requires: capability.requires,
      limitations: _macroLimitations(capability.limitations, stepResults),
      errorCode: success ? null : errorCode,
      errorMessage: success ? null : errorMessage,
    );
  }

  Future<CockpitSystemControlActionResult> _runResolvedCommand(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlCapability capability,
    CockpitResolvedSystemControlCommand command,
  ) async {
    if (command.executable == cockpitIosWdaCommandExecutable) {
      return _runIosWebDriverAgentCommand(request, capability, command);
    }
    return _runProcessCommand(request, capability, command);
  }

  Future<CockpitSystemControlActionResult> _runProcessCommand(
    CockpitSystemControlActionRequest request,
    CockpitSystemControlCapability capability,
    CockpitResolvedSystemControlCommand command,
  ) async {
    final attemptLimit = _processAttemptLimit(request);
    late ProcessResult processResult;
    try {
      for (var attempt = 1; ; attempt += 1) {
        try {
          processResult = await cockpitRunManagedProcessWithTimeout(
            _processManager,
            command.executable!,
            command.arguments,
            timeout: request.timeout,
          );
          if (processResult.exitCode == 0 || attempt >= attemptLimit) {
            break;
          }
        } on CockpitManagedProcessTimeoutException {
          if (attempt >= attemptLimit) {
            rethrow;
          }
        }
      }
    } on CockpitManagedProcessTimeoutException catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        command: <String>[command.executable!, ...command.arguments],
        stdout: error.stdout.trimRight(),
        stderr: error.stderr.trimRight(),
        recommendedNextStep: 'inspectShellFailure',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        errorCode: 'systemActionTimedOut',
        errorMessage:
            'System action command timed out after ${error.duration.inMilliseconds}ms.',
      );
    } on Object catch (error) {
      return CockpitSystemControlActionResult(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        action: request.action,
        availability: capability.availability,
        success: false,
        command: <String>[command.executable!, ...command.arguments],
        recommendedNextStep: 'inspectShellFailure',
        strategy: capability.strategy,
        requires: capability.requires,
        limitations: capability.limitations,
        errorCode: 'systemActionProcessFailed',
        errorMessage: _describeSystemControlError(error),
      );
    }
    final exitCode = processResult.exitCode;
    final success = exitCode == 0;
    return CockpitSystemControlActionResult(
      platform: request.platform,
      deviceId: request.deviceId,
      appId: request.appId,
      processId: request.processId,
      action: request.action,
      availability: capability.availability,
      success: success,
      command: <String>[command.executable!, ...command.arguments],
      exitCode: exitCode,
      stdout: '${processResult.stdout}'.trimRight(),
      stderr: '${processResult.stderr}'.trimRight(),
      recommendedNextStep: success
          ? _recommendedNextStepAfterSuccess(request.action)
          : 'inspectShellFailure',
      strategy: capability.strategy,
      requires: capability.requires,
      limitations: _limitationsAfterSuccess(
        platform: request.platform,
        action: request.action,
        success: success,
        limitations: capability.limitations,
      ),
      errorCode: success ? null : 'systemActionFailed',
      errorMessage: success
          ? null
          : 'System action command exited with $exitCode.',
    );
  }
}

int _processAttemptLimit(CockpitSystemControlActionRequest request) {
  if (request.platform != 'ios') {
    return 1;
  }
  return switch (request.action) {
    CockpitSystemControlAction.setStatusBar ||
    CockpitSystemControlAction.clearStatusBar ||
    CockpitSystemControlAction.setClipboard ||
    CockpitSystemControlAction.getClipboard ||
    CockpitSystemControlAction.readSystemState ||
    CockpitSystemControlAction.readDeviceInfo ||
    CockpitSystemControlAction.readProcessList ||
    CockpitSystemControlAction.readSystemLogs => 2,
    _ => 1,
  };
}

final class _SystemMacroStep {
  const _SystemMacroStep({
    required this.action,
    this.parameters = const <String, Object?>{},
    this.optional = false,
    this.label,
  });

  final CockpitSystemControlAction action;
  final Map<String, Object?> parameters;
  final bool optional;
  final String? label;
}

CockpitSystemControlActionResult _invalidEvidencePayload(
  CockpitSystemControlActionRequest request,
  CockpitSystemControlCapability capability,
  String message,
) {
  return CockpitSystemControlActionResult(
    platform: request.platform,
    deviceId: request.deviceId,
    appId: request.appId,
    processId: request.processId,
    action: request.action,
    availability: capability.availability,
    success: false,
    recommendedNextStep: 'fixActionPayload',
    errorCode: 'invalidSystemActionParameter',
    errorMessage: message,
    strategy: capability.strategy,
    requires: capability.requires,
    limitations: capability.limitations,
  );
}

String? _validateSystemControlAllowedValue(
  CockpitSystemControlAction action,
  CockpitSystemControlParameter parameter,
  Object? value,
) {
  if (parameter.allowedValues.isEmpty) {
    return null;
  }
  if (value is! String) {
    return '${action.name} requires ${parameter.name} to be one of ${parameter.allowedValues.join(", ")}.';
  }
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (!parameter.allowedValues.contains(normalized)) {
    return '${action.name} requires ${parameter.name} to be one of ${parameter.allowedValues.join(", ")}.';
  }
  return null;
}

String? _validateSystemControlValueType(
  CockpitSystemControlAction action,
  CockpitSystemControlParameter parameter,
  Object? value,
) {
  if (value == null) {
    return null;
  }
  final valid = switch (parameter.valueType) {
    CockpitSystemControlParameterType.string => value is String,
    CockpitSystemControlParameterType.integer =>
      _readDeclaredInteger(value, parameter) != null,
    CockpitSystemControlParameterType.number =>
      _readDeclaredNumber(value, parameter) != null,
    CockpitSystemControlParameterType.boolean =>
      value is bool ||
          (value is String && _parseSystemControlBoolLiteral(value) != null),
    CockpitSystemControlParameterType.stringList =>
      value is List && value.every((item) => item is String),
  };
  if (valid) {
    return null;
  }
  return '${action.name} requires ${parameter.name} to be ${_describeSystemControlType(parameter)}.';
}

bool? _parseSystemControlBoolLiteral(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => null,
  };
}

bool _isSystemControlParameterAbsent(
  Object? value,
  CockpitSystemControlParameter parameter,
) {
  if (value == null) {
    return true;
  }
  return switch (parameter.valueType) {
    CockpitSystemControlParameterType.string =>
      value is String && value.trim().isEmpty,
    CockpitSystemControlParameterType.integer =>
      _readDeclaredInteger(value, parameter) == null,
    CockpitSystemControlParameterType.number =>
      _readDeclaredNumber(value, parameter) == null,
    CockpitSystemControlParameterType.boolean =>
      value is String && value.trim().isEmpty,
    CockpitSystemControlParameterType.stringList =>
      value is List && value.isEmpty,
  };
}

int? _readDeclaredInteger(
  Object? value,
  CockpitSystemControlParameter parameter,
) {
  final intValue = switch (value) {
    int() => value,
    num() when value.isFinite && value == value.truncateToDouble() =>
      value.toInt(),
    String() => int.tryParse(value.trim()),
    _ => null,
  };
  if (intValue == null) {
    return null;
  }
  if (parameter.minimum != null && intValue < parameter.minimum!) {
    return null;
  }
  if (parameter.maximum != null && intValue > parameter.maximum!) {
    return null;
  }
  return intValue;
}

double? _readDeclaredNumber(
  Object? value,
  CockpitSystemControlParameter parameter,
) {
  final doubleValue = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value.trim()),
    _ => null,
  };
  if (doubleValue == null || !doubleValue.isFinite) {
    return null;
  }
  if (parameter.minimum != null && doubleValue < parameter.minimum!) {
    return null;
  }
  if (parameter.maximum != null && doubleValue > parameter.maximum!) {
    return null;
  }
  return doubleValue;
}

String _describeSystemControlType(CockpitSystemControlParameter parameter) {
  final range = <String>[
    if (parameter.minimum != null) '>= ${parameter.minimum}',
    if (parameter.maximum != null) '<= ${parameter.maximum}',
  ].join(' and ');
  final type = switch (parameter.valueType) {
    CockpitSystemControlParameterType.string => 'a string',
    CockpitSystemControlParameterType.integer => 'an integer',
    CockpitSystemControlParameterType.number => 'a finite number',
    CockpitSystemControlParameterType.boolean => 'a boolean',
    CockpitSystemControlParameterType.stringList => 'an array of strings',
  };
  return range.isEmpty ? type : '$type ($range)';
}

String _recommendedNextStepForCommandError(
  CockpitResolvedSystemControlCommand command,
) {
  return switch (command.errorCode) {
    'missingSystemActionParameter' ||
    'invalidSystemActionParameter' ||
    'missingSystemActionTarget' => 'fixActionPayload',
    _ => 'unsupportedSystemAction',
  };
}

String _recommendedNextStepAfterSuccess(CockpitSystemControlAction action) {
  return switch (action) {
    CockpitSystemControlAction.grantPermission ||
    CockpitSystemControlAction.revokePermission ||
    CockpitSystemControlAction.resetPermission ||
    CockpitSystemControlAction.clearAppData ||
    CockpitSystemControlAction.installApp ||
    CockpitSystemControlAction.uninstallApp => 'relaunchAppThenReadState',
    _ => 'readPostActionState',
  };
}

List<String> _limitationsAfterSuccess({
  required String platform,
  required CockpitSystemControlAction action,
  required bool success,
  required List<String> limitations,
}) {
  if (!success ||
      platform.trim().toLowerCase() != 'ios' ||
      (action != CockpitSystemControlAction.grantPermission &&
          action != CockpitSystemControlAction.revokePermission &&
          action != CockpitSystemControlAction.resetPermission)) {
    return limitations;
  }
  return <String>{
    ...limitations,
    'simctl privacy may terminate the app',
  }.toList(growable: false);
}

Map<String, Object?> _macroTargetParameters(
  CockpitSystemControlActionRequest request,
) {
  final appId = request.appId?.trim();
  if (appId == null || appId.isEmpty) {
    return const <String, Object?>{};
  }
  final platform = request.platform.trim().toLowerCase();
  if (platform == 'android') {
    return <String, Object?>{'packageId': appId};
  }
  if (platform == 'ios') {
    return <String, Object?>{'appId': appId};
  }
  return <String, Object?>{'appId': appId};
}

List<String> _macroLimitations(
  List<String> limitations,
  List<Map<String, Object?>> stepResults,
) {
  final skipped = stepResults
      .where((step) => step['skipped'] == true)
      .map((step) => step['action'])
      .whereType<String>()
      .toList(growable: false);
  final failedOptional = stepResults
      .where(
        (step) =>
            step['optional'] == true &&
            step['skipped'] != true &&
            step['success'] != true,
      )
      .map((step) => step['action'])
      .whereType<String>()
      .toList(growable: false);
  if (skipped.isEmpty && failedOptional.isEmpty) {
    return limitations;
  }
  return <String>{
    ...limitations,
    if (skipped.isNotEmpty)
      'Skipped unavailable optional system actions: ${skipped.join(", ")}',
    if (failedOptional.isNotEmpty)
      'Optional system actions failed and were skipped: ${failedOptional.join(", ")}',
  }.toList(growable: false);
}

CockpitCaptureAdapter? _defaultCaptureAdapterFor(
  CockpitSystemControlActionRequest request,
) {
  final deviceId = request.deviceId;
  final appId = request.appId;
  final windowAppId = _windowAppIdFor(request);
  final wdaBaseUri = _wdaBaseUri(request.metadata);
  return switch (request.platform.trim().toLowerCase()) {
    'android' when deviceId != null && deviceId.isNotEmpty =>
      CockpitAdbCaptureAdapter(deviceId: deviceId),
    'ios'
        when deviceId != null &&
            deviceId.isNotEmpty &&
            !_looksLikeIosSimulatorDeviceId(deviceId) &&
            wdaBaseUri != null =>
      CockpitWdaCaptureAdapter(baseUri: wdaBaseUri),
    'ios' when deviceId != null && deviceId.isNotEmpty =>
      CockpitSimctlCaptureAdapter(deviceId: deviceId),
    'macos' when appId != null && appId.isNotEmpty =>
      CockpitMacosCaptureAdapter(appId: appId),
    'windows' when windowAppId != null => CockpitWindowsCaptureAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    'linux' when windowAppId != null => CockpitLinuxCaptureAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    // Web evidence captures the browser window through the host adapters.
    'web' => _hostWindowCaptureAdapterFor(request),
    _ => null,
  };
}

Uri? _wdaBaseUri(Map<String, Object?> metadata) {
  if (metadata['wdaReachable'] != true) return null;
  final value = metadata['wdaUrl'];
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.hasScheme && uri.host.isNotEmpty ? uri : null;
}

bool _looksLikeIosSimulatorDeviceId(String deviceId) =>
    deviceId.toLowerCase() == 'booted' ||
    RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    ).hasMatch(deviceId);

CockpitCaptureAdapter? _hostWindowCaptureAdapterFor(
  CockpitSystemControlActionRequest request,
) {
  final appId = request.appId;
  final windowAppId = _windowAppIdFor(request);
  return switch (Platform.operatingSystem) {
    'macos' when appId != null && appId.trim().isNotEmpty =>
      CockpitMacosCaptureAdapter(appId: appId),
    'windows' when windowAppId != null => CockpitWindowsCaptureAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    'linux' when windowAppId != null => CockpitLinuxCaptureAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    _ => null,
  };
}

CockpitRecordingAdapter? _defaultRecordingAdapterFor(
  CockpitSystemControlActionRequest request,
) {
  final deviceId = request.deviceId;
  final appId = request.appId;
  final windowAppId = _windowAppIdFor(request);
  return switch (request.platform.trim().toLowerCase()) {
    'android' when deviceId != null && deviceId.isNotEmpty =>
      CockpitAdbRecordingAdapter(deviceId: deviceId),
    'ios' when deviceId != null && deviceId.isNotEmpty =>
      CockpitSimctlRecordingAdapter(deviceId: deviceId),
    'macos' when appId != null && appId.isNotEmpty =>
      CockpitMacosRecordingAdapter(appId: appId),
    'windows' when windowAppId != null => CockpitWindowsRecordingAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    'linux' when windowAppId != null => CockpitLinuxRecordingAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    // Web evidence records the browser window through the host adapters.
    'web' => _hostWindowRecordingAdapterFor(request),
    _ => null,
  };
}

CockpitRecordingAdapter? _hostWindowRecordingAdapterFor(
  CockpitSystemControlActionRequest request,
) {
  final appId = request.appId;
  final windowAppId = _windowAppIdFor(request);
  return switch (Platform.operatingSystem) {
    'macos' when appId != null && appId.trim().isNotEmpty =>
      CockpitMacosRecordingAdapter(appId: appId),
    'windows' when windowAppId != null => CockpitWindowsRecordingAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    'linux' when windowAppId != null => CockpitLinuxRecordingAdapter(
      appId: windowAppId,
      processId: request.processId,
    ),
    _ => null,
  };
}

String? _windowAppIdFor(CockpitSystemControlActionRequest request) {
  final appId = request.appId;
  if (appId != null && appId.trim().isNotEmpty) {
    return appId;
  }
  final processId = request.processId;
  return processId == null ? null : 'pid-$processId';
}

CockpitRecordingRequest? _recordingRequestFromParameters(
  Map<String, Object?> parameters,
) {
  final purpose = cockpitReadSystemControlStringParameter(
    parameters,
    'purpose',
    allowedValues: _allowedRecordingValues('purpose'),
  );
  final name = cockpitReadSystemControlStringParameter(parameters, 'name');
  final mode = cockpitReadSystemControlStringParameter(
    parameters,
    'mode',
    allowedValues: _allowedRecordingValues('mode'),
  );
  final layer = cockpitReadSystemControlStringParameter(
    parameters,
    'layer',
    allowedValues: _allowedRecordingValues('layer'),
  );
  if (purpose.isInvalid ||
      name.isInvalid ||
      mode.isInvalid ||
      layer.isInvalid) {
    return null;
  }
  return CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.fromJson(purpose.value ?? 'acceptance'),
    name: name.value ?? 'system-recording',
    mode: CockpitRecordingMode.fromJson(mode.value ?? 'native'),
    layer: CockpitRecordingLayer.fromJson(layer.value ?? 'system'),
    allowFallback: false,
  );
}

List<String> _allowedRecordingValues(String name) {
  for (final parameter in CockpitSystemControlParameterSets.startRecording) {
    if (parameter.name == name) {
      return parameter.allowedValues;
    }
  }
  return const <String>[];
}

Future<String> _copyArtifactToOutputPath({
  required String sourcePath,
  required String outputPath,
}) async {
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  final sourceFile = File(sourcePath);
  if (sourceFile.absolute.path == outputFile.absolute.path) {
    return outputFile.path;
  }
  await sourceFile.copy(outputFile.path);
  return outputFile.path;
}

String _describeSystemControlError(Object error) {
  if (error is StateError) {
    return error.message;
  }
  if (error is FileSystemException) {
    return <String>[
      error.message,
      if (error.path != null && error.path!.isNotEmpty) error.path!,
      if (error.osError != null) '${error.osError}',
    ].join(' ');
  }
  return '$error';
}
