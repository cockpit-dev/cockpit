import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/cockpit_platform_driver_registry.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../targets/cockpit_target_capability_support.dart';
import '../targets/cockpit_target_handle.dart';
import '../targets/cockpit_target_reference_resolver.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_read_app_service.dart';

typedef CockpitReadTargetFunction =
    Future<CockpitReadTargetResult> Function(CockpitReadTargetRequest request);
typedef CockpitReadFlutterTargetFunction =
    Future<CockpitReadAppResult> Function(CockpitReadAppRequest request);

final class CockpitReadTargetRequest {
  const CockpitReadTargetRequest({
    this.target,
    this.targetHandlePath,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.minimal(),
    this.snapshotOptions,
    this.deadline,
  });

  final CockpitTargetHandle? target;
  final String? targetHandlePath;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final DateTime? deadline;
}

final class CockpitReadTargetResult {
  const CockpitReadTargetResult({
    required this.target,
    required this.capabilityProfile,
    required this.foregroundSurface,
    required this.selectedPlane,
    required this.fallbackTrail,
    required this.recommendedNextStep,
    this.whatMatters,
    this.sessionId,
    this.transportType,
    this.currentRouteName,
    this.uiSummary,
    this.snapshot,
    this.snapshotRef,
    this.effectiveSnapshotOptions,
  });

  final CockpitTargetHandle target;
  final CockpitCapabilityProfile capabilityProfile;
  final CockpitSurfaceKind foregroundSurface;
  final CockpitPlaneKind selectedPlane;
  final List<CockpitPlaneKind> fallbackTrail;
  final String recommendedNextStep;
  final String? whatMatters;
  final String? sessionId;
  final String? transportType;
  final String? currentRouteName;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final String? snapshotRef;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target.toJson(),
    'capabilityProfile': capabilityProfile.toJson(),
    'foregroundSurface': foregroundSurface.name,
    'selectedPlane': selectedPlane.name,
    'fallbackTrail': fallbackTrail.map((planeKind) => planeKind.name).toList(),
    'recommendedNextStep': recommendedNextStep,
    if (whatMatters != null) 'whatMatters': whatMatters,
    if (sessionId != null) 'sessionId': sessionId,
    if (transportType != null) 'transportType': transportType,
    if (currentRouteName != null) 'currentRouteName': currentRouteName,
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
  };
}

final class CockpitReadTargetService {
  CockpitReadTargetService({
    CockpitReadTargetFunction? readTarget,
    CockpitReadAppService? readAppService,
    CockpitReadFlutterTargetFunction? readFlutterTarget,
    CockpitTargetReferenceResolver? targetReferenceResolver,
    CockpitPlatformDriverRegistry? platformDriverRegistry,
  }) : _readTargetOverride = readTarget,
       _readFlutterTarget =
           readFlutterTarget ??
           (readAppService ?? CockpitReadAppService()).read,
       _targetReferenceResolver =
           targetReferenceResolver ?? CockpitTargetReferenceResolver(),
       _platformDriverRegistry =
           platformDriverRegistry ?? CockpitPlatformDriverRegistry();

  final CockpitReadTargetFunction? _readTargetOverride;
  final CockpitReadFlutterTargetFunction _readFlutterTarget;
  final CockpitTargetReferenceResolver _targetReferenceResolver;
  final CockpitPlatformDriverRegistry _platformDriverRegistry;

  Future<CockpitReadTargetResult> read(CockpitReadTargetRequest request) async {
    final override = _readTargetOverride;
    if (override != null) {
      return override(request);
    }

    final resolved = await _targetReferenceResolver.resolve(
      target: request.target,
      targetHandlePath: request.targetHandlePath,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
    );
    final target = resolved.target;
    if (target == null) {
      throw CockpitApplicationServiceException(
        code: 'missingTargetReference',
        message: 'read-target requires a resolved target handle.',
      );
    }

    final capabilityProfile = await _resolveCapabilityProfile(target);
    if (_usesFlutterRemoteRead(target)) {
      final appResult = await _readFlutterTarget(
        CockpitReadAppRequest(
          app: resolved.app ?? _appFromTarget(target),
          baseUri: resolved.baseUri,
          resultProfile: request.resultProfile,
          snapshotOptions: request.snapshotOptions,
          deadline: request.deadline,
        ),
      );
      final remoteProfile =
          appResult.capabilities.capabilityProfile ??
          _legacyCapabilityProfile(appResult.capabilities);
      final mergedCapabilityProfile = cockpitMergeTargetCapabilityProfiles(
        primary: capabilityProfile,
        secondary: remoteProfile,
      );
      final normalizedMergedProfile = _normalizedCapabilityProfile(
        capabilityProfile: mergedCapabilityProfile,
        recordingCapabilities: appResult.recordingCapabilities,
      );
      return CockpitReadTargetResult(
        target: target.copyWith(capabilityProfile: normalizedMergedProfile),
        capabilityProfile: normalizedMergedProfile,
        foregroundSurface: cockpitForegroundSurfaceForTargetProfile(
          normalizedMergedProfile,
        ),
        selectedPlane: appResult.selectedPlane,
        fallbackTrail: appResult.fallbackTrail.isEmpty
            ? cockpitFallbackTrailForProfile(
                profile: normalizedMergedProfile,
                selectedPlane: appResult.selectedPlane,
              )
            : appResult.fallbackTrail,
        recommendedNextStep: appResult.recommendedNextStep,
        whatMatters: _whatMattersForFlutterRead(
          base:
              appResult.whatMatters ??
              cockpitWhatMattersForProfile(normalizedMergedProfile),
          recordingCapabilities: appResult.recordingCapabilities,
          capabilityProfile: mergedCapabilityProfile,
          normalizedCapabilityProfile: normalizedMergedProfile,
        ),
        sessionId: appResult.sessionId,
        transportType: appResult.transportType,
        currentRouteName: appResult.currentRouteName,
        uiSummary: appResult.uiSummary,
        snapshot: appResult.snapshot,
        snapshotRef: appResult.snapshotRef,
        effectiveSnapshotOptions: appResult.effectiveSnapshotOptions,
      );
    }

    return CockpitReadTargetResult(
      target: target.copyWith(capabilityProfile: capabilityProfile),
      capabilityProfile: capabilityProfile,
      foregroundSurface: cockpitForegroundSurfaceForTargetProfile(
        capabilityProfile,
      ),
      selectedPlane: cockpitPlaneForSurface(
        cockpitForegroundSurfaceForTargetProfile(capabilityProfile),
      ),
      fallbackTrail: cockpitFallbackTrailForProfile(
        profile: capabilityProfile,
        selectedPlane: cockpitPlaneForSurface(
          cockpitForegroundSurfaceForTargetProfile(capabilityProfile),
        ),
      ),
      recommendedNextStep: cockpitRecommendedNextStepForProfile(
        capabilityProfile,
      ),
      whatMatters: cockpitWhatMattersForProfile(capabilityProfile),
      uiSummary: cockpitInteractiveStaticSummaryForProfile(
        request.resultProfile,
      ),
    );
  }

  Future<CockpitCapabilityProfile> _resolveCapabilityProfile(
    CockpitTargetHandle target,
  ) async {
    final existing = target.capabilityProfile;
    final remoteSession = _targetRemoteSession(target);
    final driver = _platformDriverRegistry.resolve(
      platform: target.platform,
      deviceId: target.deviceId,
      appId: _targetPlatformAppId(target, remoteSession: remoteSession),
      processId: _targetProcessId(target, remoteSession: remoteSession),
    );
    if (existing != null && driver == null) {
      return existing;
    }
    if (driver == null) {
      throw CockpitApplicationServiceException(
        code: 'unsupportedPlatform',
        message: 'No platform driver is available for this target.',
        details: <String, Object?>{'platform': target.platform},
      );
    }
    final described = await driver.describeCapabilities();
    if (existing == null) {
      return described;
    }
    return cockpitMergeTargetCapabilityProfiles(
      primary: existing,
      secondary: described,
    );
  }

  bool _usesFlutterRemoteRead(CockpitTargetHandle target) {
    if (target.targetKind == CockpitTargetKind.flutterApp ||
        target.targetKind == CockpitTargetKind.desktopApp) {
      return true;
    }
    return target.targetKind == CockpitTargetKind.browserPage &&
        target.metadata['appId'] is String &&
        '${target.metadata['appId']}'.trim().isNotEmpty;
  }

  CockpitAppHandle _appFromTarget(CockpitTargetHandle target) {
    final remoteSession = _targetRemoteSession(target);
    final metadataAppId = target.metadata['appId'] as String?;
    return CockpitAppHandle(
      appId: (metadataAppId != null && metadataAppId.trim().isNotEmpty)
          ? metadataAppId
          : target.targetId,
      mode: target.metadata['appMode'] == CockpitAppMode.development.jsonValue
          ? CockpitAppMode.development
          : CockpitAppMode.automation,
      platform: target.platform,
      deviceId: target.deviceId,
      projectDir: target.projectDir,
      target: target.target,
      baseUrl: target.connection.baseUrl,
      launchedAt: target.launchedAt,
      platformAppId: _targetPlatformAppId(target, remoteSession: remoteSession),
      processId: _targetProcessId(target, remoteSession: remoteSession),
      remoteSession: remoteSession,
    );
  }

  String? _targetPlatformAppId(
    CockpitTargetHandle target, {
    CockpitRemoteSessionHandle? remoteSession,
  }) {
    final explicit = target.metadata['platformAppId'] as String?;
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit;
    }
    return remoteSession?.effectivePlatformAppId;
  }

  int? _targetProcessId(
    CockpitTargetHandle target, {
    CockpitRemoteSessionHandle? remoteSession,
  }) {
    final value = target.metadata['processId'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String && value.isNotEmpty) {
      return int.tryParse(value);
    }
    return remoteSession?.processId;
  }

  CockpitRemoteSessionHandle? _targetRemoteSession(CockpitTargetHandle target) {
    final value = target.metadata['remoteSession'];
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return CockpitRemoteSessionHandle.fromJson(
      Map<String, Object?>.from(value),
    );
  }

  CockpitCapabilityProfile _normalizedCapabilityProfile({
    required CockpitCapabilityProfile capabilityProfile,
    required CockpitRecordingCapabilities recordingCapabilities,
  }) {
    if (capabilityProfile.targetKind != CockpitTargetKind.flutterApp ||
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

  String? _whatMattersForFlutterRead({
    required String? base,
    required CockpitRecordingCapabilities recordingCapabilities,
    required CockpitCapabilityProfile capabilityProfile,
    required CockpitCapabilityProfile normalizedCapabilityProfile,
  }) {
    if (recordingCapabilities.supportsNativeRecording ||
        !capabilityProfile.supportsEvidence(
          CockpitEvidenceCapability.screenRecording,
        ) ||
        normalizedCapabilityProfile.supportsEvidence(
          CockpitEvidenceCapability.screenRecording,
        )) {
      return base;
    }

    final limitation = recordingCapabilities.recordingLimitations
        .where((entry) => entry.trim().isNotEmpty)
        .join(' ');
    final recordingHint = limitation.isEmpty
        ? 'Native recording is unavailable for this target right now.'
        : 'Native recording is unavailable for this target right now: '
              '$limitation';
    if (base == null || base.trim().isEmpty) {
      return recordingHint;
    }
    return '$base $recordingHint';
  }

  static CockpitCapabilityProfile _legacyCapabilityProfile(
    CockpitCapabilities capabilities,
  ) {
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.flutterApp,
      surfaceKinds: <CockpitSurfaceKind>{
        if (capabilities.supportsInAppControl)
          CockpitSurfaceKind.flutterSemantic,
        CockpitSurfaceKind.nativeUi,
      },
      actionCapabilities: <CockpitActionCapability>{
        CockpitActionCapability.tap,
        CockpitActionCapability.typeText,
        if (capabilities.supportsNativeScreenCapture)
          CockpitActionCapability.captureScreenshot,
      },
      evidenceCapabilities: <CockpitEvidenceCapability>{
        if (capabilities.supportsFlutterViewCapture)
          CockpitEvidenceCapability.flutterScreenshot,
        if (capabilities.supportsNativeScreenCapture)
          CockpitEvidenceCapability.nativeScreenshot,
      },
    );
  }
}
