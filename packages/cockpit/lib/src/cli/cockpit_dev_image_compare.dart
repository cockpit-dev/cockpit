import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

final class CockpitDevImageEvidence {
  const CockpitDevImageEvidence({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
    required this.width,
    required this.height,
  });

  final String path;
  final int sizeBytes;
  final String sha256;
  final int width;
  final int height;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'mediaType': 'image/png',
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'width': width,
    'height': height,
  };
}

final class CockpitDevImageComparison {
  const CockpitDevImageComparison({
    required this.matched,
    required this.dimensionMismatch,
    required this.changedPixelCount,
    required this.totalPixelCount,
    required this.pixelTolerance,
    required this.maximumChangedPixels,
    required this.actual,
    required this.baseline,
    required this.diff,
  });

  final bool matched;
  final bool dimensionMismatch;
  final int changedPixelCount;
  final int totalPixelCount;
  final int pixelTolerance;
  final int maximumChangedPixels;
  final CockpitDevImageEvidence actual;
  final CockpitDevImageEvidence baseline;
  final CockpitDevImageEvidence diff;

  Map<String, Object?> toJson() => <String, Object?>{
    'matched': matched,
    'dimensionMismatch': dimensionMismatch,
    'changedPixelCount': changedPixelCount,
    'totalPixelCount': totalPixelCount,
    'pixelTolerance': pixelTolerance,
    'maximumChangedPixels': maximumChangedPixels,
  };
}

final class CockpitDevImageComparator {
  const CockpitDevImageComparator();

  Future<CockpitDevImageComparison> compare({
    required String actualPath,
    required String baselinePath,
    required String diffPath,
    required int pixelTolerance,
    required int maximumChangedPixels,
  }) async {
    final actual = await _readPng(actualPath, 'actual screenshot');
    final baseline = await _readPng(baselinePath, 'screenshot baseline');
    final width = actual.image.width > baseline.image.width
        ? actual.image.width
        : baseline.image.width;
    final height = actual.image.height > baseline.image.height
        ? actual.image.height
        : baseline.image.height;
    final total = width * height;
    if (maximumChangedPixels > total) {
      throw FormatException(
        '--max-changed-pixels exceeds the $total-pixel comparison canvas.',
      );
    }
    final diff = img.Image(width: width, height: height);
    var changed = 0;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final inActual = x < actual.image.width && y < actual.image.height;
        final inBaseline =
            x < baseline.image.width && y < baseline.image.height;
        var pixelChanged = !inActual || !inBaseline;
        if (!pixelChanged) {
          final left = actual.image.getPixel(x, y);
          final right = baseline.image.getPixel(x, y);
          pixelChanged =
              (left.r - right.r).abs() > pixelTolerance ||
              (left.g - right.g).abs() > pixelTolerance ||
              (left.b - right.b).abs() > pixelTolerance ||
              (left.a - right.a).abs() > pixelTolerance;
        }
        if (pixelChanged) {
          changed += 1;
          diff.setPixelRgba(x, y, 255, 32, 32, 255);
        } else {
          final source = baseline.image.getPixel(x, y);
          final luminance =
              (source.r * 0.2126 + source.g * 0.7152 + source.b * 0.0722)
                  .round();
          diff.setPixelRgba(x, y, luminance, luminance, luminance, 255);
        }
      }
    }
    final diffEvidence = await _writePng(diffPath, img.encodePng(diff));
    final dimensionMismatch =
        actual.image.width != baseline.image.width ||
        actual.image.height != baseline.image.height;
    return CockpitDevImageComparison(
      matched: !dimensionMismatch && changed <= maximumChangedPixels,
      dimensionMismatch: dimensionMismatch,
      changedPixelCount: changed,
      totalPixelCount: total,
      pixelTolerance: pixelTolerance,
      maximumChangedPixels: maximumChangedPixels,
      actual: actual.evidence,
      baseline: baseline.evidence,
      diff: diffEvidence,
    );
  }

  Future<({img.Image image, CockpitDevImageEvidence evidence})> _readPng(
    String path,
    String label,
  ) async {
    final file = File(p.normalize(p.absolute(path)));
    if (!await file.exists()) {
      throw FileSystemException('$label not found.', path);
    }
    final size = await file.length();
    if (size < 1 || size > 512 * 1024 * 1024) {
      throw FormatException('$label size is invalid.');
    }
    final bytes = await file.readAsBytes();
    final image = img.decodePng(bytes);
    if (image == null || image.width < 1 || image.height < 1) {
      throw FormatException('$label is not a valid PNG.');
    }
    final resolved = p.normalize(await file.resolveSymbolicLinks());
    return (
      image: image,
      evidence: CockpitDevImageEvidence(
        path: resolved,
        sizeBytes: size,
        sha256: sha256.convert(bytes).toString(),
        width: image.width,
        height: image.height,
      ),
    );
  }

  Future<CockpitDevImageEvidence> _writePng(
    String path,
    List<int> bytes,
  ) async {
    final destination = File(p.normalize(p.absolute(path)));
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.part-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return (await _readPng(destination.path, 'screenshot diff')).evidence;
  }
}
