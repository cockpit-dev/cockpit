import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../platform/cockpit_platform_driver_registry.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../targets/cockpit_target_handle.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_compact_json.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_launch_app_service.dart';
import 'cockpit_read_app_service.dart';

typedef CockpitLaunchTargetFunction =
    Future<CockpitLaunchTargetResult> Function(
      CockpitLaunchTargetRequest request,
    );
typedef CockpitLaunchFlutterAppTargetFunction =
    Future<CockpitLaunchAppResult> Function(CockpitLaunchAppRequest request);
typedef CockpitReadLaunchedAppFunction =
    Future<CockpitReadAppResult> Function(CockpitReadAppRequest request);

final class CockpitLaunchTargetRequest {
  const CockpitLaunchTargetRequest({
    required this.projectDir,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    this.target,
    this.flavor,
    this.targetKind = CockpitTargetKind.flutterApp,
    this.mode = CockpitAppMode.development,
    this.launchTimeout = const Duration(seconds: 120),
    this.allowSessionPortFallback = true,
    this.authPassword = '',
    this.targetHandlePath,
    this.launchConfiguration = CockpitFlutterLaunchConfiguration.empty,
  });

  final String projectDir;
  final String? target;
  final String? flavor;
  final String platform;
  final String deviceId;
  final int sessionPort;
  final CockpitTargetKind targetKind;
  final CockpitAppMode mode;
  final Duration launchTimeout;
  final bool allowSessionPortFallback;
  final String authPassword;
  final String? targetHandlePath;
  final CockpitFlutterLaunchConfiguration launchConfiguration;
}

final class CockpitLaunchTargetResult {
  const CockpitLaunchTargetResult({
    required this.target,
    this.targetJsonPath,
    this.app,
    this.recommendedNextStep,
    this.whatMatters,
  });

  final CockpitTargetHandle target;
  final String? targetJsonPath;
  final CockpitAppHandle? app;
  final String? recommendedNextStep;
  final String? whatMatters;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target.toJson(),
    if (targetJsonPath != null) 'targetJsonPath': targetJsonPath,
    if (app != null) 'app': app!.toJson(),
    if (recommendedNextStep != null) 'recommendedNextStep': recommendedNextStep,
    if (whatMatters != null) 'whatMatters': whatMatters,
  };
}

final class CockpitLaunchTargetService {
  CockpitLaunchTargetService({
    CockpitLaunchTargetFunction? launchTarget,
    CockpitLaunchAppService? launchAppService,
    CockpitLaunchFlutterAppTargetFunction? launchFlutterApp,
    CockpitReadAppService? readAppService,
    CockpitReadLaunchedAppFunction? readApp,
    CockpitPlatformDriverRegistry? platformDriverRegistry,
  }) : _launchTargetOverride = launchTarget,
       _launchFlutterApp =
           launchFlutterApp ??
           (launchAppService ?? CockpitLaunchAppService()).launch,
       _readApp = readApp ?? (readAppService ?? CockpitReadAppService()).read,
       _platformDriverRegistry =
           platformDriverRegistry ?? CockpitPlatformDriverRegistry();

  final CockpitLaunchTargetFunction? _launchTargetOverride;
  final CockpitLaunchFlutterAppTargetFunction _launchFlutterApp;
  final CockpitReadLaunchedAppFunction _readApp;
  final CockpitPlatformDriverRegistry _platformDriverRegistry;

  Future<CockpitLaunchTargetResult> launch(
    CockpitLaunchTargetRequest request,
  ) async {
    final override = _launchTargetOverride;
    if (override != null) {
      return override(request);
    }

    final capabilityProfile = await _resolveCapabilityProfile(
      platform: request.platform,
      deviceId: request.deviceId,
    );
    final normalizedTargetKind = _normalizeTargetKind(
      requestedTargetKind: request.targetKind,
      capabilityProfile: capabilityProfile,
    );

    if (!_isLaunchableTargetKind(normalizedTargetKind)) {
      throw CockpitApplicationServiceException(
        code: 'unsupportedTargetKind',
        message: 'launch-target cannot directly launch this target kind.',
        details: <String, Object?>{
          'targetKind': normalizedTargetKind.name,
          'platform': request.platform,
          'recommendedNextStep': 'createTargetHandleExternally',
        },
      );
    }

    final appResult = await _launchFlutterApp(
      CockpitLaunchAppRequest(
        projectDir: request.projectDir,
        target: request.target,
        flavor: request.flavor,
        platform: request.platform,
        deviceId: request.deviceId,
        sessionPort: request.sessionPort,
        mode: request.mode,
        launchTimeout: request.launchTimeout,
        allowSessionPortFallback: request.allowSessionPortFallback,
        authPassword: request.authPassword,
        launchConfiguration: request.launchConfiguration,
      ),
    );
    final launchedProfile = await _resolveLaunchedProfile(
      app: appResult.app,
      targetKind: normalizedTargetKind,
    );
    final target = CockpitTargetHandle.fromAppHandle(appResult.app).copyWith(
      targetKind: normalizedTargetKind,
      capabilityProfile: launchedProfile.capabilityProfile,
    );
    final targetJsonPath = await _persistTargetIfRequested(
      path: request.targetHandlePath,
      target: target,
    );
    return CockpitLaunchTargetResult(
      target: target,
      targetJsonPath: targetJsonPath,
      app: appResult.app,
      recommendedNextStep: launchedProfile.recommendedNextStep,
      whatMatters: launchedProfile.whatMatters,
    );
  }

  Future<String?> _persistTargetIfRequested({
    required String? path,
    required CockpitTargetHandle target,
  }) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(cockpitPrettyJsonText(target.toJson()));
    return p.normalize(file.path);
  }

  Future<CockpitCapabilityProfile> _resolveCapabilityProfile({
    required String platform,
    required String deviceId,
    String? appId,
    int? processId,
  }) async {
    final driver = _platformDriverRegistry.resolve(
      platform: platform,
      deviceId: deviceId,
      appId: appId,
      processId: processId,
    );
    if (driver == null) {
      throw CockpitApplicationServiceException(
        code: 'unsupportedPlatform',
        message: 'launch-target does not support this platform.',
        details: <String, Object?>{'platform': platform},
      );
    }
    return driver.describeCapabilities();
  }

  Future<_LaunchedTargetProfile> _resolveLaunchedProfile({
    required CockpitAppHandle app,
    required CockpitTargetKind targetKind,
  }) async {
    final fallbackProfile = await _resolveCapabilityProfile(
      platform: app.platform,
      deviceId: app.deviceId,
      appId: app.platformAppId ?? app.remoteSession?.effectivePlatformAppId,
      processId: app.processId ?? app.remoteSession?.processId,
    );
    if (!_canReadLaunchedApp(app)) {
      return _LaunchedTargetProfile(capabilityProfile: fallbackProfile);
    }

    try {
      final readResult = await _readApp(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );
      final profile = readResult.capabilities.capabilityProfile;
      if (profile == null) {
        return _LaunchedTargetProfile(
          capabilityProfile: fallbackProfile,
          recommendedNextStep: readResult.recommendedNextStep,
          whatMatters: readResult.whatMatters,
        );
      }
      final capabilityProfile = profile.targetKind == targetKind
          ? profile
          : CockpitCapabilityProfile(
              targetKind: targetKind,
              surfaceKinds: profile.surfaceKinds,
              actionCapabilities: profile.actionCapabilities,
              evidenceCapabilities: profile.evidenceCapabilities,
              qualityFlags: profile.qualityFlags,
            );
      return _LaunchedTargetProfile(
        capabilityProfile: capabilityProfile,
        recommendedNextStep: readResult.recommendedNextStep,
        whatMatters: readResult.whatMatters,
      );
    } on Object catch (error) {
      if (!_isRecoverableLaunchedAppReadFailure(error)) {
        rethrow;
      }
      return _LaunchedTargetProfile(capabilityProfile: fallbackProfile);
    }
  }

  bool _canReadLaunchedApp(CockpitAppHandle app) {
    return app.remoteSession != null || app.developmentSession != null;
  }

  bool _isRecoverableLaunchedAppReadFailure(Object error) {
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return true;
    }
    return error is CockpitApplicationServiceException &&
        error.code == 'remoteUnavailable';
  }

  CockpitTargetKind _normalizeTargetKind({
    required CockpitTargetKind requestedTargetKind,
    required CockpitCapabilityProfile capabilityProfile,
  }) {
    if (requestedTargetKind == capabilityProfile.targetKind) {
      return requestedTargetKind;
    }
    if (requestedTargetKind == CockpitTargetKind.flutterApp &&
        (capabilityProfile.targetKind == CockpitTargetKind.desktopApp ||
            capabilityProfile.targetKind == CockpitTargetKind.browserPage)) {
      return capabilityProfile.targetKind;
    }
    throw CockpitApplicationServiceException(
      code: 'unsupportedTargetKind',
      message: 'The requested target kind is incompatible with this platform.',
      details: <String, Object?>{
        'requestedTargetKind': requestedTargetKind.name,
        'platformTargetKind': capabilityProfile.targetKind.name,
      },
    );
  }

  bool _isLaunchableTargetKind(CockpitTargetKind targetKind) {
    return switch (targetKind) {
      CockpitTargetKind.flutterApp ||
      CockpitTargetKind.desktopApp ||
      CockpitTargetKind.browserPage => true,
      CockpitTargetKind.nativeApp ||
      CockpitTargetKind.systemSurface ||
      CockpitTargetKind.device ||
      CockpitTargetKind.hostWorkspace => false,
    };
  }
}

final class _LaunchedTargetProfile {
  const _LaunchedTargetProfile({
    required this.capabilityProfile,
    this.recommendedNextStep,
    this.whatMatters,
  });

  final CockpitCapabilityProfile capabilityProfile;
  final String? recommendedNextStep;
  final String? whatMatters;
}
