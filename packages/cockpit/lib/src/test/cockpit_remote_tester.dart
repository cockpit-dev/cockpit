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
  }) : super(
         automation: CockpitRemoteAutomationAdapter(
           client: client,
           workspaceRoot: workspaceRoot,
         ),
         performance: CockpitRemotePerformanceAdapter(client: client),
       );
}
