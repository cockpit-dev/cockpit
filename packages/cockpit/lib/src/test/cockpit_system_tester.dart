import 'package:cockpit_test/cockpit_test.dart';

import '../system_control/cockpit_system_control_action_service.dart';
import '../system_control/cockpit_system_control_service.dart';
import '../system_control/cockpit_system_test_automation_adapter.dart';
import '../system_control/cockpit_system_test_target.dart';
import 'cockpit_automation_tester.dart';

/// Tester for a release app that exposes no Cockpit integration.
///
/// All commands are routed through the native/system control plane. A
/// performance adapter may be supplied by a platform driver when it can
/// produce a real report; otherwise [CockpitTester.profile] fails explicitly
/// with a capability error.
final class SystemCockpitTester extends CockpitAutomationTester {
  SystemCockpitTester({
    required CockpitSystemTestTarget target,
    required CockpitSystemControlService controlService,
    required CockpitSystemControlActionService actionService,
    required String workspaceRoot,
    required super.initialLocale,
    super.localeProvider,
    super.performance,
  }) : super(
         automation: CockpitSystemTestAutomationAdapter(
           target: target,
           controlService: controlService,
           actionService: actionService,
           workspaceRoot: workspaceRoot,
         ),
       );
}
