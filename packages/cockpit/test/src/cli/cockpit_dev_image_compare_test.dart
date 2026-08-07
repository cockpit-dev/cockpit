import 'dart:io';

import 'package:cockpit/src/cli/cockpit_dev_image_compare.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-dev-compare-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('compares exact RGBA channels with an integer tolerance', () async {
    final actual = img.Image(width: 2, height: 2);
    final baseline = img.Image(width: 2, height: 2);
    img.fill(actual, color: img.ColorRgba8(20, 30, 40, 255));
    img.fill(baseline, color: img.ColorRgba8(20, 30, 40, 255));
    actual.setPixelRgba(1, 1, 30, 30, 40, 255);
    final actualPath = p.join(temporary.path, 'actual.png');
    final baselinePath = p.join(temporary.path, 'baseline.png');
    await File(actualPath).writeAsBytes(img.encodePng(actual));
    await File(baselinePath).writeAsBytes(img.encodePng(baseline));

    final failed = await const CockpitDevImageComparator().compare(
      actualPath: actualPath,
      baselinePath: baselinePath,
      diffPath: p.join(temporary.path, 'failed-diff.png'),
      pixelTolerance: 9,
      maximumChangedPixels: 0,
    );
    final passed = await const CockpitDevImageComparator().compare(
      actualPath: actualPath,
      baselinePath: baselinePath,
      diffPath: p.join(temporary.path, 'passed-diff.png'),
      pixelTolerance: 10,
      maximumChangedPixels: 0,
    );

    expect(failed.matched, isFalse);
    expect(failed.changedPixelCount, 1);
    expect(passed.matched, isTrue);
    expect(passed.changedPixelCount, 0);
    expect(p.isAbsolute(failed.diff.path), isTrue);
    expect(failed.diff.sha256, hasLength(64));
  });

  test(
    'dimension mismatch fails regardless of changed-pixel allowance',
    () async {
      final actual = img.Image(width: 2, height: 2);
      final baseline = img.Image(width: 1, height: 2);
      img.fill(actual, color: img.ColorRgba8(10, 10, 10, 255));
      img.fill(baseline, color: img.ColorRgba8(10, 10, 10, 255));
      final actualPath = p.join(temporary.path, 'actual.png');
      final baselinePath = p.join(temporary.path, 'baseline.png');
      await File(actualPath).writeAsBytes(img.encodePng(actual));
      await File(baselinePath).writeAsBytes(img.encodePng(baseline));

      final result = await const CockpitDevImageComparator().compare(
        actualPath: actualPath,
        baselinePath: baselinePath,
        diffPath: p.join(temporary.path, 'diff.png'),
        pixelTolerance: 255,
        maximumChangedPixels: 4,
      );

      expect(result.dimensionMismatch, isTrue);
      expect(result.matched, isFalse);
      expect(result.changedPixelCount, 2);
    },
  );
}
