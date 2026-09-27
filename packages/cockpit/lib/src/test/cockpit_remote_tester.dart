import 'package:cockpit_test/cockpit_test.dart';

import '../remote/cockpit_remote_automation_adapter.dart';
import '../remote/cockpit_remote_performance_adapter.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_automation_tester.dart';

/// Tester for a release/profile app that embeds the Cockpit bridge.
final class RemoteCockpitTester extends CockpitAutomationTester {
  RemoteCockpitTester({
    required CockpitRemoteSessionClient client,
    required String workspaceRoot,
    required super.initialLocale,
    super.localeProvider,
  }) : _client = client,
       super(
         automation: CockpitRemoteAutomationAdapter(
           client: client,
           workspaceRoot: workspaceRoot,
         ),
         performance: CockpitRemotePerformanceAdapter(client: client),
       );

  final CockpitRemoteSessionClient _client;

  @override
  Future<Set<CockpitTestFeature>> describeFeatures() async {
    final status = await _client.readStatus();
    final capabilities = status.capabilities;
    return Set<CockpitTestFeature>.unmodifiable(<CockpitTestFeature>{
      if (capabilities.supportsInAppControl) CockpitTestFeature.inAppControl,
      if (capabilities.supportsFlutterViewCapture)
        CockpitTestFeature.flutterViewCapture,
      if (capabilities.supportsNativeScreenCapture)
        CockpitTestFeature.nativeScreenCapture,
      if (capabilities.supportsHostAutomation)
        CockpitTestFeature.hostAutomation,
      if (capabilities.supportsViewportResize)
        CockpitTestFeature.viewportResize,
      if (status.performanceCapture) CockpitTestFeature.performanceCapture,
    });
  }
}
