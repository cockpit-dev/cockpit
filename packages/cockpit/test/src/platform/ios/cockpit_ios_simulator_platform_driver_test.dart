import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/platform/ios/cockpit_ios_simulator_platform_driver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ios simulator platform driver reports simulator-only native evidence',
    () async {
      final driver = CockpitIosSimulatorPlatformDriver(
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        processRunner: (_, _) async => ProcessResult(1, 0, '', ''),
      );

      final profile = await driver.describeCapabilities();

      expect(profile.targetKind, CockpitTargetKind.flutterApp);
      expect(profile.surfaceKinds, contains(CockpitSurfaceKind.nativeUi));
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.launchApp),
      );
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.runShell),
      );
      expect(
        profile.evidenceCapabilities,
        contains(CockpitEvidenceCapability.nativeScreenshot),
      );
      expect(
        profile.evidenceCapabilities,
        contains(CockpitEvidenceCapability.screenRecording),
      );
      expect(profile.qualityFlags, contains(CockpitQualityFlag.simulatorOnly));
    },
  );

  test(
    'probes simulator shell once and preserves unrelated capabilities',
    () async {
      final calls = <({String executable, List<String> arguments})>[];
      final driver = CockpitIosSimulatorPlatformDriver(
        deviceId: 'SIMULATOR-OK',
        processRunner: (executable, arguments) async {
          calls.add((executable: executable, arguments: arguments));
          return ProcessResult(1, 0, '', '');
        },
      );

      final first = await driver.describeCapabilities();
      final second = await driver.describeCapabilities();

      expect(first, equals(second));
      expect(calls, hasLength(1));
      expect(calls.single.executable, 'xcrun');
      expect(calls.single.arguments, <String>[
        'simctl',
        'spawn',
        'SIMULATOR-OK',
        '/bin/sh',
        '-lc',
        'true',
      ]);
      expect(
        first.actionCapabilities,
        contains(CockpitActionCapability.runShell),
      );
    },
  );

  test('omits simulator shell when simctl probe exits nonzero', () async {
    final driver = CockpitIosSimulatorPlatformDriver(
      deviceId: 'SIMULATOR-EXIT-134',
      processRunner: (_, _) async => ProcessResult(1, 134, '', 'unsupported'),
    );

    final profile = await driver.describeCapabilities();

    expect(
      profile.actionCapabilities,
      isNot(contains(CockpitActionCapability.runShell)),
    );
    expect(
      profile.actionCapabilities,
      contains(CockpitActionCapability.captureScreenshot),
    );
    expect(
      profile.evidenceCapabilities,
      contains(CockpitEvidenceCapability.screenRecording),
    );
  });

  test(
    'omits simulator shell when the probe times out',
    () async {
      final driver = CockpitIosSimulatorPlatformDriver(
        deviceId: 'SIMULATOR-TIMEOUT',
        processRunner: (_, _) => Completer<ProcessResult>().future,
      );

      final profile = await driver.describeCapabilities();

      expect(
        profile.actionCapabilities,
        isNot(contains(CockpitActionCapability.runShell)),
      );
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.launchApp),
      );
    },
    timeout: const Timeout(Duration(seconds: 3)),
  );
}
