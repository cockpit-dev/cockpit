import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

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
    child: child,
  );
}
