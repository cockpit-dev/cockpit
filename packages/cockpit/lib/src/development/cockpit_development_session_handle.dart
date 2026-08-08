import '../session/cockpit_remote_session_handle.dart';

const Object _cockpitUnsetDevelopmentSessionHandleField = Object();

enum CockpitDevelopmentLaunchMode {
  development('development');

  const CockpitDevelopmentLaunchMode(this.jsonValue);

  final String jsonValue;

  static CockpitDevelopmentLaunchMode fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported development launch mode.',
      ),
    );
  }
}

final class CockpitDevelopmentSessionHandle {
  const CockpitDevelopmentSessionHandle({
    required this.developmentSessionId,
    required this.platform,
    required this.deviceId,
    required this.projectDir,
    required this.target,
    required this.appId,
    required this.appBaseUrl,
    required this.supervisorBaseUrl,
    required this.launchedAt,
    required this.reloadGeneration,
    this.launchMode = CockpitDevelopmentLaunchMode.development,
    this.flavor,
    this.flutterVersion,
    this.bindHost,
    this.reloadRecoverable = true,
    this.remoteSessionHandle,
    this.vmServiceUri,
    this.lastReloadAt,
  });

  final String developmentSessionId;
  final String platform;
  final String deviceId;
  final String projectDir;
  final String target;
  final String appId;
  final String appBaseUrl;
  final String supervisorBaseUrl;
  final CockpitDevelopmentLaunchMode launchMode;
  final String? flavor;
  final String? flutterVersion;
  final String? bindHost;
  final bool reloadRecoverable;
  final CockpitRemoteSessionHandle? remoteSessionHandle;
  final Uri? vmServiceUri;
  final DateTime launchedAt;
  final DateTime? lastReloadAt;
  final int reloadGeneration;

  Uri get baseUri => Uri.parse(appBaseUrl);

  Uri get supervisorBaseUri => Uri.parse(supervisorBaseUrl);

  Map<String, Object?> toJson() => <String, Object?>{
    'developmentSessionId': developmentSessionId,
    'platform': platform,
    'deviceId': deviceId,
    'projectDir': projectDir,
    'target': target,
    'appId': appId,
    'appBaseUrl': appBaseUrl,
    'supervisorBaseUrl': supervisorBaseUrl,
    'launchMode': launchMode.jsonValue,
    if (flavor != null) 'flavor': flavor,
    if (flutterVersion != null) 'flutterVersion': flutterVersion,
    if (bindHost != null) 'bindHost': bindHost,
    'reloadRecoverable': reloadRecoverable,
    if (remoteSessionHandle != null)
      'remoteSessionHandle': remoteSessionHandle!.toJson(),
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri!.toString(),
    'launchedAt': launchedAt.toUtc().toIso8601String(),
    if (lastReloadAt != null)
      'lastReloadAt': lastReloadAt!.toUtc().toIso8601String(),
    'reloadGeneration': reloadGeneration,
  };

  factory CockpitDevelopmentSessionHandle.fromJson(Map<String, Object?> json) {
    final remoteSessionHandleJson =
        json['remoteSessionHandle'] as Map<Object?, Object?>?;
    return CockpitDevelopmentSessionHandle(
      developmentSessionId: json['developmentSessionId']! as String,
      platform: json['platform']! as String,
      deviceId: json['deviceId']! as String,
      projectDir: json['projectDir']! as String,
      target: json['target']! as String,
      appId: json['appId']! as String,
      appBaseUrl: json['appBaseUrl']! as String,
      supervisorBaseUrl: json['supervisorBaseUrl']! as String,
      launchMode: json['launchMode'] == null
          ? CockpitDevelopmentLaunchMode.development
          : CockpitDevelopmentLaunchMode.fromJson(json['launchMode']),
      flavor: json['flavor'] as String?,
      flutterVersion: json['flutterVersion'] as String?,
      bindHost: json['bindHost'] as String?,
      reloadRecoverable: json['reloadRecoverable'] as bool? ?? false,
      remoteSessionHandle: remoteSessionHandleJson == null
          ? null
          : CockpitRemoteSessionHandle.fromJson(
              Map<String, Object?>.from(remoteSessionHandleJson),
            ),
      vmServiceUri: json['vmServiceUri'] == null
          ? null
          : Uri.parse(json['vmServiceUri']! as String),
      launchedAt: DateTime.parse(json['launchedAt']! as String).toUtc(),
      lastReloadAt: json['lastReloadAt'] == null
          ? null
          : DateTime.parse(json['lastReloadAt']! as String).toUtc(),
      reloadGeneration: json['reloadGeneration'] as int? ?? 0,
    );
  }

  CockpitDevelopmentSessionHandle copyWith({
    String? developmentSessionId,
    String? platform,
    String? deviceId,
    String? projectDir,
    String? target,
    String? appId,
    String? appBaseUrl,
    String? supervisorBaseUrl,
    CockpitDevelopmentLaunchMode? launchMode,
    Object? flavor = _cockpitUnsetDevelopmentSessionHandleField,
    Object? flutterVersion = _cockpitUnsetDevelopmentSessionHandleField,
    Object? bindHost = _cockpitUnsetDevelopmentSessionHandleField,
    bool? reloadRecoverable,
    Object? remoteSessionHandle = _cockpitUnsetDevelopmentSessionHandleField,
    Object? vmServiceUri = _cockpitUnsetDevelopmentSessionHandleField,
    DateTime? launchedAt,
    Object? lastReloadAt = _cockpitUnsetDevelopmentSessionHandleField,
    int? reloadGeneration,
  }) {
    return CockpitDevelopmentSessionHandle(
      developmentSessionId: developmentSessionId ?? this.developmentSessionId,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      projectDir: projectDir ?? this.projectDir,
      target: target ?? this.target,
      appId: appId ?? this.appId,
      appBaseUrl: appBaseUrl ?? this.appBaseUrl,
      supervisorBaseUrl: supervisorBaseUrl ?? this.supervisorBaseUrl,
      launchMode: launchMode ?? this.launchMode,
      flavor: identical(flavor, _cockpitUnsetDevelopmentSessionHandleField)
          ? this.flavor
          : flavor as String?,
      flutterVersion:
          identical(flutterVersion, _cockpitUnsetDevelopmentSessionHandleField)
          ? this.flutterVersion
          : flutterVersion as String?,
      bindHost: identical(bindHost, _cockpitUnsetDevelopmentSessionHandleField)
          ? this.bindHost
          : bindHost as String?,
      reloadRecoverable: reloadRecoverable ?? this.reloadRecoverable,
      remoteSessionHandle:
          identical(
            remoteSessionHandle,
            _cockpitUnsetDevelopmentSessionHandleField,
          )
          ? this.remoteSessionHandle
          : remoteSessionHandle as CockpitRemoteSessionHandle?,
      vmServiceUri:
          identical(vmServiceUri, _cockpitUnsetDevelopmentSessionHandleField)
          ? this.vmServiceUri
          : vmServiceUri as Uri?,
      launchedAt: launchedAt ?? this.launchedAt,
      lastReloadAt:
          identical(lastReloadAt, _cockpitUnsetDevelopmentSessionHandleField)
          ? this.lastReloadAt
          : lastReloadAt as DateTime?,
      reloadGeneration: reloadGeneration ?? this.reloadGeneration,
    );
  }
}
