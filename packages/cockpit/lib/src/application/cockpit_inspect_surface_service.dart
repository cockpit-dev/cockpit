import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:collection/collection.dart';

import '../capture/cockpit_capture_strategy_resolver.dart';
import '../platform/cockpit_platform_driver_registry.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../targets/cockpit_target_capability_support.dart';
import '../targets/cockpit_target_handle.dart';
import '../targets/cockpit_target_reference_resolver.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_inspect_ui_service.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';

typedef CockpitInspectSurfaceFunction =
    Future<CockpitInspectSurfaceResult> Function(
      CockpitInspectSurfaceRequest request,
    );
typedef CockpitInspectFlutterSurfaceFunction =
    Future<CockpitInspectUiResult> Function(CockpitInspectUiRequest request);

final class CockpitInspectSurfaceRequest {
  const CockpitInspectSurfaceRequest({
    this.target,
    this.targetHandlePath,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.inspect(),
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
  });

  final CockpitTargetHandle? target;
  final String? targetHandlePath;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
}

final class CockpitInspectSurfaceResult {
  const CockpitInspectSurfaceResult({
    required this.target,
    required this.capabilityProfile,
    required this.surfaceKind,
    required this.selectedPlane,
    required this.recommendedNextStep,
    required this.diagnosticLevel,
    required this.truncated,
    this.routeName,
    this.uiSummary,
    this.snapshot,
    this.diagnostics,
    this.delta,
    this.snapshotRef,
    this.artifactDownloads = const <CockpitRemoteArtifactDownload>[],
    this.artifactSourcePaths = const <String, String>{},
    this.effectiveSnapshotOptions,
    this.locator,
  });

  final CockpitTargetHandle target;
  final CockpitCapabilityProfile capabilityProfile;
  final CockpitSurfaceKind surfaceKind;
  final CockpitPlaneKind selectedPlane;
  final String recommendedNextStep;
  final String? routeName;
  final String diagnosticLevel;
  final bool truncated;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final Map<String, Object?>? diagnostics;
  final CockpitInteractiveSnapshotDelta? delta;
  final String? snapshotRef;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;
  final Map<String, String> artifactSourcePaths;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;
  final Map<String, Object?>? locator;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target.toJson(),
    'capabilityProfile': capabilityProfile.toJson(),
    'surfaceKind': surfaceKind.name,
    'selectedPlane': selectedPlane.name,
    'recommendedNextStep': recommendedNextStep,
    if (routeName != null) 'routeName': routeName,
    'diagnosticLevel': diagnosticLevel,
    'truncated': truncated,
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (diagnostics != null) 'diagnostics': diagnostics,
    if (delta != null) 'delta': delta!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
    if (artifactSourcePaths.isNotEmpty)
      'artifactSourcePaths': artifactSourcePaths,
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
    if (locator != null) 'locator': locator,
  };
}

final class CockpitInspectSurfaceService {
  CockpitInspectSurfaceService({
    CockpitInspectSurfaceFunction? inspectSurface,
    CockpitInspectUiService? inspectUiService,
    CockpitInspectFlutterSurfaceFunction? inspectFlutterSurface,
    CockpitTargetReferenceResolver? targetReferenceResolver,
    CockpitPlatformDriverRegistry? platformDriverRegistry,
    CockpitCaptureStrategyResolver captureStrategyResolver =
        const CockpitCaptureStrategyResolver(),
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
  }) : _inspectSurfaceOverride = inspectSurface,
       _inspectFlutterSurface =
           inspectFlutterSurface ??
           (inspectUiService ?? CockpitInspectUiService()).inspect,
       _targetReferenceResolver =
           targetReferenceResolver ?? CockpitTargetReferenceResolver(),
       _platformDriverRegistry =
           platformDriverRegistry ?? CockpitPlatformDriverRegistry(),
       _captureStrategyResolver = captureStrategyResolver,
       _artifactTempFileFactory = artifactTempFileFactory;

  final CockpitInspectSurfaceFunction? _inspectSurfaceOverride;
  final CockpitInspectFlutterSurfaceFunction _inspectFlutterSurface;
  final CockpitTargetReferenceResolver _targetReferenceResolver;
  final CockpitPlatformDriverRegistry _platformDriverRegistry;
  final CockpitCaptureStrategyResolver _captureStrategyResolver;
  final CockpitRemoteArtifactTempFileFactory? _artifactTempFileFactory;

  Future<CockpitInspectSurfaceResult> inspect(
    CockpitInspectSurfaceRequest request,
  ) async {
    final override = _inspectSurfaceOverride;
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
        message: 'inspect-surface requires a resolved target handle.',
      );
    }

    final capabilityProfile = await _resolveCapabilityProfile(target);
    final flutterInspectResult = await _tryFlutterRemoteInspect(
      request: request,
      target: target,
      resolved: resolved,
      capabilityProfile: capabilityProfile,
    );
    if (flutterInspectResult != null) {
      return flutterInspectResult;
    }

    final fallbackApp = resolved.app ?? _appFromTarget(target);
    final captureAdapter = _captureStrategyResolver.resolve(
      platform: target.platform,
      client: CockpitRemoteSessionClient(
        baseUri: resolved.baseUri,
        artifactTempFileFactory: _artifactTempFileFactory,
      ),
      platformAppId: fallbackApp.platformAppId,
      processId: fallbackApp.processId,
      sessionHandle: fallbackApp.remoteSession,
      androidDeviceId:
          request.androidDeviceId ??
          (target.platform == 'android' ? target.deviceId : null),
      iosDeviceId: target.platform == 'ios' ? target.deviceId : null,
      artifactTempFileFactory: _artifactTempFileFactory,
    );
    final capture = await captureAdapter.capture(
      CockpitCommand(
        commandId: 'inspect-surface-capture',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'inspect_surface_${target.platform}',
        ),
      ),
    );
    if (!capture.result.success) {
      throw CockpitApplicationServiceException(
        code: 'surfaceCaptureFailed',
        message:
            capture.result.error?.message ??
            'Unable to capture the current target surface.',
        details: capture.result.error?.details ?? const <String, Object?>{},
      );
    }
    final artifactDescriptors = _artifactDescriptorsFromExecution(capture);
    final snapshotRef =
        capture.artifactSourcePaths.values.firstOrNull ??
        artifactDescriptors.firstOrNull?.relativePath;
    final selectedPlane = cockpitPlaneForSurface(
      cockpitForegroundSurfaceForTargetProfile(capabilityProfile),
    );
    return CockpitInspectSurfaceResult(
      target: target.copyWith(capabilityProfile: capabilityProfile),
      capabilityProfile: capabilityProfile,
      surfaceKind: cockpitForegroundSurfaceForTargetProfile(capabilityProfile),
      selectedPlane: selectedPlane,
      recommendedNextStep: 'reviewCapture',
      diagnosticLevel: request.resultProfile.snapshotProfile.jsonValue,
      truncated: false,
      uiSummary: cockpitInteractiveStaticSummaryForProfile(
        request.resultProfile,
      ),
      diagnostics: <String, Object?>{
        'capture': CockpitInteractiveCommandCore.fromResult(
          capture.result,
        ).toJson(),
        'artifacts': artifactDescriptors
            .map((artifact) => artifact.toJson())
            .toList(growable: false),
      },
      snapshotRef: snapshotRef,
    );
  }

  static CockpitCapabilityProfile _legacyCapabilityProfile() {
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.flutterApp,
      surfaceKinds: <CockpitSurfaceKind>{
        CockpitSurfaceKind.flutterSemantic,
        CockpitSurfaceKind.nativeUi,
      },
      actionCapabilities: <CockpitActionCapability>{
        CockpitActionCapability.tap,
        CockpitActionCapability.typeText,
        CockpitActionCapability.captureScreenshot,
      },
      evidenceCapabilities: <CockpitEvidenceCapability>{
        CockpitEvidenceCapability.flutterScreenshot,
        CockpitEvidenceCapability.nativeScreenshot,
      },
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

  bool _shouldAttemptFlutterRemoteInspect(CockpitTargetHandle target) {
    return target.targetKind == CockpitTargetKind.flutterApp ||
        target.targetKind == CockpitTargetKind.desktopApp ||
        (target.targetKind == CockpitTargetKind.browserPage &&
            target.metadata['appId'] is String &&
            '${target.metadata['appId']}'.trim().isNotEmpty);
  }

  Future<CockpitInspectSurfaceResult?> _tryFlutterRemoteInspect({
    required CockpitInspectSurfaceRequest request,
    required CockpitTargetHandle target,
    required CockpitResolvedTargetReference resolved,
    required CockpitCapabilityProfile capabilityProfile,
  }) async {
    if (!_shouldAttemptFlutterRemoteInspect(target)) {
      return null;
    }

    try {
      final inspectResult = await _inspectFlutterSurface(
        CockpitInspectUiRequest(
          app: resolved.app ?? _appFromTarget(target),
          baseUri: resolved.baseUri,
          resultProfile: request.resultProfile,
          snapshotOptions: request.snapshotOptions,
          compareAgainstSnapshotRef: request.compareAgainstSnapshotRef,
        ),
      );
      final mergedProfile = cockpitMergeTargetCapabilityProfiles(
        primary: capabilityProfile,
        secondary: _legacyCapabilityProfile(),
      );
      return CockpitInspectSurfaceResult(
        target: target.copyWith(capabilityProfile: mergedProfile),
        capabilityProfile: mergedProfile,
        surfaceKind: cockpitForegroundSurfaceForTargetProfile(mergedProfile),
        selectedPlane: CockpitPlaneKind.flutterSemanticPlane,
        recommendedNextStep: 'runNextCommand',
        routeName: inspectResult.routeName,
        diagnosticLevel: inspectResult.diagnosticLevel,
        truncated: inspectResult.truncated,
        uiSummary: inspectResult.uiSummary,
        snapshot: inspectResult.snapshot,
        diagnostics: inspectResult.diagnostics,
        delta: inspectResult.delta,
        snapshotRef: inspectResult.snapshotRef,
        artifactDownloads: inspectResult.artifactDownloads,
        artifactSourcePaths: inspectResult.artifactSourcePaths,
        effectiveSnapshotOptions: inspectResult.effectiveSnapshotOptions,
        locator: inspectResult.locator,
      );
    } on Object catch (error) {
      if (target.targetKind == CockpitTargetKind.flutterApp ||
          !_isRecoverableFlutterInspectFailure(error)) {
        rethrow;
      }
      return null;
    }
  }

  bool _isRecoverableFlutterInspectFailure(Object error) {
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return true;
    }
    return error is CockpitApplicationServiceException &&
        error.code == 'remoteUnavailable';
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

  List<CockpitInteractiveArtifactDescriptor> _artifactDescriptorsFromExecution(
    CockpitCommandExecution execution,
  ) {
    return execution.result.artifacts
        .map(
          (artifact) => CockpitInteractiveArtifactDescriptor(
            role: artifact.role,
            relativePath: artifact.relativePath,
            sourcePath: execution.artifactSourcePaths[artifact.relativePath],
          ),
        )
        .toList(growable: false);
  }
}
