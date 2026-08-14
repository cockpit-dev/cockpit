import 'package:flutter_cockpit/src/runtime/cockpit_visual_frame_driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('synthetic visual frames are limited to desktop and web', () {
    for (final platform in <String>[
      'macos',
      'windows',
      'linux',
      'web',
      ' MACOS ',
    ]) {
      expect(
        cockpitSupportsSyntheticVisualFrames(platform),
        isTrue,
        reason: platform,
      );
    }

    for (final platform in <String>[
      'android',
      'ios',
      'fuchsia',
      'unknown',
      '',
    ]) {
      expect(
        cockpitSupportsSyntheticVisualFrames(platform),
        isFalse,
        reason: platform,
      );
    }
  });

  test('unsupported platforms never attempt to drive a frame', () async {
    expect(
      await ensureCockpitVisualFrame(platform: 'android', mayAnimate: true),
      isFalse,
    );
  });
}
