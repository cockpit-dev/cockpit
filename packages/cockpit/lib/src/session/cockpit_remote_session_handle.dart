import 'package:cockpit_protocol/cockpit_protocol.dart';

const Object _cockpitUnsetRemoteSessionHandleField = Object();

final class CockpitRemoteSessionHandle {
  const CockpitRemoteSessionHandle({
    required this.platform,
    required this.deviceId,
    required this.projectDir,
    required this.target,
    required this.appId,
    this.platformAppId,
    this.platformAppIdKnown = true,
    this.processId,
    required this.host,
    required this.hostPort,
    required this.devicePort,
    required this.baseUrl,
    required this.launchedAt,
    this.authToken = '',
  });

  final String platform;
  final String deviceId;
  final String projectDir;
  final String target;
  final String appId;
  final String? platformAppId;
  final bool platformAppIdKnown;
  final int? processId;
  final String host;
  final int hostPort;
  final int devicePort;
  final String baseUrl;
  final DateTime launchedAt;
  final String authToken;

  Uri get baseUri {
    final uri = Uri.parse(baseUrl);
    if (authToken.isEmpty) return uri;
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'token': authToken,
      },
    );
  }

  String? get effectivePlatformAppId {
    if (!platformAppIdKnown) {
      return null;
    }
    final explicit = platformAppId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fallback = appId.trim();
    return fallback.isEmpty ? null : fallback;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'deviceId': deviceId,
    'projectDir': projectDir,
    'target': target,
    'appId': appId,
    if (platformAppId != null) 'platformAppId': platformAppId,
    if (!platformAppIdKnown) 'platformAppIdKnown': false,
    if (processId != null) 'processId': processId,
    'host': host,
    'hostPort': hostPort,
    'devicePort': devicePort,
    'baseUrl': baseUrl,
    'launchedAt': launchedAt.toUtc().toIso8601String(),
    if (authToken.isNotEmpty) 'authToken': authToken,
  };

  factory CockpitRemoteSessionHandle.fromJson(Map<String, Object?> json) {
    return CockpitRemoteSessionHandle(
      platform: json['platform']! as String,
      deviceId: json['deviceId']! as String,
      projectDir: json['projectDir']! as String,
      target: json['target']! as String,
      appId: json['appId']! as String,
      platformAppId: json['platformAppId'] as String?,
      platformAppIdKnown: json['platformAppIdKnown'] as bool? ?? true,
      processId: json['processId'] as int?,
      host: json['host']! as String,
      hostPort: json['hostPort']! as int,
      devicePort: json['devicePort']! as int,
      baseUrl: json['baseUrl']! as String,
      launchedAt: DateTime.parse(json['launchedAt']! as String).toUtc(),
      authToken: json['authToken'] as String? ?? '',
    );
  }

  CockpitRemoteSessionHandle copyWith({
    String? platform,
    String? deviceId,
    String? projectDir,
    String? target,
    String? appId,
    Object? platformAppId = _cockpitUnsetRemoteSessionHandleField,
    bool? platformAppIdKnown,
    Object? processId = _cockpitUnsetRemoteSessionHandleField,
    String? host,
    int? hostPort,
    int? devicePort,
    String? baseUrl,
    DateTime? launchedAt,
    String? authToken,
  }) {
    return CockpitRemoteSessionHandle(
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      projectDir: projectDir ?? this.projectDir,
      target: target ?? this.target,
      appId: appId ?? this.appId,
      platformAppId:
          identical(platformAppId, _cockpitUnsetRemoteSessionHandleField)
          ? this.platformAppId
          : platformAppId as String?,
      platformAppIdKnown: platformAppIdKnown ?? this.platformAppIdKnown,
      processId: identical(processId, _cockpitUnsetRemoteSessionHandleField)
          ? this.processId
          : processId as int?,
      host: host ?? this.host,
      hostPort: hostPort ?? this.hostPort,
      devicePort: devicePort ?? this.devicePort,
      baseUrl: baseUrl ?? this.baseUrl,
      launchedAt: launchedAt ?? this.launchedAt,
      authToken: authToken ?? this.authToken,
    );
  }

  static CockpitRemoteSessionHandle fromRemoteStatus({
    required String projectDir,
    required String target,
    required String deviceId,
    required String appId,
    String? platformAppId,
    bool platformAppIdKnown = true,
    int? processId,
    required String host,
    required int hostPort,
    required int devicePort,
    required CockpitRemoteSessionStatus status,
    DateTime? launchedAt,
    String? authToken,
  }) {
    return CockpitRemoteSessionHandle(
      platform: status.platform.toLowerCase(),
      deviceId: deviceId,
      projectDir: projectDir,
      target: target,
      appId: appId,
      platformAppId: platformAppId,
      platformAppIdKnown: platformAppIdKnown,
      processId: processId,
      host: host,
      hostPort: hostPort,
      devicePort: devicePort,
      baseUrl: Uri(scheme: 'http', host: host, port: hostPort).toString(),
      launchedAt: (launchedAt ?? DateTime.now()).toUtc(),
      authToken: authToken ?? status.sessionId,
    );
  }
}
