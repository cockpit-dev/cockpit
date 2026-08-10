import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import 'cockpit_entrypoint_resolver.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../development/cockpit_development_session_machine_launcher.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../session/cockpit_remote_session_launcher.dart';
import 'cockpit_app_temp_store.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_compact_json.dart';
import 'cockpit_launch_development_session_service.dart';
import 'cockpit_launch_remote_session_service.dart';
import 'cockpit_session_registry.dart';
import 'cockpit_stop_app_service.dart';

typedef CockpitExistingDesktopAppStopper =
    Future<void> Function(CockpitAppHandle app);

final class CockpitLaunchAppRequest {
  const CockpitLaunchAppRequest({
    required this.projectDir,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    this.target,
    this.flavor,
    this.mode = CockpitAppMode.development,
    this.launchTimeout = const Duration(seconds: 600),
    this.allowSessionPortFallback = true,
    this.appHandlePath,
    this.launchConfiguration = CockpitFlutterLaunchConfiguration.empty,
  });

  final String projectDir;
  final String? target;
  final String? flavor;
  final String platform;
  final String deviceId;
  final int sessionPort;
  final CockpitAppMode mode;
  final Duration launchTimeout;
  final bool allowSessionPortFallback;
  final String? appHandlePath;
  final CockpitFlutterLaunchConfiguration launchConfiguration;
}

final class CockpitLaunchAppResult {
  const CockpitLaunchAppResult({
    required this.app,
    this.appJsonPath,
    this.supervisorLogPath,
  });

  final CockpitAppHandle app;
  final String? appJsonPath;
  final String? supervisorLogPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'app': app.toJson(),
    if (appJsonPath != null) 'appJsonPath': appJsonPath,
    if (supervisorLogPath != null) 'supervisorLogPath': supervisorLogPath,
  };
}

final class CockpitLaunchAppService {
  CockpitLaunchAppService({
    CockpitLaunchDevelopmentSessionService? developmentService,
    CockpitLaunchRemoteSessionService? remoteService,
    CockpitRemoteSessionStatusReader remoteStatusReader =
        cockpitReadRemoteSessionStatus,
    CockpitSessionRegistry? registry,
    CockpitExistingDesktopAppStopper? stopExistingDesktopApp,
    CockpitAppTempStore? appTempStore,
  }) : _developmentService =
           developmentService ?? CockpitLaunchDevelopmentSessionService(),
       _remoteService =
           remoteService ??
           CockpitLaunchRemoteSessionService(appTempStore: appTempStore),
       _remoteStatusReader = remoteStatusReader,
       _registry = registry,
       _stopExistingDesktopApp =
           stopExistingDesktopApp ??
           _defaultStopExistingDesktopApp(appTempStore);

  final CockpitLaunchDevelopmentSessionService _developmentService;
  final CockpitLaunchRemoteSessionService _remoteService;
  final CockpitRemoteSessionStatusReader _remoteStatusReader;
  final CockpitSessionRegistry? _registry;
  final CockpitExistingDesktopAppStopper _stopExistingDesktopApp;

  Future<CockpitLaunchAppResult> launch(CockpitLaunchAppRequest request) async {
    await _maybeStopExistingDesktopApp(request);
    return switch (request.mode) {
      CockpitAppMode.development => _launchDevelopment(request),
      CockpitAppMode.automation => _launchAutomation(request),
    };
  }

  Future<CockpitLaunchAppResult> _launchDevelopment(
    CockpitLaunchAppRequest request,
  ) async {
    try {
      final result = await _developmentService.launch(
        CockpitLaunchDevelopmentSessionRequest(
          projectDir: request.projectDir,
          target: request.target,
          flavor: request.flavor,
          platform: request.platform,
          deviceId: request.deviceId,
          sessionPort: request.sessionPort,
          launchTimeout: request.launchTimeout,
          allowSessionPortFallback: request.allowSessionPortFallback,
          persistAppHandlePath: request.appHandlePath,
          launchConfiguration: request.launchConfiguration,
        ),
      );
      _registry?.recordDevelopmentSession(
        handle: result.sessionHandle,
        status: result.status,
        supervisorLogPath: result.supervisorLogPath,
      );
      return CockpitLaunchAppResult(
        app: result.app,
        appJsonPath: result.appJsonPath,
        supervisorLogPath: result.supervisorLogPath,
      );
    } on Object catch (error) {
      if (!_shouldFallbackToAutomation(request, error)) {
        rethrow;
      }
      if (error is CockpitDevelopmentSessionFallbackException) {
        final reusedResult = await _reuseFallbackRemoteSession(
          request: request,
          error: error,
        );
        if (reusedResult != null) {
          return reusedResult;
        }
      }
      return _launchAutomation(request);
    }
  }

  bool _shouldFallbackToAutomation(
    CockpitLaunchAppRequest request,
    Object error,
  ) {
    return request.platform == 'ios' &&
        request.mode == CockpitAppMode.development &&
        !cockpitLooksLikeIosSimulatorDeviceId(request.deviceId) &&
        error is CockpitDevelopmentSessionFallbackException &&
        error.code == 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed';
  }

  Future<CockpitLaunchAppResult?> _reuseFallbackRemoteSession({
    required CockpitLaunchAppRequest request,
    required CockpitDevelopmentSessionFallbackException error,
  }) async {
    final remoteSessionHandle = error.remoteSessionHandle;
    if (remoteSessionHandle == null) {
      return null;
    }
    final remoteStatus = await _readFallbackRemoteStatus(
      error,
      remoteSessionHandle,
    );
    if (remoteStatus != null) {
      try {
        _registry?.recordRemoteSession(
          handle: remoteSessionHandle,
          status: remoteStatus,
          recommendedNextStep: remoteStatus.capabilities.supportsInAppControl
              ? 'ready_for_commands'
              : 'limited_capabilities',
        );
      } on Object {
        // Registry writes are best-effort for fallback reuse.
      }
    }
    final app = CockpitAppHandle.fromRemoteSession(remoteSessionHandle);
    final appJsonPath = await _persistAppIfRequested(
      path: request.appHandlePath,
      app: app,
    );
    return CockpitLaunchAppResult(app: app, appJsonPath: appJsonPath);
  }

  Future<CockpitRemoteSessionStatus?> _readFallbackRemoteStatus(
    CockpitDevelopmentSessionFallbackException error,
    CockpitRemoteSessionHandle remoteSessionHandle,
  ) async {
    if (error.remoteStatus != null) {
      return error.remoteStatus;
    }
    try {
      return await _remoteStatusReader(remoteSessionHandle.baseUri);
    } on Object {
      return null;
    }
  }

  Future<CockpitLaunchAppResult> _launchAutomation(
    CockpitLaunchAppRequest request,
  ) async {
    final result = await _remoteService.launch(
      CockpitLaunchRemoteSessionRequest(
        projectDir: request.projectDir,
        target: request.target,
        flavor: request.flavor,
        platform: request.platform,
        deviceId: request.deviceId,
        sessionPort: request.sessionPort,
        launchTimeout: request.launchTimeout,
        allowSessionPortFallback: request.allowSessionPortFallback,
        launchConfiguration: request.launchConfiguration,
      ),
    );
    _registry?.recordRemoteSession(
      handle: result.sessionHandle,
      status: result.health,
      recommendedNextStep: result.health.capabilities.supportsInAppControl
          ? 'ready_for_commands'
          : 'limited_capabilities',
    );
    final app = CockpitAppHandle.fromRemoteSession(result.sessionHandle);
    final appJsonPath = await _persistAppIfRequested(
      path: request.appHandlePath,
      app: app,
    );
    return CockpitLaunchAppResult(app: app, appJsonPath: appJsonPath);
  }

  Future<String?> _persistAppIfRequested({
    required String? path,
    required CockpitAppHandle app,
  }) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(cockpitPrettyJsonText(app.toJson()));
    return p.normalize(file.path);
  }

  Future<void> _maybeStopExistingDesktopApp(
    CockpitLaunchAppRequest request,
  ) async {
    if (!_isDesktopSingleInstancePlatform(request.platform)) {
      return;
    }
    final appHandlePath = request.appHandlePath;
    if (appHandlePath == null || appHandlePath.trim().isEmpty) {
      return;
    }

    final existingApp = await _readPersistedAppHandle(appHandlePath);
    if (existingApp == null ||
        !_shouldStopExistingDesktopApp(
          existingApp: existingApp,
          request: request,
        )) {
      return;
    }

    await _stopExistingDesktopApp(existingApp);
  }

  bool _shouldStopExistingDesktopApp({
    required CockpitAppHandle existingApp,
    required CockpitLaunchAppRequest request,
  }) {
    return existingApp.platform == request.platform &&
        existingApp.deviceId == request.deviceId &&
        p.equals(
          cockpitNormalizeProjectDir(existingApp.projectDir),
          cockpitNormalizeProjectDir(request.projectDir),
        );
  }

  Future<CockpitAppHandle?> _readPersistedAppHandle(
    String appHandlePath,
  ) async {
    final file = File(appHandlePath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      return CockpitAppHandle.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  bool _isDesktopSingleInstancePlatform(String platform) {
    return platform == 'macos' || platform == 'windows' || platform == 'linux';
  }
}

CockpitExistingDesktopAppStopper _defaultStopExistingDesktopApp(
  CockpitAppTempStore? appTempStore,
) => (app) async {
  await CockpitStopAppService(
    appTempStore: appTempStore,
  ).stop(CockpitStopAppRequest(app: app));
};
