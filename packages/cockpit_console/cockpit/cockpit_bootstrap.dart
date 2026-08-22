import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cockpit_console/cockpit_console.dart';
import 'package:cockpit_console/i18n/strings.g.dart';

/// Builds the development-mode wrapper around [CockpitConsoleApp].
///
/// This file lives under `cockpit/` and is never shipped in production. It
/// wraps the production app with [FlutterCockpitApp] so the Cockpit Supervisor
/// can inspect the widget tree, drive typed UI commands, capture screenshots,
/// observe network/runtime state, and hot-reload, all without modifying
/// production code.
Widget buildCockpitConsoleDevelopmentApp() {
  const enableDiagnostics = bool.fromEnvironment(
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
    networkObserver: !enableHttpNetworkObserver
        ? null
        : CockpitHttpNetworkObserver(
            maxRetainedEntries: 80,
            captureFilter: captureConsoleNetworkRequest,
          ),
    runtimeObserverConfiguration: CockpitRuntimeObserverConfiguration(
      enabled: enableRuntimeObserver,
    ),
    diagnostics: CockpitDiagnosticsConfig(
      enableRebuildTracking: enableDiagnostics,
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
  return TranslationProvider(
    child: FlutterCockpitApp(
      config: FlutterCockpitConfig.fromRuntimeConfiguration(configuration),
      child: ProviderScope(
        retry: consoleProviderRetry,
        child: CockpitConsoleApp(
          navigatorObservers: <NavigatorObserver>[
            FlutterCockpit.createNavigatorObserver(),
          ],
        ),
      ),
    ),
  );
}

bool captureConsoleNetworkRequest(String _, Uri uri) {
  final loopback =
      uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
  if (!loopback) return true;
  return !uri.path.startsWith('/api/v2/') && !uri.path.startsWith('/_cockpit/');
}
