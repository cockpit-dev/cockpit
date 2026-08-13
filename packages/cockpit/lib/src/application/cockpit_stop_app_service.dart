import 'dart:io';

import 'package:path/path.dart' as p;

import '../development/cockpit_development_session_status.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_app_temp_store.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_compact_json.dart';
import 'cockpit_platform_app_stopper.dart';
import 'cockpit_session_registry.dart';
import 'cockpit_stop_development_session_service.dart';

typedef CockpitStopDevelopmentAppFunction =
    Future<CockpitStopDevelopmentSessionResult> Function(
      CockpitStopDevelopmentSessionRequest request,
    );
typedef CockpitStopAutomationAppFunction =
    Future<void> Function(CockpitAppHandle app);
typedef CockpitAppReachabilityProbe = Future<bool> Function(Uri baseUri);

Future<bool> cockpitProbeAppReachability(Uri baseUri) async {
  try {
    await CockpitRemoteSessionClient(
      baseUri: baseUri,
      requestTimeout: const Duration(seconds: 2),
    ).readStatus();
    return true;
  } on Object {
    return false;
  }
}

final class CockpitStopAppRequest {
  const CockpitStopAppRequest({this.appId, this.app, this.appHandlePath});

  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
}

final class CockpitStopAppResult {
  const CockpitStopAppResult({
    required this.app,
    required this.status,
    this.appJsonPath,
  });

  final CockpitAppHandle app;
  final CockpitAppStopStatus status;
  final String? appJsonPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'app': app.toJson(),
    'status': status.toJson(),
    if (appJsonPath != null) 'appJsonPath': appJsonPath,
  };
}

final class CockpitAppStopStatus {
  const CockpitAppStopStatus({
    required this.mode,
    required this.state,
    required this.appReachable,
    required this.remoteSessionReachable,
    this.lastError,
  });

  final CockpitAppMode mode;
  final String state;
  final bool? appReachable;
  final bool remoteSessionReachable;
  final String? lastError;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.jsonValue,
    'state': state,
    'appReachable': appReachable,
    'remoteSessionReachable': remoteSessionReachable,
    if (lastError != null) 'lastError': lastError,
  };

  factory CockpitAppStopStatus.fromDevelopmentStatus(
    CockpitDevelopmentSessionStatus status,
  ) {
    return CockpitAppStopStatus(
      mode: CockpitAppMode.development,
      state: status.state.jsonValue,
      appReachable: status.appReachable,
      remoteSessionReachable: status.remoteSessionReachable,
      lastError: status.lastError,
    );
  }

  factory CockpitAppStopStatus.stopped({
    required CockpitAppMode mode,
    String? lastError,
  }) {
    return CockpitAppStopStatus(
      mode: mode,
      state: 'stopped',
      appReachable: false,
      remoteSessionReachable: false,
      lastError: lastError,
    );
  }
}

final class CockpitStopAppService {
  CockpitStopAppService({
    CockpitStopDevelopmentSessionService? stopService,
    CockpitPlatformAppStopper? automationStopper,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitSessionRegistry? registry,
    CockpitStopDevelopmentAppFunction? stopDevelopment,
    CockpitStopAutomationAppFunction? stopAutomation,
    CockpitAppReachabilityProbe? probeReachability,
    CockpitAppTempStore? appTempStore,
  }) : _stopDevelopment =
           stopDevelopment ?? _defaultStopDevelopment(stopService),
       _stopAutomation =
           stopAutomation ??
           (automationStopper ?? CockpitPlatformAppStopper()).stop,
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _registry = registry,
       _probeReachability = probeReachability ?? cockpitProbeAppReachability,
       _appTempStore = appTempStore;

  final CockpitStopDevelopmentAppFunction _stopDevelopment;
  final CockpitStopAutomationAppFunction _stopAutomation;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitSessionRegistry? _registry;
  final CockpitAppReachabilityProbe _probeReachability;
  final CockpitAppTempStore? _appTempStore;

  Future<CockpitStopAppResult> stop(CockpitStopAppRequest request) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
    );
    final developmentHandle =
        resolved.app?.developmentSession ?? resolved.developmentRecord?.handle;
    if (developmentHandle != null) {
      final fallbackApp =
          resolved.app ??
          CockpitAppHandle.fromDevelopmentSession(
            developmentHandle,
            supervisorLogPath: resolved.developmentRecord?.supervisorLogPath,
          );
      CockpitStopDevelopmentSessionResult stopped;
      try {
        stopped = await _stopDevelopment(
          CockpitStopDevelopmentSessionRequest(
            sessionHandle: developmentHandle,
          ),
        );
      } on Object catch (error) {
        await _bestEffortStopDevelopmentPlatformApp(fallbackApp);
        final status = await _waitUntilStopped(
          fallbackApp,
          lastError: error.toString(),
        );
        final appJsonPath = await _persistAppIfRequested(
          path: request.appHandlePath,
          app: fallbackApp,
        );
        return CockpitStopAppResult(
          app: fallbackApp,
          status: status,
          appJsonPath: appJsonPath,
        );
      }
      _registry?.removeDevelopmentSession(
        stopped.sessionHandle.developmentSessionId,
      );
      final app = CockpitAppHandle.fromDevelopmentSession(
        stopped.sessionHandle,
        supervisorLogPath:
            resolved.app?.supervisorLogPath ??
            resolved.developmentRecord?.supervisorLogPath,
      );
      await _bestEffortStopDevelopmentPlatformApp(app);
      final appJsonPath = await _persistAppIfRequested(
        path: request.appHandlePath,
        app: app,
      );
      return CockpitStopAppResult(
        app: app,
        status: CockpitAppStopStatus.fromDevelopmentStatus(stopped.status),
        appJsonPath: appJsonPath,
      );
    }

    final automationApp =
        resolved.app ??
        (resolved.remoteRecord == null
            ? null
            : CockpitAppHandle.fromRemoteSession(
                resolved.remoteRecord!.handle,
              ));
    if (automationApp == null) {
      throw const CockpitApplicationServiceException(
        code: 'stopAppUnavailable',
        message: 'Stop requires a resolved app handle.',
      );
    }
    _validateAutomationStopSupport(automationApp);
    await _stopAutomation(automationApp);
    var status = await _waitUntilStopped(automationApp);
    final remoteHandle =
        automationApp.remoteSession ?? resolved.remoteRecord?.handle;
    if (remoteHandle != null) {
      _registry?.removeRemoteSession(remoteHandle);
      if (await _releaseAutomationTemp(remoteHandle) case final error?) {
        status = CockpitAppStopStatus(
          mode: status.mode,
          state: status.state,
          appReachable: status.appReachable,
          remoteSessionReachable: status.remoteSessionReachable,
          lastError: error,
        );
      }
    }
    final appJsonPath = await _persistAppIfRequested(
      path: request.appHandlePath,
      app: automationApp,
    );
    return CockpitStopAppResult(
      app: automationApp,
      status: status,
      appJsonPath: appJsonPath,
    );
  }

  Future<String?> _releaseAutomationTemp(
    CockpitRemoteSessionHandle handle,
  ) async {
    final store = _appTempStore;
    if (store == null || !cockpitUsesManagedAppTemp(handle.platform)) {
      return null;
    }
    try {
      await store.release(
        cockpitRemoteAppTempKey(
          platform: handle.platform,
          hostPort: handle.hostPort,
        ),
      );
      return null;
    } on Object catch (error) {
      return 'Application temporary directory cleanup failed: $error';
    }
  }

  Future<void> _bestEffortStopDevelopmentPlatformApp(
    CockpitAppHandle app,
  ) async {
    if (app.platform == 'web') {
      return;
    }
    try {
      await _stopAutomation(app).timeout(const Duration(seconds: 5));
    } on Object {
      // The supervisor stop result remains the authoritative development
      // status; this only cleans up platform processes that outlive flutter run.
    }
  }

  void _validateAutomationStopSupport(CockpitAppHandle app) {
    if (app.platform != 'ios' ||
        cockpitLooksLikeIosSimulatorDeviceId(app.deviceId)) {
      return;
    }
    final bundleId = app.platformAppId?.trim();
    if (bundleId != null && bundleId.isNotEmpty) {
      return;
    }
    throw CockpitApplicationServiceException(
      code: 'missingPlatformAppId',
      message:
          'stop-app requires a resolved iOS bundle identifier for '
          'physical-device automation sessions.',
      details: <String, Object?>{
        'platform': app.platform,
        'deviceId': app.deviceId,
        'appId': app.appId,
      },
    );
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

  Future<CockpitAppStopStatus> _waitUntilStopped(
    CockpitAppHandle app, {
    String? lastError,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final reachable = await _probeReachability(app.baseUri);
      if (!reachable) {
        return CockpitAppStopStatus.stopped(
          mode: app.mode,
          lastError: lastError,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const CockpitApplicationServiceException(
      code: 'stopAppTimeout',
      message: 'The app remained reachable after the stop request.',
    );
  }
}

CockpitStopDevelopmentAppFunction _defaultStopDevelopment(
  CockpitStopDevelopmentSessionService? stopService,
) {
  final service = stopService ?? CockpitStopDevelopmentSessionService();
  return (request) => service.stop(request);
}
