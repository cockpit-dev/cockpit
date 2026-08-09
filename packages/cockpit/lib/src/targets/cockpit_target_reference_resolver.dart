import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_app_reference_resolver.dart';
import '../application/cockpit_application_service_exception.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_target_handle.dart';

final class CockpitResolvedTargetReference {
  const CockpitResolvedTargetReference({
    required this.baseUri,
    this.target,
    this.app,
  });

  final Uri baseUri;
  final CockpitTargetHandle? target;
  final CockpitAppHandle? app;
}

final class CockpitTargetReferenceResolver {
  CockpitTargetReferenceResolver({
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitAndroidPortForwarder portForwarder =
        const CockpitAndroidPortForwarder(),
  }) : _appReferenceResolver =
           appReferenceResolver ?? CockpitAppReferenceResolver(),
       _portForwarder = portForwarder;

  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitAndroidPortForwarder _portForwarder;

  Future<CockpitResolvedTargetReference> resolve({
    CockpitTargetHandle? target,
    String? targetHandlePath,
    CockpitAppHandle? app,
    String? appHandlePath,
    Uri? baseUri,
    String? androidDeviceId,
  }) async {
    if (target != null) {
      if (app != null) {
        _requireMatchingTargetApp(target, app);
        final resolvedApp = await _appReferenceResolver.resolve(
          app: app,
          baseUri: baseUri,
        );
        final currentApp = resolvedApp.app ?? app;
        return CockpitResolvedTargetReference(
          baseUri: resolvedApp.baseUri,
          target: target.copyWith(
            connection: CockpitTargetConnection(
              baseUrl: resolvedApp.baseUri.toString(),
            ),
            metadata: _metadataWithResolvedApp(target.metadata, currentApp),
          ),
          app: currentApp,
        );
      }
      final refreshed = await _refreshTargetConnection(
        target,
        overrideBaseUri: baseUri,
      );
      return CockpitResolvedTargetReference(
        baseUri: refreshed.baseUri,
        target: refreshed,
      );
    }

    if (targetHandlePath != null && targetHandlePath.isNotEmpty) {
      final resolvedTarget = await readTargetHandle(targetHandlePath);
      final refreshed = await _refreshTargetConnection(
        resolvedTarget,
        overrideBaseUri: baseUri,
      );
      return CockpitResolvedTargetReference(
        baseUri: refreshed.baseUri,
        target: refreshed,
      );
    }

    if (app != null || (appHandlePath != null && appHandlePath.isNotEmpty)) {
      final resolvedApp = await _appReferenceResolver.resolve(
        app: app,
        appHandlePath: appHandlePath,
        baseUri: baseUri,
      );
      final resolvedTarget = resolvedApp.app == null
          ? null
          : CockpitTargetHandle.fromAppHandle(resolvedApp.app!);
      return CockpitResolvedTargetReference(
        baseUri: resolvedApp.baseUri,
        target: resolvedTarget,
        app: resolvedApp.app,
      );
    }

    if (baseUri != null) {
      final deviceId = androidDeviceId;
      if (deviceId == null || deviceId.isEmpty) {
        return CockpitResolvedTargetReference(baseUri: baseUri);
      }
      final hostPort = await _portForwarder.ensureForwarded(
        deviceId: deviceId,
        preferredHostPort: baseUri.port,
        devicePort: baseUri.port,
      );
      return CockpitResolvedTargetReference(
        baseUri: baseUri.replace(port: hostPort),
      );
    }

    throw const CockpitApplicationServiceException(
      code: 'missingTargetReference',
      message:
          'A target handle, target handle path, app handle, or base URI is required.',
    );
  }

  void _requireMatchingTargetApp(
    CockpitTargetHandle target,
    CockpitAppHandle app,
  ) {
    final targetAppId = target.metadata['appId'];
    if ((targetAppId is String && targetAppId != app.appId) ||
        target.platform != app.platform ||
        target.deviceId != app.deviceId) {
      throw const CockpitApplicationServiceException(
        code: 'targetAppIdentityMismatch',
        message: 'Target and application handles describe different runtimes.',
      );
    }
  }

  Future<CockpitTargetHandle> readTargetHandle(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw CockpitApplicationServiceException(
        code: 'targetHandleNotFound',
        message: 'Target handle JSON file does not exist.',
        details: <String, Object?>{'path': path},
      );
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      throw CockpitApplicationServiceException(
        code: 'invalidTargetHandleJson',
        message: 'Target handle JSON must decode to an object.',
        details: <String, Object?>{'path': path},
      );
    }

    final normalized = Map<String, Object?>.from(decoded);
    final wrappedTarget = normalized['targetHandle'] ?? normalized['target'];
    if (wrappedTarget is Map<Object?, Object?>) {
      return CockpitTargetHandle.fromJson(
        Map<String, Object?>.from(wrappedTarget),
      );
    }
    return CockpitTargetHandle.fromJson(normalized);
  }

  Future<CockpitTargetHandle> _refreshTargetConnection(
    CockpitTargetHandle target, {
    Uri? overrideBaseUri,
  }) async {
    if (target.targetKind != CockpitTargetKind.flutterApp &&
        target.targetKind != CockpitTargetKind.desktopApp) {
      if (overrideBaseUri == null || overrideBaseUri == target.baseUri) {
        return target;
      }
      return target.copyWith(
        connection: CockpitTargetConnection(
          baseUrl: overrideBaseUri.toString(),
        ),
      );
    }
    if (overrideBaseUri != null) {
      target = target.copyWith(
        connection: CockpitTargetConnection(
          baseUrl: overrideBaseUri.toString(),
        ),
      );
    }
    final app = CockpitAppHandle(
      appId: target.metadata['appId'] as String? ?? target.targetId,
      mode: target.metadata['appMode'] == CockpitAppMode.development.jsonValue
          ? CockpitAppMode.development
          : CockpitAppMode.automation,
      platform: target.platform,
      deviceId: target.deviceId,
      projectDir: target.projectDir,
      target: target.target,
      baseUrl: target.connection.baseUrl,
      launchedAt: target.launchedAt,
      platformAppId: target.metadata['platformAppId'] as String?,
      processId: _targetProcessId(target),
      remoteSession: _targetRemoteSession(target),
    );
    final resolved = await _appReferenceResolver.resolve(
      app: app,
      baseUri: overrideBaseUri,
    );
    final refreshedApp = resolved.app;
    final refreshedMetadata = refreshedApp == null
        ? target.metadata
        : _metadataWithResolvedApp(target.metadata, refreshedApp);
    if (resolved.baseUri == target.baseUri &&
        _metadataMapsEqual(refreshedMetadata, target.metadata)) {
      return target;
    }
    return target.copyWith(
      connection: CockpitTargetConnection(baseUrl: resolved.baseUri.toString()),
      metadata: refreshedMetadata,
    );
  }

  Map<String, Object?> _metadataWithResolvedApp(
    Map<String, Object?> metadata,
    CockpitAppHandle app,
  ) {
    final refreshed = Map<String, Object?>.of(metadata)
      ..['appId'] = app.appId
      ..['appMode'] = app.mode.jsonValue
      ..['supportsHotReload'] = app.supportsHotReload;
    final platformAppId = app.platformAppId;
    if (platformAppId == null) {
      refreshed.remove('platformAppId');
    } else {
      refreshed['platformAppId'] = platformAppId;
    }
    final processId = app.processId;
    if (processId == null) {
      refreshed.remove('processId');
    } else {
      refreshed['processId'] = processId;
    }
    final remoteSession = app.remoteSession;
    if (remoteSession == null) {
      refreshed.remove('remoteSession');
    } else {
      refreshed['remoteSession'] = remoteSession.toJson();
    }
    final supervisorLogPath = app.supervisorLogPath;
    if (supervisorLogPath == null) {
      refreshed.remove('supervisorLogPath');
    } else {
      refreshed['supervisorLogPath'] = supervisorLogPath;
    }
    return refreshed;
  }

  bool _metadataMapsEqual(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonLikeValueEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }

  bool _jsonLikeValueEquals(Object? left, Object? right) {
    if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_jsonLikeValueEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List<Object?> && right is List<Object?>) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index += 1) {
        if (!_jsonLikeValueEquals(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  int? _targetProcessId(CockpitTargetHandle target) {
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
    return null;
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
}
