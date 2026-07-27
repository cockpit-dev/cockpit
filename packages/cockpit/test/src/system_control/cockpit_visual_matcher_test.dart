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

  test('finds a transparent template across supported image scales', () async {
    final template = img.Image(width: 20, height: 16, numChannels: 4);
    for (var y = 2; y < 14; y += 1) {
      for (var x = 2; x < 18; x += 1) {
        template.setPixelRgba(
          x,
          y,
          (x * 13) % 256,
          (y * 19) % 256,
          ((x + y) * 11) % 256,
          255,
        );
      }
    }
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
  });

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
          threshold: 0.99,
        );

    expect(result.matched, isFalse);
    expect(result.similarity, lessThan(0.99));
    expect(img.decodePng(result.diffPng), isNotNull);
    expect(
      result.baselineSourcePath,
      await File(
        p.join(workspace.path, 'baselines/home.png'),
      ).resolveSymbolicLinks(),
    );
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
        pixel.r,
        pixel.g,
        pixel.b,
        pixel.a,
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
