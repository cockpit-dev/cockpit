import 'package:collection/collection.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_app_handle.dart';

final class CockpitTargetConnection {
  const CockpitTargetConnection({required this.baseUrl});

  final String baseUrl;

  Uri get baseUri => Uri.parse(baseUrl);

  Map<String, Object?> toJson() => <String, Object?>{'baseUrl': baseUrl};

  factory CockpitTargetConnection.fromJson(Map<String, Object?> json) {
    return CockpitTargetConnection(baseUrl: json['baseUrl']! as String);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitTargetConnection && other.baseUrl == baseUrl;
  }

  @override
  int get hashCode => baseUrl.hashCode;
}

final class CockpitTargetHandle {
  CockpitTargetHandle({
    required this.targetId,
    required this.targetKind,
    required this.platform,
    required this.deviceId,
    required this.projectDir,
    required this.target,
    required this.connection,
    required this.launchedAt,
    this.capabilityProfile,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = Map.unmodifiable(metadata);

  final String targetId;
  final CockpitTargetKind targetKind;
  final String platform;
  final String deviceId;
  final String projectDir;
  final String target;
  final CockpitTargetConnection connection;
  final DateTime launchedAt;
  final CockpitCapabilityProfile? capabilityProfile;
  final Map<String, Object?> metadata;

  static const MapEquality<String, Object?> _metadataEquality =
      MapEquality<String, Object?>();

  Uri get baseUri => connection.baseUri;

  CockpitTargetHandle copyWith({
    String? targetId,
    CockpitTargetKind? targetKind,
    String? platform,
    String? deviceId,
    String? projectDir,
    String? target,
    CockpitTargetConnection? connection,
    DateTime? launchedAt,
    CockpitCapabilityProfile? capabilityProfile,
    Map<String, Object?>? metadata,
  }) {
    return CockpitTargetHandle(
      targetId: targetId ?? this.targetId,
      targetKind: targetKind ?? this.targetKind,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      projectDir: projectDir ?? this.projectDir,
      target: target ?? this.target,
      connection: connection ?? this.connection,
      launchedAt: launchedAt ?? this.launchedAt,
      capabilityProfile: capabilityProfile ?? this.capabilityProfile,
      metadata: metadata ?? this.metadata,
    );
  }

  factory CockpitTargetHandle.fromAppHandle(CockpitAppHandle app) {
    return CockpitTargetHandle(
      targetId: app.appId,
      targetKind: CockpitTargetKind.flutterApp,
      platform: app.platform,
      deviceId: app.deviceId,
      projectDir: app.projectDir,
      target: app.target,
      connection: CockpitTargetConnection(baseUrl: app.baseUrl),
      launchedAt: app.launchedAt,
      metadata: _targetMetadataForApp(app),
    );
  }

  /// Rebinds this registered target to the current handle for the same app.
  ///
  /// Flutter attach and hot-restart can replace the runtime app identity while
  /// the public workspace target remains stable. Capability information and
  /// target kind belong to that stable target; connection and runtime metadata
  /// must follow the refreshed app handle atomically.
  CockpitTargetHandle withAppHandle(CockpitAppHandle app) {
    return CockpitTargetHandle(
      targetId: app.appId,
      targetKind: targetKind,
      platform: app.platform,
      deviceId: app.deviceId,
      projectDir: app.projectDir,
      target: app.target,
      connection: CockpitTargetConnection(baseUrl: app.baseUrl),
      launchedAt: app.launchedAt,
      capabilityProfile: capabilityProfile,
      metadata: _targetMetadataForApp(app, base: metadata),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'targetKind': targetKind.name,
    'platform': platform,
    'deviceId': deviceId,
    'projectDir': projectDir,
    'target': target,
    'connection': connection.toJson(),
    'launchedAt': launchedAt.toUtc().toIso8601String(),
    if (capabilityProfile != null)
      'capabilityProfile': capabilityProfile!.toJson(),
    'metadata': metadata,
  };

  factory CockpitTargetHandle.fromJson(Map<String, Object?> json) {
    final connectionJson = json['connection']! as Map<Object?, Object?>;
    final capabilityProfileJson =
        json['capabilityProfile'] as Map<Object?, Object?>?;
    final metadataJson = json['metadata'] as Map<Object?, Object?>?;
    return CockpitTargetHandle(
      targetId: json['targetId']! as String,
      targetKind: CockpitTargetKind.fromJson(json['targetKind']),
      platform: json['platform']! as String,
      deviceId: json['deviceId']! as String,
      projectDir: json['projectDir']! as String,
      target: json['target']! as String,
      connection: CockpitTargetConnection.fromJson(
        Map<String, Object?>.from(connectionJson),
      ),
      launchedAt: DateTime.parse(json['launchedAt']! as String).toUtc(),
      capabilityProfile: capabilityProfileJson == null
          ? null
          : CockpitCapabilityProfile.fromJson(
              Map<String, Object?>.from(capabilityProfileJson),
            ),
      metadata: metadataJson == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(metadataJson),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitTargetHandle &&
            other.targetId == targetId &&
            other.targetKind == targetKind &&
            other.platform == platform &&
            other.deviceId == deviceId &&
            other.projectDir == projectDir &&
            other.target == target &&
            other.connection == connection &&
            other.launchedAt == launchedAt &&
            other.capabilityProfile == capabilityProfile &&
            _metadataEquality.equals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
    targetId,
    targetKind,
    platform,
    deviceId,
    projectDir,
    target,
    connection,
    launchedAt,
    capabilityProfile,
    _metadataEquality.hash(metadata),
  );
}

Map<String, Object?> _targetMetadataForApp(
  CockpitAppHandle app, {
  Map<String, Object?> base = const <String, Object?>{},
}) {
  final metadata = Map<String, Object?>.of(base)
    ..['appId'] = app.appId
    ..['appMode'] = app.mode.jsonValue
    ..['supportsHotReload'] = app.supportsHotReload;
  _writeOptionalMetadata(metadata, 'platformAppId', app.platformAppId);
  _writeOptionalMetadata(metadata, 'processId', app.processId);
  _writeOptionalMetadata(
    metadata,
    'remoteSession',
    app.remoteSession?.toJson(),
  );
  _writeOptionalMetadata(metadata, 'supervisorLogPath', app.supervisorLogPath);
  return metadata;
}

void _writeOptionalMetadata(
  Map<String, Object?> metadata,
  String key,
  Object? value,
) {
  if (value == null) {
    metadata.remove(key);
  } else {
    metadata[key] = value;
  }
}
