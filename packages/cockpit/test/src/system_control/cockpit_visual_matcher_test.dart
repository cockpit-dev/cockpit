import 'dart:io';

import 'package:cockpit/src/system_control/cockpit_visual_matcher.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('cockpit-visual-');
  });

  tearDown(() async {
    await workspace.delete(recursive: true);
  });

  test(
    'finds a 16-bit transparent template in an 8-bit screenshot across scales',
    () async {
      final sourceTemplate = img.Image(width: 20, height: 16, numChannels: 4);
      for (var y = 2; y < 14; y += 1) {
        for (var x = 2; x < 18; x += 1) {
          sourceTemplate.setPixelRgba(
            x,
            y,
            (x * 13) % 256,
            (y * 19) % 256,
            ((x + y) * 11) % 256,
            255,
          );
        }
      }
      final template = sourceTemplate.convert(format: img.Format.uint16);
      final scaled = img.copyResize(
        template,
        width: 23,
        height: 18,
        interpolation: img.Interpolation.linear,
      );
      final screenshot = img.Image(width: 120, height: 80, numChannels: 4);
      img.fill(screenshot, color: img.ColorRgba8(22, 28, 35, 255));
      _copyImage(scaled, screenshot, x: 41, y: 27);
      await _writePng(workspace, 'assets/template.png', template);
      final screenshotFile = await _writePng(
        workspace,
        'actual/screenshot.png',
        screenshot,
      );

      final result = await CockpitVisualMatcher(workspaceRoot: workspace.path)
          .findTemplate(
            screenshotPath: screenshotFile.path,
            templateReference: 'assets/template.png',
            threshold: 0.98,
          );

      expect(
        result.matched,
        isTrue,
        reason:
            'similarity=${result.similarity}, '
            'bounds=${result.x},${result.y},${result.width},${result.height}',
      );
      expect(result.similarity, greaterThanOrEqualTo(0.98));
      expect(result.x, 41);
      expect(result.y, 27);
      expect(result.width, 23);
      expect(result.height, 18);
    },
  );

  test('compares complete screenshots and emits an offline diff', () async {
    final baseline = img.Image(width: 32, height: 24, numChannels: 4);
    img.fill(baseline, color: img.ColorRgba8(40, 80, 120, 255));
    final actual = img.copyResize(baseline, width: 32, height: 24);
    for (var y = 4; y < 12; y += 1) {
      for (var x = 8; x < 20; x += 1) {
        actual.setPixelRgba(x, y, 220, 30, 50, 255);
      }
    }
    await _writePng(workspace, 'baselines/home.png', baseline);
    final actualFile = await _writePng(workspace, 'actual/home.png', actual);

    final result = await CockpitVisualMatcher(workspaceRoot: workspace.path)
        .compareScreenshot(
          screenshotPath: actualFile.path,
          baselineReference: 'baselines/home.png',
          pixelTolerance: 0.05,
          maxDifferingPixelRatio: 0.1,
        );

    expect(result.matched, isFalse);
    expect(result.differingPixelRatio, greaterThan(0.1));
    expect(result.differingPixelCount, 96);
    expect(result.totalPixelCount, 768);
    expect(img.decodePng(result.diffPng), isNotNull);
    expect(
      result.baselineSourcePath,
      await File(
        p.join(workspace.path, 'baselines/home.png'),
      ).resolveSymbolicLinks(),
    );
  });

  test('compares a locator-scoped screenshot crop without resizing', () async {
    final screenshot = img.Image(width: 100, height: 80, numChannels: 4);
    img.fill(screenshot, color: img.ColorRgba8(12, 18, 24, 255));
    for (var y = 20; y < 60; y += 1) {
      for (var x = 25; x < 75; x += 1) {
        screenshot.setPixelRgba(x, y, 40, 90, 160, 255);
      }
    }
    final baseline = img.copyCrop(
      screenshot,
      x: 25,
      y: 20,
      width: 50,
      height: 40,
    );
    final screenshotFile = await _writePng(
      workspace,
      'actual/cropped.png',
      screenshot,
    );
    await _writePng(workspace, 'baselines/cropped.png', baseline);

    final result = await CockpitVisualMatcher(workspaceRoot: workspace.path)
        .compareScreenshot(
          screenshotPath: screenshotFile.path,
          baselineReference: 'baselines/cropped.png',
          pixelTolerance: 0,
          maxDifferingPixelRatio: 0,
          crop: const CockpitVisualCrop(
            left: 0.25,
            top: 0.25,
            right: 0.75,
            bottom: 0.75,
          ),
        );

    expect(result.matched, isTrue);
    expect(result.width, 50);
    expect(result.height, 40);
    expect(result.differingPixelCount, 0);
  });

  test('compares equivalent mixed-bit-depth screenshots', () async {
    final actual = img.Image(width: 2, height: 1, numChannels: 4);
    actual
      ..setPixelRgba(0, 0, 40, 90, 160, 255)
      ..setPixelRgba(1, 0, 220, 30, 50, 255);
    final baseline = actual.convert(format: img.Format.uint16);
    final actualFile = await _writePng(
      workspace,
      'actual/mixed-depth.png',
      actual,
    );
    await _writePng(workspace, 'baselines/mixed-depth.png', baseline);

    final result = await CockpitVisualMatcher(workspaceRoot: workspace.path)
        .compareScreenshot(
          screenshotPath: actualFile.path,
          baselineReference: 'baselines/mixed-depth.png',
          pixelTolerance: 0,
          maxDifferingPixelRatio: 0,
        );

    expect(result.matched, isTrue);
    expect(result.differingPixelCount, 0);
    expect(result.matchingPixelRatio, 1);
  });
}

void _copyImage(
  img.Image source,
  img.Image destination, {
  required int x,
  required int y,
}) {
  for (var sourceY = 0; sourceY < source.height; sourceY += 1) {
    for (var sourceX = 0; sourceX < source.width; sourceX += 1) {
      final pixel = source.getPixel(sourceX, sourceY);
      if (pixel.a == 0) continue;
      destination.setPixelRgba(
        x + sourceX,
        y + sourceY,
        pixel.rNormalized * destination.maxChannelValue,
        pixel.gNormalized * destination.maxChannelValue,
        pixel.bNormalized * destination.maxChannelValue,
        pixel.aNormalized * destination.maxChannelValue,
      );
    }
  }
}

Future<File> _writePng(
  Directory root,
  String relativePath,
  img.Image image,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(img.encodePng(image), flush: true);
  return file;
}
