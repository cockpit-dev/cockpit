import 'package:cockpit_protocol/cockpit_protocol.dart';

enum SessionMonitorSection {
  overview,
  ui,
  logs,
  network,
  activity,
  diagnostics,
}

enum SessionMonitorSeverity { info, success, warning, error }

enum SessionMonitorMessageKind {
  raw,
  projectRefreshFailed,
  refreshFailed,
  stopped,
  bridgeReconnecting,
}

final class SessionMonitorMessage {
  const SessionMonitorMessage._({required this.kind, this.raw, this.count});

  const SessionMonitorMessage.raw(String value)
    : this._(kind: SessionMonitorMessageKind.raw, raw: value);

  const SessionMonitorMessage.projectRefreshFailed()
    : this._(kind: SessionMonitorMessageKind.projectRefreshFailed);

  const SessionMonitorMessage.refreshFailed(int count)
    : this._(kind: SessionMonitorMessageKind.refreshFailed, count: count);

  const SessionMonitorMessage.stopped()
    : this._(kind: SessionMonitorMessageKind.stopped);

  const SessionMonitorMessage.bridgeReconnecting()
    : this._(kind: SessionMonitorMessageKind.bridgeReconnecting);

  final SessionMonitorMessageKind kind;
  final String? raw;
  final int? count;
}

enum SessionMonitorActivityKind {
  discovered,
  connected,
  changed,
  appUnavailable,
  appReachable,
  bridgeConnected,
  bridgeDisconnected,
  routeChanged,
  runtimeError,
  networkFailure,
}

final class SessionMonitorKey {
  const SessionMonitorKey({required this.workspaceId, required this.sessionId});

  final String workspaceId;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SessionMonitorKey &&
      other.workspaceId == workspaceId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(workspaceId, sessionId);
}

final class MonitoredSession {
  const MonitoredSession({
    required this.key,
    required this.projectPath,
    required this.projectName,
    required this.targetId,
    required this.platform,
    required this.deviceId,
    required this.targetKind,
    required this.entrypoint,
    required this.flavor,
    required this.appId,
    required this.state,
    required this.lastSeenAt,
    this.route,
    this.appReachable,
    this.bridgeReachable = false,
    this.reloadGeneration = 0,
    this.runtimeStatusAt,
    this.errorCount = 0,
    this.networkFailureCount = 0,
    this.networkInFlightCount = 0,
    this.message,
  });

  final SessionMonitorKey key;
  final String projectPath;
  final String projectName;
  final String targetId;
  final String platform;
  final String deviceId;
  final CockpitTargetKind targetKind;
  final String? entrypoint;
  final String? flavor;
  final String? appId;
  final String state;
  final DateTime lastSeenAt;
  final String? route;
  final bool? appReachable;
  final bool bridgeReachable;
  final int reloadGeneration;
  final DateTime? runtimeStatusAt;
  final int errorCount;
  final int networkFailureCount;
  final int networkInFlightCount;
  final SessionMonitorMessage? message;

  bool get healthy => state == 'ready' && bridgeReachable;

  bool get live =>
      appReachable == true && state != 'stopped' && state != 'failed';

  MonitoredSession copyWith({
    String? state,
    DateTime? lastSeenAt,
    Object? route = _unset,
    Object? appReachable = _unset,
    bool? bridgeReachable,
    int? reloadGeneration,
    Object? runtimeStatusAt = _unset,
    int? errorCount,
    int? networkFailureCount,
    int? networkInFlightCount,
    Object? message = _unset,
  }) {
    return MonitoredSession(
      key: key,
      projectPath: projectPath,
      projectName: projectName,
      targetId: targetId,
      platform: platform,
      deviceId: deviceId,
      targetKind: targetKind,
      entrypoint: entrypoint,
      flavor: flavor,
      appId: appId,
      state: state ?? this.state,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      route: identical(route, _unset) ? this.route : route as String?,
      appReachable: identical(appReachable, _unset)
          ? this.appReachable
          : appReachable as bool?,
      bridgeReachable: bridgeReachable ?? this.bridgeReachable,
      reloadGeneration: reloadGeneration ?? this.reloadGeneration,
      runtimeStatusAt: identical(runtimeStatusAt, _unset)
          ? this.runtimeStatusAt
          : runtimeStatusAt as DateTime?,
      errorCount: errorCount ?? this.errorCount,
      networkFailureCount: networkFailureCount ?? this.networkFailureCount,
      networkInFlightCount: networkInFlightCount ?? this.networkInFlightCount,
      message: identical(message, _unset)
          ? this.message
          : message as SessionMonitorMessage?,
    );
  }
}

final class SessionMonitorActivity {
  const SessionMonitorActivity({
    required this.at,
    required this.kind,
    required this.severity,
    this.platform,
    this.device,
    this.from,
    this.to,
    this.value,
    this.count,
  });

  final DateTime at;
  final SessionMonitorActivityKind kind;
  final SessionMonitorSeverity severity;
  final String? platform;
  final String? device;
  final String? from;
  final String? to;
  final String? value;
  final int? count;
}

final class SessionMonitorDetail {
  const SessionMonitorDetail({
    this.identity,
    this.ui,
    this.logs,
    this.network,
    this.errors,
    this.sessionLogs,
    this.networkBodies = const <String, Map<String, Object?>>{},
    this.loadingNetworkBodies = const <String>{},
    this.networkBodyErrors = const <String, String>{},
    this.activity = const <SessionMonitorActivity>[],
    this.activityDropped = 0,
    this.loadingSections = const <SessionMonitorSection>{},
    this.sectionErrors = const <SessionMonitorSection, String>{},
    this.updatedAt,
  });

  final Map<String, Object?>? identity;
  final Map<String, Object?>? ui;
  final Map<String, Object?>? logs;
  final Map<String, Object?>? network;
  final Map<String, Object?>? errors;
  final Map<String, Object?>? sessionLogs;
  final Map<String, Map<String, Object?>> networkBodies;
  final Set<String> loadingNetworkBodies;
  final Map<String, String> networkBodyErrors;
  final List<SessionMonitorActivity> activity;
  final int activityDropped;
  final Set<SessionMonitorSection> loadingSections;
  final Map<SessionMonitorSection, String> sectionErrors;
  final DateTime? updatedAt;

  bool loading(SessionMonitorSection section) =>
      loadingSections.contains(section);

  SessionMonitorDetail copyWith({
    Object? identity = _unset,
    Object? ui = _unset,
    Object? logs = _unset,
    Object? network = _unset,
    Object? errors = _unset,
    Object? sessionLogs = _unset,
    Map<String, Map<String, Object?>>? networkBodies,
    Set<String>? loadingNetworkBodies,
    Map<String, String>? networkBodyErrors,
    List<SessionMonitorActivity>? activity,
    int? activityDropped,
    Set<SessionMonitorSection>? loadingSections,
    Map<SessionMonitorSection, String>? sectionErrors,
    DateTime? updatedAt,
  }) {
    return SessionMonitorDetail(
      identity: identical(identity, _unset)
          ? this.identity
          : identity as Map<String, Object?>?,
      ui: identical(ui, _unset) ? this.ui : ui as Map<String, Object?>?,
      logs: identical(logs, _unset) ? this.logs : logs as Map<String, Object?>?,
      network: identical(network, _unset)
          ? this.network
          : network as Map<String, Object?>?,
      errors: identical(errors, _unset)
          ? this.errors
          : errors as Map<String, Object?>?,
      sessionLogs: identical(sessionLogs, _unset)
          ? this.sessionLogs
          : sessionLogs as Map<String, Object?>?,
      networkBodies: networkBodies ?? this.networkBodies,
      loadingNetworkBodies: loadingNetworkBodies ?? this.loadingNetworkBodies,
      networkBodyErrors: networkBodyErrors ?? this.networkBodyErrors,
      activity: activity ?? this.activity,
      activityDropped: activityDropped ?? this.activityDropped,
      loadingSections: loadingSections ?? this.loadingSections,
      sectionErrors: sectionErrors ?? this.sectionErrors,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

final class SessionActivityWindow {
  const SessionActivityWindow({required this.entries, required this.dropped});

  final List<SessionMonitorActivity> entries;
  final int dropped;
}

SessionActivityWindow retainSessionActivity({
  required List<SessionMonitorActivity> existing,
  required int dropped,
  required List<SessionMonitorActivity> additions,
  required int limit,
}) {
  assert(limit > 0);
  if (additions.isEmpty && existing.length <= limit) {
    return SessionActivityWindow(entries: existing, dropped: dropped);
  }

  final additionStart = additions.length > limit ? additions.length - limit : 0;
  final retainedAdditions = additions.sublist(additionStart);
  final existingSlots = limit - retainedAdditions.length;
  final existingStart = existing.length > existingSlots
      ? existing.length - existingSlots
      : 0;
  return SessionActivityWindow(
    entries: List<SessionMonitorActivity>.unmodifiable([
      ...existing.skip(existingStart),
      ...retainedAdditions,
    ]),
    dropped: dropped + additionStart + existingStart,
  );
}

final class SessionMonitorState {
  const SessionMonitorState({
    this.sessions = const <MonitoredSession>[],
    this.details = const <SessionMonitorKey, SessionMonitorDetail>{},
    this.loading = false,
    this.error,
    this.selected,
    this.selectionManual = false,
    this.updatedAt,
  });

  final List<MonitoredSession> sessions;
  final Map<SessionMonitorKey, SessionMonitorDetail> details;
  final bool loading;
  final SessionMonitorMessage? error;
  final SessionMonitorKey? selected;
  final bool selectionManual;
  final DateTime? updatedAt;

  MonitoredSession? get selectedSession {
    final key = selected;
    if (key == null) return null;
    for (final session in sessions) {
      if (session.key == key) return session;
    }
    return null;
  }

  SessionMonitorDetail detail(SessionMonitorKey key) =>
      details[key] ?? const SessionMonitorDetail();

  SessionMonitorState copyWith({
    List<MonitoredSession>? sessions,
    Map<SessionMonitorKey, SessionMonitorDetail>? details,
    bool? loading,
    Object? error = _unset,
    Object? selected = _unset,
    bool? selectionManual,
    DateTime? updatedAt,
  }) {
    return SessionMonitorState(
      sessions: sessions ?? this.sessions,
      details: details ?? this.details,
      loading: loading ?? this.loading,
      error: identical(error, _unset)
          ? this.error
          : error as SessionMonitorMessage?,
      selected: identical(selected, _unset)
          ? this.selected
          : selected as SessionMonitorKey?,
      selectionManual: selectionManual ?? this.selectionManual,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unset = Object();
