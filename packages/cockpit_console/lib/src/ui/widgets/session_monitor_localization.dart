import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:flutter/widgets.dart';

String sessionMonitorMessageText(
  BuildContext context,
  SessionMonitorMessage message,
) {
  final strings = context.t.sessions;
  return switch (message.kind) {
    SessionMonitorMessageKind.raw => message.raw ?? '',
    SessionMonitorMessageKind.projectRefreshFailed =>
      strings.refreshProjectFailed,
    SessionMonitorMessageKind.refreshFailed => strings.refreshFailed(
      n: message.count ?? 0,
    ),
    SessionMonitorMessageKind.stopped => strings.stoppedMessage,
    SessionMonitorMessageKind.bridgeReconnecting =>
      strings.bridgeReconnectingMessage,
  };
}

String sessionMonitorStateText(BuildContext context, String state) {
  final status = context.t.sessions.status;
  return switch (state) {
    'ready' => status.live,
    'starting' => status.starting,
    'reloading' => status.reloading,
    'restarting' => status.restarting,
    'checking' => status.checking,
    'failed' => status.failed,
    'unavailable' => status.unavailable,
    'stopped' => status.stopped,
    _ => state,
  };
}

({String label, String detail}) sessionMonitorActivityText(
  BuildContext context,
  SessionMonitorActivity activity,
) {
  final strings = context.t.sessions.activity;
  return switch (activity.kind) {
    SessionMonitorActivityKind.discovered => (
      label: strings.discovered,
      detail: strings.discoveredDetail(
        platform: activity.platform ?? '',
        device: activity.device ?? '',
      ),
    ),
    SessionMonitorActivityKind.connected => (
      label: strings.connected,
      detail: strings.stateDetail(
        from: sessionMonitorStateText(context, activity.from ?? ''),
        to: sessionMonitorStateText(context, activity.to ?? ''),
      ),
    ),
    SessionMonitorActivityKind.changed => (
      label: strings.changed,
      detail: strings.stateDetail(
        from: sessionMonitorStateText(context, activity.from ?? ''),
        to: sessionMonitorStateText(context, activity.to ?? ''),
      ),
    ),
    SessionMonitorActivityKind.appUnavailable => (
      label: strings.appUnavailable,
      detail: activity.value ?? '',
    ),
    SessionMonitorActivityKind.appReachable => (
      label: strings.appReachable,
      detail: activity.value ?? '',
    ),
    SessionMonitorActivityKind.bridgeConnected => (
      label: strings.bridgeConnected,
      detail: strings.sessionDetail(session: activity.value ?? ''),
    ),
    SessionMonitorActivityKind.bridgeDisconnected => (
      label: strings.bridgeDisconnected,
      detail: strings.sessionDetail(session: activity.value ?? ''),
    ),
    SessionMonitorActivityKind.routeChanged => (
      label: strings.routeChanged,
      detail: strings.routeDetail(
        from: activity.from ?? strings.unknownRoute,
        to: activity.to ?? strings.unknownRoute,
      ),
    ),
    SessionMonitorActivityKind.runtimeError => (
      label: strings.runtimeError,
      detail: strings.runtimeErrorDetail(n: activity.count ?? 0),
    ),
    SessionMonitorActivityKind.networkFailure => (
      label: strings.networkFailure,
      detail: strings.networkFailureDetail(n: activity.count ?? 0),
    ),
  };
}
