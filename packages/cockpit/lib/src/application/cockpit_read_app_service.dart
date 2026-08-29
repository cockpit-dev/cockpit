import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/cockpit_platform_driver_registry.dart';
import '../targets/cockpit_target_capability_support.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_read_remote_status_service.dart';
import 'cockpit_session_registry.dart';

final class CockpitReadAppRequest {
  const CockpitReadAppRequest({
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.minimal(),
    this.snapshotOptions,
    this.deadline,
  });

  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final DateTime? deadline;
}

final class CockpitReadAppResult {
  const CockpitReadAppResult({
    required this.sessionId,
    required this.transportType,
    required this.capabilities,
    required this.recordingCapabilities,
    this.selectedPlane = CockpitPlaneKind.flutterSemanticPlane,
    this.fallbackTrail = const <CockpitPlaneKind>[],
    this.recommendedNextStep = 'runNextCommand',
    this.whatMatters,
    this.app,
    this.state,
    this.lastError,
    this.currentRouteName,
    this.uiSummary,
    this.snapshot,
    this.snapshotRef,
    this.artifactDownloads = const <CockpitRemoteArtifactDownload>[],
    this.diagnostics,
    this.effectiveSnapshotOptions,
  });

  final String sessionId;
  final String transportType;
  final CockpitCapabilities capabilities;
  final CockpitRecordingCapabilities recordingCapabilities;
  final CockpitPlaneKind selectedPlane;
  final List<CockpitPlaneKind> fallbackTrail;
  final String recommendedNextStep;
  final String? whatMatters;
  final CockpitAppHandle? app;
  final String? state;
  final String? lastError;
  final String? currentRouteName;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final String? snapshotRef;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;
  final Map<String, Object?>? diagnostics;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'transportType': transportType,
    'capabilities': capabilities.toJson(),
    'recordingCapabilities': recordingCapabilities.toJson(),
    'selectedPlane': selectedPlane.name,
    'fallbackTrail': fallbackTrail.map((planeKind) => planeKind.name).toList(),
    'recommendedNextStep': recommendedNextStep,
    if (whatMatters != null) 'whatMatters': whatMatters,
    if (app != null) 'app': app!.toJson(),
    if (state != null) 'state': state,
    if (lastError != null) 'lastError': lastError,
    if (currentRouteName != null) 'currentRouteName': currentRouteName,
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
    if (diagnostics != null) 'diagnostics': diagnostics,
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
  };
}

final class CockpitReadAppService {
  CockpitReadAppService({
    CockpitReadRemoteStatusService? remoteStatusService,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitPlatformDriverRegistry? platformDriverRegistry,
    CockpitSessionRegistry? registry,
  }) : _remoteStatusService =
           remoteStatusService ?? CockpitReadRemoteStatusService(),
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _platformDriverRegistry =
           platformDriverRegistry ?? CockpitPlatformDriverRegistry();

  final CockpitReadRemoteStatusService _remoteStatusService;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitPlatformDriverRegistry _platformDriverRegistry;

  Future<CockpitReadAppResult> read(CockpitReadAppRequest request) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
    );
    final result = await _remoteStatusService.read(
      CockpitReadRemoteStatusRequest(
        baseUri: resolved.baseUri,
        sessionHandle: resolved.app?.remoteSession,
        resultProfile: request.resultProfile,
        snapshotOptions: request.snapshotOptions,
        deadline: request.deadline,
      ),
    );
    final capabilityProfile = await _resolveCapabilityProfile(
      app: resolved.app,
      capabilities: result.capabilities,
    );
    final recordingCapabilities = _normalizedRecordingCapabilities(
      recordingCapabilities: result.recordingCapabilities,
      capabilityProfile: capabilityProfile,
    );
    final normalizedCapabilityProfile = _normalizedCapabilityProfile(
      capabilityProfile: capabilityProfile,
      recordingCapabilities: recordingCapabilities,
    );
    final capabilities = _normalizedCapabilities(
      app: resolved.app,
      capabilities: result.capabilities,
      capabilityProfile: normalizedCapabilityProfile,
    );

    return CockpitReadAppResult(
      sessionId: result.sessionId,
      transportType: result.transportType,
      capabilities: capabilities,
      recordingCapabilities: recordingCapabilities,
      selectedPlane: _selectedPlaneFor(capabilities),
      fallbackTrail: _fallbackTrailFor(capabilities),
      recommendedNextStep: _recommendedNextStep(
        capabilities: capabilities,
        currentRouteName: result.currentRouteName,
        lastError: resolved.developmentRecord?.status.lastError,
        uiSummary: result.uiSummary,
      ),
      whatMatters: _whatMatters(
        capabilities: capabilities,
        currentRouteName: result.currentRouteName,
        lastError: resolved.developmentRecord?.status.lastError,
        uiSummary: result.uiSummary,
      ),
      app: resolved.app,
      state:
          resolved.developmentRecord?.status.state.jsonValue ??
          resolved.remoteRecord?.recommendedNextStep,
      lastError: resolved.developmentRecord?.status.lastError,
      currentRouteName: result.currentRouteName,
      uiSummary: result.uiSummary,
      snapshot: result.snapshot,
      snapshotRef: result.snapshotRef,
      artifactDownloads: result.artifactDownloads,
      diagnostics: null,
      effectiveSnapshotOptions: result.effectiveSnapshotOptions,
    );
  }

  Future<CockpitCapabilityProfile?> _resolveCapabilityProfile({
    required CockpitAppHandle? app,
    required CockpitCapabilities capabilities,
  }) async {
    final remoteProfile =
        capabilities.capabilityProfile ??
        _legacyCapabilityProfile(capabilities);
    if (app == null) {
      return remoteProfile;
    }

    final driver = _platformDriverRegistry.resolve(
      platform: app.platform,
      deviceId: app.deviceId,
      appId: app.platformAppId ?? app.remoteSession?.effectivePlatformAppId,
      processId: app.processId ?? app.remoteSession?.processId,
    );
    if (driver == null) {
      return remoteProfile;
    }

    return cockpitMergeTargetCapabilityProfiles(
      primary: await driver.describeCapabilities(),
      secondary: remoteProfile,
    );
  }

  static CockpitCapabilities _normalizedCapabilities({
    required CockpitAppHandle? app,
    required CockpitCapabilities capabilities,
    required CockpitCapabilityProfile? capabilityProfile,
  }) {
    final supportsHostAutomation =
        capabilities.supportsHostAutomation ||
        (capabilityProfile?.supportsSurface(CockpitSurfaceKind.hostShell) ??
            false);
    return CockpitCapabilities(
      platform: app?.platform ?? capabilities.platform,
      transportType: capabilities.transportType,
      supportsInAppControl: capabilities.supportsInAppControl,
      supportsFlutterViewCapture: capabilities.supportsFlutterViewCapture,
      supportsNativeScreenCapture: capabilities.supportsNativeScreenCapture,
      supportsHostAutomation: supportsHostAutomation,
      supportedCommands: capabilities.supportedCommands,
      supportedLocatorStrategies: capabilities.supportedLocatorStrategies,
      capabilityProfile: capabilityProfile,
    );
  }

  static CockpitRecordingCapabilities _normalizedRecordingCapabilities({
    required CockpitRecordingCapabilities recordingCapabilities,
    required CockpitCapabilityProfile? capabilityProfile,
  }) {
    final profileSupportsRecording =
        capabilityProfile != null &&
        _shouldPromoteRecordingFromProfile(capabilityProfile) &&
        capabilityProfile.supportsAction(
          CockpitActionCapability.startRecording,
        ) &&
        capabilityProfile.supportsAction(
          CockpitActionCapability.stopRecording,
        ) &&
        capabilityProfile.supportsEvidence(
          CockpitEvidenceCapability.screenRecording,
        );
    final limitations = <String>{...recordingCapabilities.recordingLimitations};
    return CockpitRecordingCapabilities(
      supportsNativeRecording:
          recordingCapabilities.supportsNativeRecording ||
          profileSupportsRecording,
      preferredAcceptanceRecordingKind:
          recordingCapabilities.preferredAcceptanceRecordingKind,
      supportedLayers: recordingCapabilities.supportedLayers,
      preferredLayer: recordingCapabilities.preferredLayer,
      recordingLimitations: limitations.toList(growable: false),
    );
  }

  static CockpitCapabilityProfile? _normalizedCapabilityProfile({
    required CockpitCapabilityProfile? capabilityProfile,
    required CockpitRecordingCapabilities recordingCapabilities,
  }) {
    if (capabilityProfile == null ||
        capabilityProfile.targetKind != CockpitTargetKind.flutterApp ||
        recordingCapabilities.supportsNativeRecording) {
      return capabilityProfile;
    }
    return CockpitCapabilityProfile(
      targetKind: capabilityProfile.targetKind,
      surfaceKinds: capabilityProfile.surfaceKinds,
      actionCapabilities: capabilityProfile.actionCapabilities
          .where(
            (capability) =>
                capability != CockpitActionCapability.startRecording &&
                capability != CockpitActionCapability.stopRecording,
          )
          .toSet(),
      evidenceCapabilities: capabilityProfile.evidenceCapabilities
          .where(
            (capability) =>
                capability != CockpitEvidenceCapability.screenRecording,
          )
          .toSet(),
      qualityFlags: capabilityProfile.qualityFlags,
    );
  }

  static bool _shouldPromoteRecordingFromProfile(
    CockpitCapabilityProfile profile,
  ) {
    return switch (profile.targetKind) {
      CockpitTargetKind.desktopApp || CockpitTargetKind.browserPage => true,
      CockpitTargetKind.flutterApp ||
      CockpitTargetKind.nativeApp ||
      CockpitTargetKind.systemSurface ||
      CockpitTargetKind.device ||
      CockpitTargetKind.hostWorkspace => false,
    };
  }

  static CockpitPlaneKind _selectedPlaneFor(CockpitCapabilities capabilities) {
    if (capabilities.supportsInAppControl) {
      return CockpitPlaneKind.flutterSemanticPlane;
    }
    if (capabilities.supportsHostAutomation) {
      return CockpitPlaneKind.hostPlane;
    }
    if (capabilities.supportsNativeScreenCapture) {
      return CockpitPlaneKind.nativeUiPlane;
    }
    return CockpitPlaneKind.deviceSystemPlane;
  }

  static List<CockpitPlaneKind> _fallbackTrailFor(
    CockpitCapabilities capabilities,
  ) {
    return switch (_selectedPlaneFor(capabilities)) {
      CockpitPlaneKind.flutterSemanticPlane => <CockpitPlaneKind>[
        CockpitPlaneKind.nativeUiPlane,
        CockpitPlaneKind.deviceSystemPlane,
      ],
      CockpitPlaneKind.hostPlane => const <CockpitPlaneKind>[],
      CockpitPlaneKind.nativeUiPlane => <CockpitPlaneKind>[
        CockpitPlaneKind.deviceSystemPlane,
      ],
      CockpitPlaneKind.deviceSystemPlane => const <CockpitPlaneKind>[],
    };
  }

  static CockpitCapabilityProfile _legacyCapabilityProfile(
    CockpitCapabilities capabilities,
  ) {
    final actionCapabilities = <CockpitActionCapability>{};
    for (final command in capabilities.supportedCommands) {
      switch (command) {
        case CockpitCommandType.tap ||
            CockpitCommandType.longPress ||
            CockpitCommandType.doubleTap:
          actionCapabilities.add(CockpitActionCapability.tap);
        case CockpitCommandType.wheel:
          actionCapabilities.add(CockpitActionCapability.scroll);
        case CockpitCommandType.enterText ||
            CockpitCommandType.focusTextInput ||
            CockpitCommandType.setTextEditingValue ||
            CockpitCommandType.sendTextInputAction ||
            CockpitCommandType.dismissKeyboard ||
            CockpitCommandType.sendKeyEvent ||
            CockpitCommandType.sendKeyDownEvent ||
            CockpitCommandType.sendKeyUpEvent:
          actionCapabilities.add(CockpitActionCapability.typeText);
        case CockpitCommandType.captureScreenshot:
          actionCapabilities.add(CockpitActionCapability.captureScreenshot);
        default:
          break;
      }
    }
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.flutterApp,
      surfaceKinds: <CockpitSurfaceKind>{
        if (capabilities.supportsInAppControl)
          CockpitSurfaceKind.flutterSemantic,
        if (capabilities.supportsNativeScreenCapture)
          CockpitSurfaceKind.nativeUi,
      },
      actionCapabilities: actionCapabilities,
      evidenceCapabilities: <CockpitEvidenceCapability>{
        if (capabilities.supportsFlutterViewCapture)
          CockpitEvidenceCapability.flutterScreenshot,
        if (capabilities.supportsNativeScreenCapture)
          CockpitEvidenceCapability.nativeScreenshot,
      },
    );
  }

  static String _recommendedNextStep({
    required CockpitCapabilities capabilities,
    required String? currentRouteName,
    required String? lastError,
    required CockpitInteractiveSnapshotSummary? uiSummary,
  }) {
    if (lastError != null && lastError.isNotEmpty) {
      return 'inspectFailureDiagnostics';
    }
    if (_shouldHintBrowserVisibilityRecovery(
      capabilities: capabilities,
      currentRouteName: currentRouteName,
      uiSummary: uiSummary,
    )) {
      return 'recoverBrowserVisibility';
    }
    if (currentRouteName != null && currentRouteName.isNotEmpty) {
      return 'runNextCommand';
    }
    return 'inspectCurrentState';
  }

  static String? _whatMatters({
    required CockpitCapabilities capabilities,
    required String? currentRouteName,
    required String? lastError,
    required CockpitInteractiveSnapshotSummary? uiSummary,
  }) {
    if (lastError != null && lastError.isNotEmpty) {
      return lastError;
    }
    if (_shouldHintBrowserVisibilityRecovery(
      capabilities: capabilities,
      currentRouteName: currentRouteName,
      uiSummary: uiSummary,
    )) {
      return 'Current route is $currentRouteName, but no visible targets were '
          'discovered. On browser pages this usually means the tab is '
          'backgrounded, throttled, or still reconnecting.';
    }
    if (currentRouteName != null && currentRouteName.isNotEmpty) {
      return 'Current route is $currentRouteName.';
    }
    return null;
  }

  static bool _shouldHintBrowserVisibilityRecovery({
    required CockpitCapabilities capabilities,
    required String? currentRouteName,
    required CockpitInteractiveSnapshotSummary? uiSummary,
  }) {
    final profile = capabilities.capabilityProfile;
    return currentRouteName != null &&
        currentRouteName.isNotEmpty &&
        uiSummary != null &&
        uiSummary.visibleTargetCount == 0 &&
        profile?.targetKind == CockpitTargetKind.browserPage;
  }
}
