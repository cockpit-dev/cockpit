import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/cockpit_demo_acceptance_runner.dart';

void main() {
  test('Web acceptance uses the supported development launch mode', () {
    expect(cockpitDemoLaunchModeForPlatform('web'), 'development');
    expect(cockpitDemoLaunchModeForPlatform('linux'), 'automation');
    expect(cockpitDemoLaunchModeForPlatform('android'), 'automation');
  });

  test('Acceptance CLI allows three minutes for target discovery', () async {
    final result = await Process.run('dart', const <String>[
      'run',
      'tool/verify.dart',
      '--help',
    ]);

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains('--discovery-timeout-seconds    (defaults to "180")'),
    );
  });
}
