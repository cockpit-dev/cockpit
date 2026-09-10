import 'dart:convert';
import 'dart:io';

import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_application_service_exception.dart';

typedef CockpitSessionIosDeviceConnectionReader =
    Future<CockpitIosDeviceConnection?> Function(String deviceId);

final class CockpitResolvedSessionReference {
  const CockpitResolvedSessionReference({
    required this.baseUri,
    this.sessionHandle,
  });

  final Uri baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
}

final class CockpitSessionReferenceResolver {
  CockpitSessionReferenceResolver({
    CockpitAndroidPortForwarder portForwarder =
        const CockpitAndroidPortForwarder(),
    CockpitSessionIosDeviceConnectionReader iosDeviceConnectionReader =
        _defaultIosDeviceConnectionReader,
  }) : _portForwarder = portForwarder,
       _iosDeviceConnectionReader = iosDeviceConnectionReader;

  final CockpitAndroidPortForwarder _portForwarder;
  final CockpitSessionIosDeviceConnectionReader _iosDeviceConnectionReader;

  Future<CockpitResolvedSessionReference> resolve({
    Uri? baseUri,
    CockpitRemoteSessionHandle? sessionHandle,
    String? sessionHandlePath,
    String? androidDeviceId,
    String? iosDeviceId,
  }) async {
    if (sessionHandle != null) {
      final resolvedBaseUri = baseUri == null
          ? await _resolvedBaseUriForSession(sessionHandle)
          : _withSessionToken(baseUri, sessionHandle);
      return CockpitResolvedSessionReference(
        baseUri: resolvedBaseUri,
        sessionHandle: _withResolvedBaseUri(sessionHandle, resolvedBaseUri),
      );
    }

    if (sessionHandlePath != null && sessionHandlePath.isNotEmpty) {
      final resolvedHandle = await readSessionHandle(sessionHandlePath);
      final resolvedBaseUri = baseUri == null
          ? await _resolvedBaseUriForSession(resolvedHandle)
          : _withSessionToken(baseUri, resolvedHandle);
      return CockpitResolvedSessionReference(
        baseUri: resolvedBaseUri,
        sessionHandle: _withResolvedBaseUri(resolvedHandle, resolvedBaseUri),
      );
    }

    if (baseUri != null) {
      final resolvedAndroidBaseUri = await _resolvedBaseUriForAndroidDevice(
        baseUri: baseUri,
        androidDeviceId: androidDeviceId,
      );
      if (resolvedAndroidBaseUri != null) {
        return CockpitResolvedSessionReference(baseUri: resolvedAndroidBaseUri);
      }

      final resolvedIosBaseUri = await _resolvedBaseUriForIosDevice(
        baseUri: baseUri,
        iosDeviceId: iosDeviceId,
      );
      return CockpitResolvedSessionReference(
        baseUri: resolvedIosBaseUri ?? baseUri,
      );
    }

    throw const CockpitApplicationServiceException(
      code: 'missingSessionReference',
      message: 'A session handle, handle path, or base URI is required.',
    );
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

  /// An explicit baseUri may come from an app reference that carries the raw
  /// endpoint without credentials; a session handle knows its own token, so
  /// merge the token query parameter back in before any client call.
  Uri _withSessionToken(Uri baseUri, CockpitRemoteSessionHandle handle) {
    final authToken = handle.authToken;
    if (authToken.isEmpty || baseUri.queryParameters['token'] != null) {
      return baseUri;
    }
    return baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'token': authToken,
      },
    );
  }

  Future<Uri> _resolvedBaseUriForSession(
    CockpitRemoteSessionHandle handle,
  ) async {
    if (handle.platform != 'android') {
      return handle.baseUri;
    }
    final hostPort = await _portForwarder.ensureForwarded(
      deviceId: handle.deviceId,
      preferredHostPort: handle.hostPort,
      devicePort: handle.devicePort,
    );
    // Keep the full resolved URI, including any token query parameter, so the
    // forwarded endpoint stays authenticated exactly like the original one.
    return handle.baseUri.replace(host: '127.0.0.1', port: hostPort);
  }

  CockpitRemoteSessionHandle _withResolvedBaseUri(
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

  Future<CockpitRemoteSessionHandle> readSessionHandle(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw CockpitApplicationServiceException(
        code: 'sessionHandleNotFound',
        message: 'Session handle JSON file does not exist.',
        details: <String, Object?>{'path': path},
      );
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      throw CockpitApplicationServiceException(
        code: 'invalidSessionHandleJson',
        message: 'Session handle JSON must decode to an object.',
        details: <String, Object?>{'path': path},
      );
    }
    return CockpitRemoteSessionHandle.fromJson(
      Map<String, Object?>.from(decoded),
    );
  }
}

Future<CockpitIosDeviceConnection?> _defaultIosDeviceConnectionReader(
  String deviceId,
) {
  return CockpitIosDeviceConnectionProbe().probe(deviceId);
}
