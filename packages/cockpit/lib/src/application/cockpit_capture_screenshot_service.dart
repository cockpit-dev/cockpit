import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../capture/cockpit_capture_strategy_resolver.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_run_command_service.dart';
import 'cockpit_session_registry.dart';

final class CockpitCaptureScreenshotRequest {
  const CockpitCaptureScreenshotRequest({
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.iosDeviceId,
    this.iosWdaBaseUri,
    this.name = 'screenshot',
    this.reason = CockpitScreenshotReason.acceptance,
    this.includeSnapshot = false,
    this.attachToStep = true,
    this.captureProfile,
    this.allowFallback,
    this.resultProfile = const CockpitInteractiveResultProfile.standard(),
    this.defaultCommandTimeout = const Duration(seconds: 30),
  });

  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final Uri? iosWdaBaseUri;
  final String name;
  final CockpitScreenshotReason reason;
  final bool includeSnapshot;
  final bool attachToStep;
  final CockpitCaptureProfile? captureProfile;
  final bool? allowFallback;
  final CockpitInteractiveResultProfile resultProfile;
  final Duration defaultCommandTimeout;
}

typedef CockpitCaptureScreenshotResult = CockpitRunCommandResult;

typedef CockpitCaptureScreenshotRunCommand =
    Future<CockpitRunCommandResult> Function(CockpitRunCommandRequest request);

final class CockpitCaptureScreenshotService {
  CockpitCaptureScreenshotService({
    CockpitRunCommandService? runCommandService,
    CockpitCaptureScreenshotRunCommand? runCommand,
    CockpitCaptureStrategyResolver captureStrategyResolver =
        const CockpitCaptureStrategyResolver(),
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitSessionRegistry? registry,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
  }) : _runCommand =
           runCommand ?? (runCommandService ?? CockpitRunCommandService()).run,
       _captureStrategyResolver = captureStrategyResolver,
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _artifactTempFileFactory = artifactTempFileFactory;

  final CockpitCaptureScreenshotRunCommand _runCommand;
  final CockpitCaptureStrategyResolver _captureStrategyResolver;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitRemoteArtifactTempFileFactory? _artifactTempFileFactory;

  Future<CockpitCaptureScreenshotResult> capture(
    CockpitCaptureScreenshotRequest request,
  ) async {
    final trimmedName = request.name.trim();
    final name = trimmedName.isEmpty ? 'screenshot' : trimmedName;
    final command = CockpitCommand(
      commandId: 'capture-screenshot',
      commandType: CockpitCommandType.captureScreenshot,
      screenshotRequest: CockpitScreenshotRequest(
        reason: request.reason,
        name: name,
        includeSnapshot: request.includeSnapshot,
        attachToStep: request.attachToStep,
        profile: request.captureProfile,
        allowFallback: request.allowFallback,
      ),
    );

    if (_shouldTrySystemCapture(request)) {
      final resolved = await _resolveForSystemCapture(request);
      final app = resolved.app;
      final platform = _resolvedPlatform(
        app: app,
        androidDeviceId: request.androidDeviceId,
        iosDeviceId: request.iosDeviceId,
      );
      if (platform != null && platform.isNotEmpty) {
        final captureAdapter = _captureStrategyResolver.resolve(
          platform: platform,
          client: CockpitRemoteSessionClient(
            baseUri: resolved.baseUri,
            artifactTempFileFactory: _artifactTempFileFactory,
          ),
          platformAppId:
              app?.platformAppId ?? app?.remoteSession?.effectivePlatformAppId,
          processId: app?.processId ?? app?.remoteSession?.processId,
          sessionHandle: app?.remoteSession,
          deviceId: app?.deviceId,
          androidDeviceId:
              request.androidDeviceId ??
              (app?.platform == 'android' ? app?.deviceId : null),
          iosDeviceId:
              request.iosDeviceId ??
              (app?.platform == 'ios' ? app?.deviceId : null),
          iosWdaBaseUri: request.iosWdaBaseUri,
        );
        final execution = await captureAdapter.capture(command);
        return _interactiveResultFromExecution(
          execution,
          resultProfile: request.resultProfile,
        );
      }
    }

    return _runCommand(
      CockpitRunCommandRequest(
        appId: request.appId,
        app: request.app,
        appHandlePath: request.appHandlePath,
        baseUri: request.baseUri,
        androidDeviceId: request.androidDeviceId,
        iosDeviceId: request.iosDeviceId,
        command: command,
        resultProfile: request.resultProfile,
        defaultCommandTimeout: request.defaultCommandTimeout,
      ),
    );
  }

  Future<CockpitResolvedAppReference> _resolveForSystemCapture(
    CockpitCaptureScreenshotRequest request,
  ) {
    return _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
  }

  bool _shouldTrySystemCapture(CockpitCaptureScreenshotRequest request) {
    return request.app != null ||
        (request.appId != null && request.appId!.isNotEmpty) ||
        (request.appHandlePath != null && request.appHandlePath!.isNotEmpty) ||
        (request.baseUri != null &&
            ((request.androidDeviceId != null &&
                    request.androidDeviceId!.isNotEmpty) ||
                (request.iosDeviceId != null &&
                    request.iosDeviceId!.isNotEmpty)));
  }

  String? _resolvedPlatform({
    required CockpitAppHandle? app,
    required String? androidDeviceId,
    required String? iosDeviceId,
  }) {
    final appPlatform = app?.platform ?? app?.remoteSession?.platform;
    if (appPlatform != null && appPlatform.isNotEmpty) {
      return appPlatform;
    }
    if (iosDeviceId != null && iosDeviceId.isNotEmpty) {
      return 'ios';
    }
    if (androidDeviceId != null && androidDeviceId.isNotEmpty) {
      return 'android';
    }
    return null;
  }

  CockpitCaptureScreenshotResult _interactiveResultFromExecution(
    CockpitCommandExecution execution, {
    required CockpitInteractiveResultProfile resultProfile,
  }) {
    return CockpitCaptureScreenshotResult(
      command: CockpitInteractiveCommandCore.fromResult(execution.result),
      artifacts: cockpitInteractiveArtifactsFromExecution(
        execution,
        resultProfile.artifacts,
      ),
      selectedPlane: switch (execution.result.resolvedCaptureKind) {
        CockpitCaptureKind.hostSystem => CockpitPlaneKind.deviceSystemPlane,
        CockpitCaptureKind.appNative ||
        CockpitCaptureKind.nativeAcceptance => CockpitPlaneKind.nativeUiPlane,
        CockpitCaptureKind.flutterView => CockpitPlaneKind.flutterSemanticPlane,
        null =>
          execution.result.degradationReason?.startsWith('hostCapture') == true
              ? CockpitPlaneKind.deviceSystemPlane
              : CockpitPlaneKind.flutterSemanticPlane,
      },
      fallbackTrail: cockpitCaptureFallbackTrailFor(execution.result),
      recommendedNextStep: execution.result.success
          ? 'reviewCapturedEvidence'
          : 'inspectFailureDiagnostics',
      changed: execution.result.changed,
      whatMatters:
          execution.result.degradationReason ?? execution.result.error?.message,
      snapshot:
          resultProfile.emitsInlineSnapshot && execution.result.snapshot != null
          ? CockpitSnapshot.fromJson(execution.result.snapshot!)
          : null,
    );
  }
}
