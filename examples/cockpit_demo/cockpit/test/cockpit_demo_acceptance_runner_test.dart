import 'package:flutter_test/flutter_test.dart';

import '../tool/src/cockpit_demo_acceptance_runner.dart';

void main() {
  test('Web acceptance uses the supported development launch mode', () {
    expect(cockpitDemoLaunchModeForPlatform('web'), 'development');
    expect(cockpitDemoLaunchModeForPlatform('linux'), 'automation');
    expect(cockpitDemoLaunchModeForPlatform('android'), 'automation');
  });
}
