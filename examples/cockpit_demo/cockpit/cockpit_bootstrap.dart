import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:cockpit_demo/src/app/todo_app_service.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/model/todo_settings.dart';

import 'cockpit_launch_environment.dart';

Widget buildCockpitDemoDevelopmentApp() {
  const acceptance = bool.fromEnvironment('COCKPIT_DEMO_ACCEPTANCE');
  const acceptancePlatform = String.fromEnvironment(
    'COCKPIT_DEMO_ACCEPTANCE_PLATFORM',
  );
  const defineFileValue = String.fromEnvironment('COCKPIT_DEMO_DEFINE_FILE');
  const enableDebugDiagnostics = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_DEBUG_DIAGNOSTICS',
  );
  const enableTapFeedback = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_TAP_FEEDBACK',
  );
  const enableHttpNetworkObserver = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_HTTP_NETWORK_OBSERVER',
    defaultValue: true,
  );
  const enableRuntimeObserver = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_RUNTIME_OBSERVER',
    defaultValue: true,
  );

  TodoAppService? service;
  final configuration = FlutterCockpitConfiguration(
    initialRouteName: '/inbox',
    httpNetworkObserver: !enableHttpNetworkObserver
        ? null
        : CockpitHttpNetworkObserverConfiguration(maxRetainedEntries: 80),
    runtimeObserverConfiguration: CockpitRuntimeObserverConfiguration(
      enabled: enableRuntimeObserver,
    ),
    diagnostics: CockpitDiagnosticsConfig(
      enableRebuildTracking: enableDebugDiagnostics,
      enableTapFeedback: enableTapFeedback,
    ),
    remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
      fallback: const CockpitRemoteSessionConfiguration(
        enabled: true,
        host: '127.0.0.1',
        port: 47331,
      ),
    ),
  );

  Widget child = CockpitDemoApp(
    initialRouteName: configuration.initialRouteName,
    navigatorObservers: <NavigatorObserver>[
      FlutterCockpit.createNavigatorObserver(),
    ],
    onServiceReady: (ready) => service = ready,
  );
  if (acceptance) {
    final exposesRuntimeEnvironment = const <String>{
      'linux',
      'macos',
      'windows',
    }.contains(acceptancePlatform);
    final environmentPlatform = exposesRuntimeEnvironment
        ? cockpitLaunchEnvironment('COCKPIT_ACCEPTANCE_PLATFORM')
        : null;
    final environmentInvocation = exposesRuntimeEnvironment
        ? cockpitLaunchEnvironment('COCKPIT_ACCEPTANCE_INVOCATION')
        : null;
    final launchConfigurationLabel = <String>[
      'Cockpit launch configuration',
      'platform=$acceptancePlatform',
      'defineFile=$defineFileValue',
      if (environmentPlatform != null)
        'environmentPlatform=$environmentPlatform',
      if (environmentInvocation != null)
        'environmentInvocation=$environmentInvocation',
    ].join(' ');
    child = CockpitTargetNode(
      registrationId: 'cockpit-launch-configuration',
      keyValue: 'cockpit-launch-configuration',
      tooltip: launchConfigurationLabel,
      typeName: 'LaunchConfiguration',
      child: child,
    );
  }
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.fromRuntimeConfiguration(configuration),
    appStateProvider: (context) => cockpitDemoAppState(
      service: service,
      acceptance: acceptance,
      acceptancePlatform: acceptancePlatform,
      defineFile: defineFileValue,
      httpNetworkObserverEnabled: enableHttpNetworkObserver,
      runtimeObserverEnabled: enableRuntimeObserver,
    ),
    appActions: cockpitDemoAppActions(() => service),
    child: child,
  );
}

/// App-registered quick operations surfaced through Cockpit's `appAction`
/// command. Each handler validates its arguments, persists the setting, and
/// answers with the values now in effect; invalid input throws so the
/// executor reports `appActionFailed` with the message.
Map<String, CockpitAppAction> cockpitDemoAppActions(
  TodoAppService? Function() serviceResolver,
) {
  return <String, CockpitAppAction>{
    'setThemeMode': (context, arguments) async {
      final settings = _requireSettings(serviceResolver, 'setThemeMode');
      final preference = _enumArgument<TodoThemePreference>(
        arguments,
        'mode',
        TodoThemePreference.values,
      );
      await _updateSettings(
        serviceResolver,
        TodoSettings(
          themePreference: preference,
          sortMode: settings.sortMode,
          showCompletedInInbox: settings.showCompletedInInbox,
          compactMode: settings.compactMode,
        ),
      );
      return <String, Object?>{'themeMode': preference.name};
    },
    'setSortMode': (context, arguments) async {
      final settings = _requireSettings(serviceResolver, 'setSortMode');
      final sortMode = _enumArgument<TodoSortMode>(
        arguments,
        'mode',
        TodoSortMode.values,
      );
      await _updateSettings(
        serviceResolver,
        TodoSettings(
          themePreference: settings.themePreference,
          sortMode: sortMode,
          showCompletedInInbox: settings.showCompletedInInbox,
          compactMode: settings.compactMode,
        ),
      );
      return <String, Object?>{'sortMode': sortMode.name};
    },
    'setCompactMode': (context, arguments) async {
      final settings = _requireSettings(serviceResolver, 'setCompactMode');
      final enabled = arguments['enabled'];
      if (enabled is! bool) {
        throw const FormatException(
          'setCompactMode requires a boolean "enabled" argument.',
        );
      }
      await _updateSettings(
        serviceResolver,
        TodoSettings(
          themePreference: settings.themePreference,
          sortMode: settings.sortMode,
          showCompletedInInbox: settings.showCompletedInInbox,
          compactMode: enabled,
        ),
      );
      return <String, Object?>{'compactMode': enabled};
    },
  };
}

TodoSettings _requireSettings(
  TodoAppService? Function() serviceResolver,
  String action,
) {
  final service = serviceResolver();
  if (service == null) {
    throw StateError('The todo service is not ready yet; retry "$action".');
  }
  return service.settingsState.settings;
}

Future<void> _updateSettings(
  TodoAppService? Function() serviceResolver,
  TodoSettings settings,
) {
  final service = serviceResolver();
  if (service == null) {
    throw StateError('The todo service is not ready yet; retry the action.');
  }
  return service.updateSettings(settings);
}

T _enumArgument<T extends Enum>(
  Map<String, Object?> arguments,
  String name,
  List<T> values,
) {
  final value = arguments[name];
  if (value is! String) {
    throw FormatException(
      'Expected a "$name" string argument; got ${value.runtimeType}.',
    );
  }
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException(
    '"$name" must be one of ${values.map((value) => value.name).join(', ')}; '
    'got "$value".',
  );
}

/// The app-authored state surfaced through Cockpit's `describeApp` command:
/// launch configuration plus the live todo service summary. Values under
/// sensitive-looking keys would be masked before leaving the app process, so
/// only non-secret facts belong here.
Map<String, Object?> cockpitDemoAppState({
  required TodoAppService? service,
  required bool acceptance,
  required String acceptancePlatform,
  required String defineFile,
  required bool httpNetworkObserverEnabled,
  required bool runtimeObserverEnabled,
}) {
  final sync = service?.syncState;
  final settings = service?.settingsState.settings;
  return <String, Object?>{
    'acceptance': acceptance,
    'acceptancePlatform': acceptancePlatform,
    'httpNetworkObserverEnabled': httpNetworkObserverEnabled,
    'runtimeObserverEnabled': runtimeObserverEnabled,
    'defineFile': defineFile,
    if (service != null) ...<String, Object?>{
      'syncStatus': sync?.status.name,
      'pendingTaskCount': sync?.pendingTaskCount,
      'failedTaskCount': sync?.failedTaskCount,
      'conflictTaskCount': sync?.conflictTaskCount,
      'taskCount': service.listState.tasks.length,
      'activeTaskCount': service.listState.tasks
          .where((task) => !task.isCompleted)
          .length,
      'themeMode': settings?.themePreference.name,
      'sortMode': settings?.sortMode.name,
      'compactMode': settings?.compactMode,
    },
  };
}
