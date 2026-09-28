import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:cockpit_demo/src/app/todo_app_service.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';

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
    child: child,
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
