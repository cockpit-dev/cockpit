import 'dart:convert';
import 'dart:io';

import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../remote/cockpit_remote_endpoint.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_application_service_exception.dart';

typedef CockpitSessionIosDeviceConnectionReader =
    Future<CockpitIosDeviceConnection?> Function(String deviceId);

final class CockpitResolvedSessionReference {
  const CockpitResolvedSessionReference({
    required this.baseUri,
    this.password = '',
    this.sessionHandle,
  });

  final Uri baseUri;
  final String password;
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
    String password = '',
    CockpitRemoteSessionHandle? sessionHandle,
    String? sessionHandlePath,
    String? androidDeviceId,
    String? iosDeviceId,
  }) async {
    if (sessionHandle != null) {
      final endpoint = cockpitResolveRemoteEndpoint(
        baseUri: baseUri ?? sessionHandle.baseUri,
        passwords: <String?>[password, sessionHandle.password],
        path: 'session reference',
      );
      // An explicit base URI is authoritative: the caller already knows the
      // reachable endpoint, so forwarding is refreshed only when the address
      // comes from the session handle itself.
      final resolvedBaseUri = baseUri == null
          ? await _resolvedBaseUriForSession(sessionHandle, endpoint.baseUri)
          : endpoint.baseUri;
      return CockpitResolvedSessionReference(
        baseUri: resolvedBaseUri,
        password: endpoint.password,
        sessionHandle: _withResolvedBaseUri(sessionHandle, resolvedBaseUri),
      );
    }

    if (sessionHandlePath != null && sessionHandlePath.isNotEmpty) {
      final resolvedHandle = await readSessionHandle(sessionHandlePath);
      final endpoint = cockpitResolveRemoteEndpoint(
        baseUri: baseUri ?? resolvedHandle.baseUri,
        passwords: <String?>[password, resolvedHandle.password],
        path: 'session reference',
      );
      final resolvedBaseUri = baseUri == null
          ? await _resolvedBaseUriForSession(resolvedHandle, endpoint.baseUri)
          : endpoint.baseUri;
      return CockpitResolvedSessionReference(
        baseUri: resolvedBaseUri,
        password: endpoint.password,
        sessionHandle: _withResolvedBaseUri(resolvedHandle, resolvedBaseUri),
      );
    }

    if (baseUri != null) {
      final endpoint = cockpitResolveRemoteEndpoint(
        baseUri: baseUri,
        passwords: <String?>[password],
        path: 'session reference',
      );
      final resolvedAndroidBaseUri = await _resolvedBaseUriForAndroidDevice(
        baseUri: endpoint.baseUri,
        androidDeviceId: androidDeviceId,
      );
      if (resolvedAndroidBaseUri != null) {
        return CockpitResolvedSessionReference(
          baseUri: resolvedAndroidBaseUri,
          password: endpoint.password,
        );
      }

      final resolvedIosBaseUri = await _resolvedBaseUriForIosDevice(
        baseUri: endpoint.baseUri,
        iosDeviceId: iosDeviceId,
      );
      return CockpitResolvedSessionReference(
        baseUri: resolvedIosBaseUri ?? endpoint.baseUri,
        password: endpoint.password,
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

  Future<Uri> _resolvedBaseUriForSession(
    CockpitRemoteSessionHandle handle,
    Uri baseUri,
  ) async {
    if (handle.platform != 'android') {
      return baseUri;
    }
    final hostPort = await _portForwarder.ensureForwarded(
      deviceId: handle.deviceId,
      preferredHostPort: handle.hostPort,
      devicePort: handle.devicePort,
    );
    return baseUri.replace(host: '127.0.0.1', port: hostPort);
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
