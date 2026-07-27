import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

final class CockpitVisualTemplateMatch {
  const CockpitVisualTemplateMatch({
    required this.matched,
    required this.similarity,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.screenshotWidth,
    required this.screenshotHeight,
    required this.templateSourcePath,
  });

  final bool matched;
  final double similarity;
  final int x;
  final int y;
  final int width;
  final int height;
  final int screenshotWidth;
  final int screenshotHeight;
  final String templateSourcePath;
}

final class CockpitVisualComparison {
  const CockpitVisualComparison({
    required this.matched,
    required this.similarity,
    required this.width,
    required this.height,
    required this.baselineWidth,
    required this.baselineHeight,
    required this.dimensionMismatch,
    required this.diffPng,
    required this.baselineSourcePath,
  });

  final bool matched;
  final double similarity;
  final int width;
  final int height;
  final int baselineWidth;
  final int baselineHeight;
  final bool dimensionMismatch;
  final Uint8List diffPng;
  final String baselineSourcePath;
}

final class CockpitVisualMatcher {
  CockpitVisualMatcher({required String workspaceRoot})
    : _workspaceRoot = p.normalize(p.absolute(workspaceRoot));

  static const List<double> _templateScales = <double>[
    0.75,
    0.875,
    1,
    1.125,
    1.25,
  ];

  final String _workspaceRoot;
  late final Future<String> _canonicalWorkspaceRoot =
      _resolveCanonicalWorkspaceRoot();

  Future<CockpitVisualTemplateMatch> findTemplate({
    required String screenshotPath,
    required String templateReference,
    required double threshold,
  }) async {
    final screenshot = await _decodeFile(
      await _resolveFile(screenshotPath, workspaceRelative: false),
      'screenshot',
    );
    final templateFile = await _resolveFile(
      templateReference,
      workspaceRelative: true,
    );
    final template = await _decodeFile(templateFile, 'visual template');
    _TemplateCandidate? best;
    for (final scale in _templateScales) {
      final width = math.max(1, (template.width * scale).round());
      final height = math.max(1, (template.height * scale).round());
      if (width > screenshot.width || height > screenshot.height) continue;
      final scaled = scale == 1
          ? template
          : img.copyResize(
              template,
              width: width,
              height: height,
              interpolation: img.Interpolation.linear,
            );
      final candidate = _findBestCandidate(screenshot, scaled);
      if (best == null || candidate.similarity > best.similarity) {
        best = candidate;
      }
    }
    if (best == null) {
      throw const FormatException(
        'Visual template is larger than the screenshot at every supported scale.',
      );
    }
    return CockpitVisualTemplateMatch(
      matched: best.similarity >= threshold,
      similarity: best.similarity,
      x: best.x,
      y: best.y,
      width: best.template.width,
      height: best.template.height,
      screenshotWidth: screenshot.width,
      screenshotHeight: screenshot.height,
      templateSourcePath: templateFile.path,
    );
  }

  Future<CockpitVisualComparison> compareScreenshot({
    required String screenshotPath,
    required String baselineReference,
    required double threshold,
  }) async {
    final actual = await _decodeFile(
      await _resolveFile(screenshotPath, workspaceRelative: false),
      'screenshot',
    );
    final baselineFile = await _resolveFile(
      baselineReference,
      workspaceRelative: true,
    );
    final baseline = await _decodeFile(baselineFile, 'screenshot baseline');
    if (actual.width != baseline.width || actual.height != baseline.height) {
      final diff = img.Image(width: actual.width, height: actual.height);
      img.fill(diff, color: img.ColorRgb8(255, 0, 255));
      return CockpitVisualComparison(
        matched: false,
        similarity: 0,
        width: actual.width,
        height: actual.height,
        baselineWidth: baseline.width,
        baselineHeight: baseline.height,
        dimensionMismatch: true,
        diffPng: img.encodePng(diff),
        baselineSourcePath: baselineFile.path,
      );
    }
    final diff = img.Image(width: actual.width, height: actual.height);
    var total = 0.0;
    for (var y = 0; y < actual.height; y += 1) {
      for (var x = 0; x < actual.width; x += 1) {
        final left = actual.getPixel(x, y);
        final right = baseline.getPixel(x, y);
        final red = (left.r - right.r).abs().round();
        final green = (left.g - right.g).abs().round();
        final blue = (left.b - right.b).abs().round();
        final alpha = (left.a - right.a).abs().round();
        total += 1 - (red + green + blue + alpha) / 1020;
        diff.setPixelRgba(
          x,
          y,
          math.min(255, red * 4),
          math.min(255, green * 4),
          math.min(255, blue * 4),
          255,
        );
      }
    }
    final similarity = total / (actual.width * actual.height);
    return CockpitVisualComparison(
      matched: similarity >= threshold,
      similarity: similarity,
      width: actual.width,
      height: actual.height,
      baselineWidth: baseline.width,
      baselineHeight: baseline.height,
      dimensionMismatch: false,
      diffPng: img.encodePng(diff),
      baselineSourcePath: baselineFile.path,
    );
  }

  _TemplateCandidate _findBestCandidate(img.Image source, img.Image template) {
    final anchors = _samplePoints(template, maximum: 64);
    if (anchors.isEmpty) {
      throw const FormatException('Visual template has no visible pixels.');
    }
    final searchPositions =
        (source.width - template.width + 1) *
        (source.height - template.height + 1);
    final stride = math.max(
      math.max(1, math.min(template.width, template.height) ~/ 10),
      math.sqrt(searchPositions / 50000).ceil(),
    );
    final candidates = <_TemplateCandidate>[];
    for (var y = 0; y <= source.height - template.height; y += stride) {
      for (var x = 0; x <= source.width - template.width; x += stride) {
        _retainCandidate(
          candidates,
          _TemplateCandidate(
            x: x,
            y: y,
            similarity: _score(source, template, x, y, anchors),
            template: template,
          ),
          maximum: 8,
        );
      }
    }
    final refinedSamples = _samplePoints(template, maximum: 1024);
    _TemplateCandidate? best;
    final visited = <int>{};
    for (final candidate in candidates) {
      final minX = math.max(0, candidate.x - stride + 1);
      final maxX = math.min(
        source.width - template.width,
        candidate.x + stride - 1,
      );
      final minY = math.max(0, candidate.y - stride + 1);
      final maxY = math.min(
        source.height - template.height,
        candidate.y + stride - 1,
      );
      for (var y = minY; y <= maxY; y += 1) {
        for (var x = minX; x <= maxX; x += 1) {
          if (!visited.add(y * source.width + x)) continue;
          final refined = _TemplateCandidate(
            x: x,
            y: y,
            similarity: _score(source, template, x, y, refinedSamples),
            template: template,
          );
          if (best == null || refined.similarity > best.similarity) {
            best = refined;
          }
        }
      }
    }
    return best ?? candidates.first;
  }

  List<(int, int)> _samplePoints(img.Image image, {required int maximum}) {
    final samples = <(int, int)>[];
    var visibleCount = 0;
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        if (image.getPixel(x, y).a == 0) continue;
        visibleCount += 1;
        if (samples.length < maximum) {
          samples.add((x, y));
          continue;
        }
        final hash = ((x * 73856093) ^ (y * 19349663)) & 0x7fffffff;
        final slot = hash % visibleCount;
        if (slot < maximum) samples[slot] = (x, y);
      }
    }
    return samples;
  }

  double _score(
    img.Image source,
    img.Image template,
    int offsetX,
    int offsetY,
    List<(int, int)> samples,
  ) {
    var total = 0.0;
    var totalWeight = 0.0;
    for (final (x, y) in samples) {
      final expected = template.getPixel(x, y);
      final actual = source.getPixel(offsetX + x, offsetY + y);
      final weight = expected.a / 255;
      total +=
          (1 -
              ((expected.r - actual.r).abs() +
                      (expected.g - actual.g).abs() +
                      (expected.b - actual.b).abs()) /
                  765) *
          weight;
      totalWeight += weight;
    }
    return total / totalWeight;
  }

  void _retainCandidate(
    List<_TemplateCandidate> candidates,
    _TemplateCandidate candidate, {
    required int maximum,
  }) {
    candidates.add(candidate);
    candidates.sort(
      (left, right) => right.similarity.compareTo(left.similarity),
    );
    if (candidates.length > maximum) candidates.removeLast();
  }

  Future<File> _resolveFile(
    String reference, {
    required bool workspaceRelative,
  }) async {
    final candidate = p.normalize(
      p.isAbsolute(reference) ? reference : p.join(_workspaceRoot, reference),
    );
    if (workspaceRelative &&
        !p.equals(candidate, _workspaceRoot) &&
        !p.isWithin(_workspaceRoot, candidate)) {
      throw const FormatException(
        'Visual asset must stay within the workspace.',
      );
    }
    final file = File(candidate);
    if (!await file.exists()) {
      throw FormatException('Visual asset does not exist: $reference');
    }
    final canonical = p.normalize(await file.resolveSymbolicLinks());
    final canonicalWorkspaceRoot = await _canonicalWorkspaceRoot;
    if (workspaceRelative &&
        !p.equals(canonical, canonicalWorkspaceRoot) &&
        !p.isWithin(canonicalWorkspaceRoot, canonical)) {
      throw const FormatException(
        'Visual asset resolves outside the workspace.',
      );
    }
    return File(canonical);
  }

  Future<String> _resolveCanonicalWorkspaceRoot() async =>
      p.normalize(await Directory(_workspaceRoot).resolveSymbolicLinks());

  Future<img.Image> _decodeFile(File file, String role) async {
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw FormatException('$role could not be decoded as an image.');
    }
    return decoded;
  }
}

final class _TemplateCandidate {
  const _TemplateCandidate({
    required this.x,
    required this.y,
    required this.similarity,
    required this.template,
  });

  final int x;
  final int y;
  final double similarity;
  final img.Image template;
}
