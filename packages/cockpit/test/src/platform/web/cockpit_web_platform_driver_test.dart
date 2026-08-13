import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/platform/web/cockpit_web_platform_driver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'web launch profile defers generic DOM actions to live CDP discovery',
    () async {
      final driver = CockpitWebPlatformDriver(deviceId: 'chrome');

      final profile = await driver.describeCapabilities();

      expect(profile.targetKind, CockpitTargetKind.browserPage);
      expect(profile.supportsSurface(CockpitSurfaceKind.browserDom), isTrue);
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.captureScreenshot),
      );
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.startRecording),
      );
      expect(
        profile.actionCapabilities,
        contains(CockpitActionCapability.stopRecording),
      );
      expect(
        profile.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.domSnapshot)),
      );
      expect(
        profile.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.windowCapture)),
      );
      expect(
        profile.evidenceCapabilities,
        contains(CockpitEvidenceCapability.screenRecording),
      );
      expect(
        profile.actionCapabilities,
        isNot(contains(CockpitActionCapability.runShell)),
      );
      expect(
        profile.qualityFlags,
        contains(CockpitQualityFlag.requiresBrowserDriver),
      );
    },
  );

  test(
    'web platform driver does not advertise host recording for unsupported browsers',
    () async {
      final driver = CockpitWebPlatformDriver(deviceId: 'safari');

      final profile = await driver.describeCapabilities();

      expect(
        profile.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(
        profile.actionCapabilities,
        isNot(contains(CockpitActionCapability.stopRecording)),
      );
      expect(
        profile.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.screenRecording)),
      );
    },
  );
}
