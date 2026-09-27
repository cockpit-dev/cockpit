import 'dart:convert';
import 'dart:io';

import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../remote/cockpit_remote_endpoint.dart';
import '../development/cockpit_development_session_handle.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_session_registry.dart';

typedef CockpitIosDeviceConnectionReader =
    Future<CockpitIosDeviceConnection?> Function(String deviceId);

final class CockpitResolvedAppReference {
  CockpitResolvedAppReference({
    required Uri baseUri,
    String authToken = '',
    this.app,
    this.developmentRecord,
    this.remoteRecord,
  }) : endpoint = cockpitResolveRemoteEndpoint(
         baseUri: baseUri,
         authTokens: <String?>[
           authToken,
           app?.authToken,
           developmentRecord?.handle.authToken,
           remoteRecord?.handle.authToken,
         ],
         path: 'app reference',
       );

  final CockpitRemoteEndpoint endpoint;

  Uri get baseUri => endpoint.baseUri;

  String get authToken => endpoint.authToken;
  final CockpitAppHandle? app;
  final CockpitDevelopmentSessionRecord? developmentRecord;
  final CockpitRemoteSessionRecord? remoteRecord;
}

final class CockpitAppReferenceResolver {
  CockpitAppReferenceResolver({
    CockpitSessionRegistry? registry,
    CockpitAndroidPortForwarder portForwarder =
        const CockpitAndroidPortForwarder(),
    CockpitIosDeviceConnectionReader iosDeviceConnectionReader =
        _defaultIosDeviceConnectionReader,
  }) : _registry = registry,
       _portForwarder = portForwarder,
       _iosDeviceConnectionReader = iosDeviceConnectionReader;

  final CockpitSessionRegistry? _registry;
  final CockpitAndroidPortForwarder _portForwarder;
  final CockpitIosDeviceConnectionReader _iosDeviceConnectionReader;

  Future<CockpitResolvedAppReference> resolve({
    String? appId,
    CockpitAppHandle? app,
    String? appHandlePath,
    Uri? baseUri,
    String authToken = '',
    String? androidDeviceId,
    String? iosDeviceId,
  }) async {
    final explicitEndpoint = baseUri == null
        ? null
        : cockpitResolveRemoteEndpoint(
            baseUri: baseUri,
            authTokens: <String?>[authToken],
            path: 'app reference',
          );
    final explicitBaseUri = await _resolvedExplicitBaseUri(
      baseUri: explicitEndpoint?.baseUri,
      androidDeviceId: androidDeviceId,
      iosDeviceId: iosDeviceId,
    );
    final explicitAuthToken = explicitEndpoint?.authToken ?? authToken;
    if (app != null) {
      final resolvedBaseUri =
          explicitBaseUri ?? await _resolvedBaseUriForApp(app);
      return CockpitResolvedAppReference(
        baseUri: resolvedBaseUri,
        authToken: explicitAuthToken,
        app: _withResolvedBaseUri(app, resolvedBaseUri),
      );
    }

    if (appHandlePath != null && appHandlePath.isNotEmpty) {
      final resolvedApp = await readAppHandle(appHandlePath);
      final registry = _registry;
      final developmentRecord = registry?.developmentSessionByAppId(
        resolvedApp.appId,
      );
      final remoteRecord = registry?.remoteSessionByAppId(resolvedApp.appId);
      final resolvedBaseUri =
          explicitBaseUri ??
          await _resolvedBaseUriForApp(
            resolvedApp,
            developmentRecord: developmentRecord,
            remoteRecord: remoteRecord,
          );
      return CockpitResolvedAppReference(
        baseUri: resolvedBaseUri,
        authToken: explicitAuthToken,
        app: _withResolvedBaseUri(resolvedApp, resolvedBaseUri),
        developmentRecord: developmentRecord,
        remoteRecord: remoteRecord,
      );
    }

    if (appId != null && appId.isNotEmpty) {
      final registry = _registry;
      if (registry == null) {
        if (explicitBaseUri != null) {
          return CockpitResolvedAppReference(
            baseUri: explicitBaseUri,
            authToken: explicitAuthToken,
          );
        }
        throw const CockpitApplicationServiceException(
          code: 'appLookupUnavailable',
          message: 'App lookup by appId requires a session registry.',
        );
      }
      final developmentRecord = registry.developmentSessionByAppId(appId);
      final remoteRecord = registry.remoteSessionByAppId(appId);
      final preferRemoteRecord =
          remoteRecord != null &&
          (developmentRecord == null ||
              remoteRecord.updatedAt.isAfter(developmentRecord.updatedAt));
      if (preferRemoteRecord) {
        final app = CockpitAppHandle.fromRemoteSession(remoteRecord.handle);
        final resolvedBaseUri =
            explicitBaseUri ??
            await _resolvedBaseUriForApp(
              app,
              developmentRecord: developmentRecord,
              remoteRecord: remoteRecord,
            );
        return CockpitResolvedAppReference(
          baseUri: resolvedBaseUri,
          app: _withResolvedBaseUri(app, resolvedBaseUri),
          developmentRecord: developmentRecord,
          remoteRecord: remoteRecord,
        );
      }
      if (developmentRecord != null) {
        final app = CockpitAppHandle.fromDevelopmentSession(
          developmentRecord.handle,
        );
        final resolvedBaseUri =
            explicitBaseUri ??
            await _resolvedBaseUriForApp(
              app,
              developmentRecord: developmentRecord,
            );
        return CockpitResolvedAppReference(
          baseUri: resolvedBaseUri,
          app: _withResolvedBaseUri(app, resolvedBaseUri),
          developmentRecord: developmentRecord,
        );
      }
      if (remoteRecord != null) {
        final app = CockpitAppHandle.fromRemoteSession(remoteRecord.handle);
        final resolvedBaseUri =
            explicitBaseUri ??
            await _resolvedBaseUriForApp(app, remoteRecord: remoteRecord);
        return CockpitResolvedAppReference(
          baseUri: resolvedBaseUri,
          app: _withResolvedBaseUri(app, resolvedBaseUri),
          remoteRecord: remoteRecord,
        );
      }
      if (explicitBaseUri != null) {
        return CockpitResolvedAppReference(
          baseUri: explicitBaseUri,
          authToken: explicitAuthToken,
        );
      }
      throw CockpitApplicationServiceException(
        code: 'unknownAppId',
        message: 'Unknown appId.',
        details: <String, Object?>{'appId': appId},
      );
    }

    if (explicitBaseUri != null) {
      return CockpitResolvedAppReference(
        baseUri: explicitBaseUri,
        authToken: explicitAuthToken,
      );
    }

    throw const CockpitApplicationServiceException(
      code: 'missingAppReference',
      message:
          'An appId, app handle, app handle path, or base URI is required.',
    );
  }

  Future<Uri?> _resolvedExplicitBaseUri({
    required Uri? baseUri,
    required String? androidDeviceId,
    required String? iosDeviceId,
  }) async {
    if (baseUri == null) {
      return null;
    }
    return await _resolvedBaseUriForAndroidDevice(
          baseUri: baseUri,
          androidDeviceId: androidDeviceId,
        ) ??
        await _resolvedBaseUriForIosDevice(
          baseUri: baseUri,
          iosDeviceId: iosDeviceId,
        ) ??
        baseUri;
  }

  Future<Uri?> _resolvedBaseUriForAndroidDevice({
    required Uri baseUri,
    required String? androidDeviceId,
  }) async {
    final deviceId = androidDeviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }
    final hostPort = await _portForwarder.ensureForwarded(
      deviceId: deviceId,
      preferredHostPort: baseUri.port,
      devicePort: baseUri.port,
    );
    return baseUri.replace(host: '127.0.0.1', port: hostPort);
  }

  Future<Uri?> _resolvedBaseUriForIosDevice({
    required Uri baseUri,
    required String? iosDeviceId,
  }) async {
    final deviceId = iosDeviceId?.trim();
    if (deviceId == null ||
        deviceId.isEmpty ||
        cockpitLooksLikeIosSimulatorDeviceId(deviceId)) {
      return null;
    }

    final connection = await _iosDeviceConnectionReader(deviceId);
    if (connection == null || !connection.hasReachableTunnel) {
      return null;
    }
    return baseUri.replace(host: connection.tunnelIpAddress);
  }

  Future<CockpitAppHandle> readAppHandle(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw CockpitApplicationServiceException(
        code: 'appHandleNotFound',
        message: 'App handle JSON file does not exist.',
        details: <String, Object?>{'path': path},
      );
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      throw CockpitApplicationServiceException(
        code: 'invalidAppHandleJson',
        message: 'App handle JSON must decode to an object.',
        details: <String, Object?>{'path': path},
      );
    }
    final normalized = Map<String, Object?>.from(decoded);
    final wrappedApp = normalized['app'];
    if (wrappedApp is Map<Object?, Object?>) {
      return CockpitAppHandle.fromJson(Map<String, Object?>.from(wrappedApp));
    }
    return CockpitAppHandle.fromJson(normalized);
  }

  Future<Uri> _resolvedBaseUriForApp(
    CockpitAppHandle app, {
    CockpitDevelopmentSessionRecord? developmentRecord,
    CockpitRemoteSessionRecord? remoteRecord,
  }) async {
    if (app.platform == 'android') {
      return _resolvedAndroidBaseUri(
        app,
        developmentRecord: developmentRecord,
        remoteRecord: remoteRecord,
      );
    }
    if (_isPhysicalIosApp(app)) {
      return _resolvedPhysicalIosBaseUri(
        app,
        developmentRecord: developmentRecord,
        remoteRecord: remoteRecord,
      );
    }
    return app.baseUri;
  }

  Future<Uri> _resolvedAndroidBaseUri(
    CockpitAppHandle app, {
    CockpitDevelopmentSessionRecord? developmentRecord,
    CockpitRemoteSessionRecord? remoteRecord,
  }) async {
    final remoteSessionHandle = _remoteSessionHandleForResolution(
      app,
      developmentRecord: developmentRecord,
      remoteRecord: remoteRecord,
    );
    final devicePort = remoteSessionHandle?.devicePort;
    if (devicePort == null) {
      return app.baseUri;
    }
    final preferredHostPort = remoteSessionHandle?.hostPort ?? app.baseUri.port;
    final hostPort = await _portForwarder.ensureForwarded(
      deviceId: app.deviceId,
      preferredHostPort: preferredHostPort,
      devicePort: devicePort,
    );
    final sourceUri = remoteSessionHandle?.baseUri ?? app.baseUri;
    return sourceUri.replace(host: '127.0.0.1', port: hostPort);
  }

  Future<Uri> _resolvedPhysicalIosBaseUri(
    CockpitAppHandle app, {
    CockpitDevelopmentSessionRecord? developmentRecord,
    CockpitRemoteSessionRecord? remoteRecord,
  }) async {
    final remoteSessionHandle = _remoteSessionHandleForResolution(
      app,
      developmentRecord: developmentRecord,
      remoteRecord: remoteRecord,
    );
    final connection = await _iosDeviceConnectionReader(app.deviceId);
    if (connection == null || !connection.hasReachableTunnel) {
      return remoteSessionHandle?.baseUri ?? app.baseUri;
    }
    final sourceUri = remoteSessionHandle?.baseUri ?? app.baseUri;
    return sourceUri.replace(
      host: connection.tunnelIpAddress!,
      port: remoteSessionHandle?.hostPort ?? app.baseUri.port,
    );
  }

  bool _isPhysicalIosApp(CockpitAppHandle app) {
    return app.platform == 'ios' &&
        !cockpitLooksLikeIosSimulatorDeviceId(app.deviceId);
  }

  CockpitRemoteSessionHandle? _remoteSessionHandleForResolution(
    CockpitAppHandle app, {
    CockpitDevelopmentSessionRecord? developmentRecord,
    CockpitRemoteSessionRecord? remoteRecord,
  }) {
    if (developmentRecord != null &&
        remoteRecord != null &&
        remoteRecord.updatedAt.isAfter(developmentRecord.updatedAt)) {
      return remoteRecord.handle;
    }
    return developmentRecord?.handle.remoteSessionHandle ??
        remoteRecord?.handle ??
        app.remoteSession;
  }

  CockpitAppHandle _withResolvedBaseUri(CockpitAppHandle app, Uri baseUri) {
    final remoteSession = app.remoteSession;
    final resolvedRemoteSession = remoteSession == null
        ? null
        : _remoteSessionWithResolvedBaseUri(remoteSession, baseUri);
    final developmentSession = app.developmentSession;
    final resolvedDevelopmentSession = developmentSession == null
        ? null
        : _developmentSessionWithResolvedBaseUri(developmentSession, baseUri);
    if (app.baseUrl == baseUri.toString() &&
        identical(resolvedRemoteSession, remoteSession) &&
        identical(resolvedDevelopmentSession, developmentSession)) {
      return app;
    }
    return app.copyWith(
      baseUrl: baseUri.toString(),
      developmentSession: resolvedDevelopmentSession,
      remoteSession: resolvedRemoteSession,
    );
  }

  CockpitDevelopmentSessionHandle _developmentSessionWithResolvedBaseUri(
    CockpitDevelopmentSessionHandle handle,
    Uri baseUri,
  ) {
    final remoteSession = handle.remoteSessionHandle;
    final resolvedRemoteSession = remoteSession == null
        ? null
        : _remoteSessionWithResolvedBaseUri(remoteSession, baseUri);
    if (handle.appBaseUrl == baseUri.toString() &&
        identical(resolvedRemoteSession, remoteSession)) {
      return handle;
    }
    return handle.copyWith(
      appBaseUrl: baseUri.toString(),
      remoteSessionHandle: resolvedRemoteSession,
    );
  }

  CockpitRemoteSessionHandle _remoteSessionWithResolvedBaseUri(
    CockpitRemoteSessionHandle handle,
    Uri baseUri,
  ) {
    if (handle.baseUrl == baseUri.toString() &&
        handle.host == baseUri.host &&
        handle.hostPort == baseUri.port) {
      return handle;
    }
    return handle.copyWith(
      host: baseUri.host,
      hostPort: baseUri.port,
      baseUrl: baseUri.toString(),
    );
  }
}

Future<CockpitIosDeviceConnection?> _defaultIosDeviceConnectionReader(
  String deviceId,
) {
  return CockpitIosDeviceConnectionProbe().probe(deviceId);
}
