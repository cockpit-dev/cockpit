import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../control/cockpit_screenshot_request.dart';
import '../model/cockpit_artifact_ref.dart';
import '../runtime/cockpit_snapshot.dart';
import 'cockpit_captured_screenshot.dart';
import 'cockpit_capture_paths.dart';

final class FlutterViewCapture {
  const FlutterViewCapture();

  Future<CockpitCapturedScreenshot> capture({
    required GlobalKey repaintBoundaryKey,
    required CockpitScreenshotRequest request,
    CockpitSnapshot? snapshot,
    double pixelRatio = 1.0,
    ui.Rect? cropRect,
  }) async {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      // The in-flight frame may belong to an engine that stopped delivering
      // vsync (occluded desktop surface) or park on an already-armed
      // completer that never fires, so the wait stays bounded and the
      // capture proceeds with what the boundary currently shows.
      try {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 250),
        );
      } on TimeoutException {
        // A paused or wedged engine may never finish the in-flight frame.
      }
    }

    final context = repaintBoundaryKey.currentContext;
    if (context == null) {
      throw StateError('CockpitSurface capture boundary is not mounted.');
    }

    final boundary = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError(
        'CockpitSurface capture boundary is not a RepaintBoundary.',
      );
    }

    var image = await boundary.toImage(pixelRatio: pixelRatio);
    if (cropRect != null) {
      final left = (cropRect.left * pixelRatio).floor().clamp(0, image.width);
      final top = (cropRect.top * pixelRatio).floor().clamp(0, image.height);
      final right = (cropRect.right * pixelRatio).ceil().clamp(
        left,
        image.width,
      );
      final bottom = (cropRect.bottom * pixelRatio).ceil().clamp(
        top,
        image.height,
      );
      final width = right - left;
      final height = bottom - top;
      if (width == 0 || height == 0) {
        image.dispose();
        throw StateError('Screenshot crop region is empty.');
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint(),
      );
      final cropped = await recorder.endRecording().toImage(width, height);
      image.dispose();
      image = cropped;
    }
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode CockpitSurface capture as PNG.');
    }

    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    if (bytes.isEmpty) {
      throw StateError('CockpitSurface capture encoded an empty PNG.');
    }

    return CockpitCapturedScreenshot(
      artifact: CockpitArtifactRef(
        role: 'screenshot',
        relativePath: cockpitScreenshotRelativePathFor(request),
      ),
      bytes: bytes,
      snapshot: snapshot,
    );
  }
}
