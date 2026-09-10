import '../development/cockpit_development_session_handle.dart';
import '../session/cockpit_remote_session_handle.dart';

const Object _cockpitUnsetAppHandleField = Object();

enum CockpitAppMode {
  development('development'),
  automation('automation');

  const CockpitAppMode(this.jsonValue);

  final String jsonValue;

  static CockpitAppMode fromJson(Object? value) {
    return values.firstWhere(
      (candidate) => candidate.jsonValue == value,
      orElse: () =>
          throw ArgumentError.value(value, 'value', 'Unsupported app mode.'),
    );
  }
}

final class CockpitAppHandle {
  const CockpitAppHandle({
    required this.appId,
    required this.mode,
    required this.platform,
    required this.deviceId,
    required this.projectDir,
    required this.target,
    required this.baseUrl,
    required this.launchedAt,
    this.platformAppId,
    this.processId,
    this.supervisorLogPath,
    this.developmentSession,
    this.remoteSession,
  });

  final String appId;
  final CockpitAppMode mode;
  final String platform;
  final String deviceId;
  final String projectDir;
  final String target;
  final String baseUrl;
  final DateTime launchedAt;
  final String? platformAppId;
  final int? processId;
  final String? supervisorLogPath;
  final CockpitDevelopmentSessionHandle? developmentSession;
  final CockpitRemoteSessionHandle? remoteSession;

  /// The network endpoint for this app, authenticated for its remote session.
  ///
  /// Remote-control apps reject requests that lack the session token, so the
  /// endpoint handed to clients carries the token query parameter whenever the
  /// app is bound to a remote session that knows one. The stored [baseUrl]
  /// stays unauthenticated; only this view merges credentials.
  Uri get baseUri {
    final uri = Uri.parse(baseUrl);
    final authToken = remoteSession?.authToken ?? '';
    if (authToken.isEmpty || uri.queryParameters['token'] != null) {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'token': authToken,
      },
    );
  }

  bool get supportsHotReload => mode == CockpitAppMode.development;

  Map<String, Object?> toJson() => <String, Object?>{
    'appId': appId,
    'mode': mode.jsonValue,
    'platform': platform,
    'deviceId': deviceId,
    'projectDir': projectDir,
    'target': target,
    'baseUrl': baseUrl,
    'launchedAt': launchedAt.toUtc().toIso8601String(),
    if (platformAppId != null) 'platformAppId': platformAppId,
    if (processId != null) 'processId': processId,
    'supportsHotReload': supportsHotReload,
    if (supervisorLogPath != null) 'supervisorLogPath': supervisorLogPath,
    if (developmentSession != null)
      'developmentSessionId': developmentSession!.developmentSessionId,
    if (developmentSession != null)
      'supervisorBaseUrl': developmentSession!.supervisorBaseUri.toString(),
    if (developmentSession != null)
      'reloadGeneration': developmentSession!.reloadGeneration,
    if (developmentSession?.vmServiceUri != null)
      'vmServiceUri': developmentSession!.vmServiceUri!.toString(),
    if (developmentSession?.lastReloadAt != null)
      'lastReloadAt': developmentSession!.lastReloadAt!
          .toUtc()
          .toIso8601String(),
    if (developmentSession != null)
      'developmentSession': developmentSession!.toJson(),
    if (remoteSession != null) 'remoteSession': remoteSession!.toJson(),
  };

  factory CockpitAppHandle.fromJson(Map<String, Object?> json) {
    final developmentSessionJson =
        json['developmentSession'] as Map<Object?, Object?>?;
    final remoteSessionJson = json['remoteSession'] as Map<Object?, Object?>?;
    return CockpitAppHandle(
      appId: json['appId']! as String,
      mode: CockpitAppMode.fromJson(json['mode']),
      platform: json['platform']! as String,
      deviceId: json['deviceId']! as String,
      projectDir: json['projectDir']! as String,
      target: json['target']! as String,
      baseUrl: json['baseUrl']! as String,
      launchedAt: DateTime.parse(json['launchedAt']! as String).toUtc(),
      platformAppId: json['platformAppId'] as String?,
      processId:
          json['processId'] as int? ?? remoteSessionJson?['processId'] as int?,
      supervisorLogPath: json['supervisorLogPath'] as String?,
      developmentSession: developmentSessionJson == null
          ? _developmentSessionFromCompactJson(json)
          : CockpitDevelopmentSessionHandle.fromJson(
              Map<String, Object?>.from(developmentSessionJson),
            ),
      remoteSession: remoteSessionJson == null
          ? null
          : CockpitRemoteSessionHandle.fromJson(
              Map<String, Object?>.from(remoteSessionJson),
            ),
    );
  }

  factory CockpitAppHandle.fromDevelopmentSession(
    CockpitDevelopmentSessionHandle handle, {
    String? supervisorLogPath,
  }) {
    return CockpitAppHandle(
      appId: handle.appId,
      mode: CockpitAppMode.development,
      platform: handle.platform,
      deviceId: handle.deviceId,
      projectDir: handle.projectDir,
      target: handle.target,
      baseUrl: handle.appBaseUrl,
      launchedAt: handle.launchedAt,
      platformAppId: handle.remoteSessionHandle?.effectivePlatformAppId,
      processId: handle.remoteSessionHandle?.processId,
      supervisorLogPath: supervisorLogPath,
      developmentSession: handle,
      remoteSession: handle.remoteSessionHandle,
    );
  }

  factory CockpitAppHandle.fromRemoteSession(
    CockpitRemoteSessionHandle handle,
  ) {
    return CockpitAppHandle(
      appId: handle.appId,
      mode: CockpitAppMode.automation,
      platform: handle.platform,
      deviceId: handle.deviceId,
      projectDir: handle.projectDir,
      target: handle.target,
      baseUrl: handle.baseUrl,
      launchedAt: handle.launchedAt,
      platformAppId: handle.effectivePlatformAppId,
      processId: handle.processId,
      remoteSession: handle,
    );
  }

  CockpitAppHandle copyWith({
    String? appId,
    CockpitAppMode? mode,
    String? platform,
    String? deviceId,
    String? projectDir,
    String? target,
    String? baseUrl,
    DateTime? launchedAt,
    Object? platformAppId = _cockpitUnsetAppHandleField,
    Object? processId = _cockpitUnsetAppHandleField,
    Object? supervisorLogPath = _cockpitUnsetAppHandleField,
    Object? developmentSession = _cockpitUnsetAppHandleField,
    Object? remoteSession = _cockpitUnsetAppHandleField,
  }) {
    return CockpitAppHandle(
      appId: appId ?? this.appId,
      mode: mode ?? this.mode,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      projectDir: projectDir ?? this.projectDir,
      target: target ?? this.target,
      baseUrl: baseUrl ?? this.baseUrl,
      launchedAt: launchedAt ?? this.launchedAt,
      platformAppId: identical(platformAppId, _cockpitUnsetAppHandleField)
          ? this.platformAppId
          : platformAppId as String?,
      processId: identical(processId, _cockpitUnsetAppHandleField)
          ? this.processId
          : processId as int?,
      supervisorLogPath:
          identical(supervisorLogPath, _cockpitUnsetAppHandleField)
          ? this.supervisorLogPath
          : supervisorLogPath as String?,
      developmentSession:
          identical(developmentSession, _cockpitUnsetAppHandleField)
          ? this.developmentSession
          : developmentSession as CockpitDevelopmentSessionHandle?,
      remoteSession: identical(remoteSession, _cockpitUnsetAppHandleField)
          ? this.remoteSession
          : remoteSession as CockpitRemoteSessionHandle?,
    );
  }
}

CockpitDevelopmentSessionHandle? _developmentSessionFromCompactJson(
  Map<String, Object?> json,
) {
  final developmentSessionId = json['developmentSessionId'] as String?;
  final supervisorBaseUrl = json['supervisorBaseUrl'] as String?;
  if (developmentSessionId == null ||
      developmentSessionId.isEmpty ||
      supervisorBaseUrl == null ||
      supervisorBaseUrl.isEmpty) {
    return null;
  }
  return CockpitDevelopmentSessionHandle(
    developmentSessionId: developmentSessionId,
    platform: json['platform']! as String,
    deviceId: json['deviceId']! as String,
    projectDir: json['projectDir']! as String,
    target: json['target']! as String,
    appId: json['appId']! as String,
    appBaseUrl: json['baseUrl']! as String,
    supervisorBaseUrl: supervisorBaseUrl,
    launchedAt: DateTime.parse(json['launchedAt']! as String).toUtc(),
    reloadGeneration: json['reloadGeneration'] as int? ?? 0,
    vmServiceUri: json['vmServiceUri'] == null
        ? null
        : Uri.parse(json['vmServiceUri']! as String),
    lastReloadAt: json['lastReloadAt'] == null
        ? null
        : DateTime.parse(json['lastReloadAt']! as String).toUtc(),
  );
}
