enum CockpitDevelopmentSessionState {
  starting('starting'),
  ready('ready'),
  reloading('reloading'),
  restarting('restarting'),
  stopped('stopped'),
  failed('failed');

  const CockpitDevelopmentSessionState(this.jsonValue);

  final String jsonValue;

  static CockpitDevelopmentSessionState fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported development session state.',
      ),
    );
  }
}

enum CockpitDevelopmentReloadMode {
  hotReload('hot_reload'),
  hotRestart('hot_restart');

  const CockpitDevelopmentReloadMode(this.jsonValue);

  final String jsonValue;

  static CockpitDevelopmentReloadMode fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported development reload mode.',
      ),
    );
  }
}

const Object _cockpitUnsetField = Object();

final class CockpitDevelopmentSessionStatus {
  const CockpitDevelopmentSessionStatus({
    required this.developmentSessionId,
    required this.state,
    required this.appReachable,
    required this.remoteSessionReachable,
    required this.reloadGeneration,
    required this.lastStatusAt,
    this.lastReloadMode,
    this.lastReloadSucceeded,
    this.lastError,
  });

  final String developmentSessionId;
  final CockpitDevelopmentSessionState state;

  /// Whether the platform application process is currently reachable.
  ///
  /// `null` means the selected device or platform target could not be probed;
  /// it must not be treated as proof that the application exited.
  final bool? appReachable;
  final bool remoteSessionReachable;
  final int reloadGeneration;
  final CockpitDevelopmentReloadMode? lastReloadMode;
  final bool? lastReloadSucceeded;
  final String? lastError;
  final DateTime lastStatusAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'developmentSessionId': developmentSessionId,
    'state': state.jsonValue,
    'appReachable': appReachable,
    'remoteSessionReachable': remoteSessionReachable,
    'reloadGeneration': reloadGeneration,
    if (lastReloadMode != null) 'lastReloadMode': lastReloadMode?.jsonValue,
    if (lastReloadSucceeded != null) 'lastReloadSucceeded': lastReloadSucceeded,
    if (lastError != null) 'lastError': lastError,
    'lastStatusAt': lastStatusAt.toUtc().toIso8601String(),
  };

  factory CockpitDevelopmentSessionStatus.fromJson(Map<String, Object?> json) {
    return CockpitDevelopmentSessionStatus(
      developmentSessionId: json['developmentSessionId']! as String,
      state: CockpitDevelopmentSessionState.fromJson(json['state']),
      appReachable: json['appReachable'] as bool?,
      remoteSessionReachable: json['remoteSessionReachable'] as bool? ?? false,
      reloadGeneration: json['reloadGeneration'] as int? ?? 0,
      lastReloadMode: json['lastReloadMode'] == null
          ? null
          : CockpitDevelopmentReloadMode.fromJson(json['lastReloadMode']),
      lastReloadSucceeded: json['lastReloadSucceeded'] as bool?,
      lastError: json['lastError'] as String?,
      lastStatusAt: DateTime.parse(json['lastStatusAt']! as String).toUtc(),
    );
  }

  CockpitDevelopmentSessionStatus copyWith({
    String? developmentSessionId,
    CockpitDevelopmentSessionState? state,
    Object? appReachable = _cockpitUnsetField,
    bool? remoteSessionReachable,
    int? reloadGeneration,
    Object? lastReloadMode = _cockpitUnsetField,
    Object? lastReloadSucceeded = _cockpitUnsetField,
    Object? lastError = _cockpitUnsetField,
    DateTime? lastStatusAt,
  }) {
    return CockpitDevelopmentSessionStatus(
      developmentSessionId: developmentSessionId ?? this.developmentSessionId,
      state: state ?? this.state,
      appReachable: identical(appReachable, _cockpitUnsetField)
          ? this.appReachable
          : appReachable as bool?,
      remoteSessionReachable:
          remoteSessionReachable ?? this.remoteSessionReachable,
      reloadGeneration: reloadGeneration ?? this.reloadGeneration,
      lastReloadMode: identical(lastReloadMode, _cockpitUnsetField)
          ? this.lastReloadMode
          : lastReloadMode as CockpitDevelopmentReloadMode?,
      lastReloadSucceeded: identical(lastReloadSucceeded, _cockpitUnsetField)
          ? this.lastReloadSucceeded
          : lastReloadSucceeded as bool?,
      lastError: identical(lastError, _cockpitUnsetField)
          ? this.lastError
          : lastError as String?,
      lastStatusAt: lastStatusAt ?? this.lastStatusAt,
    );
  }
}
