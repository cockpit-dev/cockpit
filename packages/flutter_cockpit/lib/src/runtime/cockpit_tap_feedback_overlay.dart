import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gesture/cockpit_gesture_action.dart';

final class CockpitTapFeedbackOverlay extends StatelessWidget {
  const CockpitTapFeedbackOverlay({required this.controller, super.key});

  final CockpitTapFeedbackController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        key: const ValueKey<String>('cockpit_tap_feedback_overlay'),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            if (!controller.hasMarkers) {
              return const SizedBox.expand();
            }
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                for (final marker in controller._markersView)
                  Positioned(
                    left: marker.offset.dx - 18,
                    top: marker.offset.dy - 18,
                    child: _CockpitTapFeedbackMarker(
                      marker: marker,
                      key: const ValueKey<String>(
                        'cockpit_tap_feedback_marker',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class CockpitTapFeedbackController extends ChangeNotifier {
  CockpitTapFeedbackController({
    this.markerTtl = const Duration(milliseconds: 850),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration markerTtl;
  final DateTime Function() _clock;
  final List<_CockpitTapFeedbackMarkerModel> _markers =
      <_CockpitTapFeedbackMarkerModel>[];
  final Map<int, Timer> _timers = <int, Timer>{};
  int _nextMarkerId = 0;

  bool get hasMarkers => _markers.isNotEmpty;

  List<_CockpitTapFeedbackMarkerModel> get _markersView =>
      List<_CockpitTapFeedbackMarkerModel>.unmodifiable(_markers);

  void record(CockpitGestureAction action) {
    final geometry = action.geometry;
    final offset =
        action.origin ??
        (geometry == null ? null : Offset(geometry.centerX, geometry.centerY));
    if (offset == null) {
      return;
    }

    final markerId = _nextMarkerId++;
    final marker = _CockpitTapFeedbackMarkerModel(
      id: markerId,
      offset: offset,
      type: action.type,
      createdAt: _clock(),
    );
    _markers.add(marker);
    if (_markers.length > 3) {
      final removed = _markers.removeAt(0);
      _timers.remove(removed.id)?.cancel();
    }
    notifyListeners();

    _timers[markerId]?.cancel();
    _timers[markerId] = Timer(markerTtl, () {
      _timers.remove(markerId);
      _markers.removeWhere((candidate) => candidate.id == markerId);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _markers.clear();
    super.dispose();
  }
}

final class _CockpitTapFeedbackMarker extends StatelessWidget {
  const _CockpitTapFeedbackMarker({required this.marker, super.key});

  final _CockpitTapFeedbackMarkerModel marker;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(marker.type);
    return SizedBox(
      width: 36,
      height: 36,
      child: CustomPaint(painter: _CockpitTapFeedbackPainter(accent: accent)),
    );
  }

  Color _accentFor(CockpitGestureActionType type) {
    return switch (type) {
      CockpitGestureActionType.hover => const Color(0xFF67E8F9),
      CockpitGestureActionType.wheel => const Color(0xFF5EEAD4),
      CockpitGestureActionType.longPress => const Color(0xFFFFC857),
      CockpitGestureActionType.doubleTap => const Color(0xFF7DD3FC),
      CockpitGestureActionType.drag ||
      CockpitGestureActionType.swipe ||
      CockpitGestureActionType.fling => const Color(0xFF38BDF8),
      CockpitGestureActionType.pinchZoom ||
      CockpitGestureActionType.rotate ||
      CockpitGestureActionType.panZoom ||
      CockpitGestureActionType.multiTouch => const Color(0xFFC084FC),
      CockpitGestureActionType.tap => const Color(0xFF99F6E4),
    };
  }
}

final class _CockpitTapFeedbackPainter extends CustomPainter {
  const _CockpitTapFeedbackPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ringPaint = Paint()
      ..color = accent.withAlphaFraction(0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final glowPaint = Paint()
      ..color = accent.withAlphaFraction(0.16)
      ..style = PaintingStyle.fill;
    final crosshairPaint = Paint()
      ..color = Colors.white.withAlphaFraction(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, 18, glowPaint);
    canvas.drawCircle(center, 13.5, ringPaint);
    canvas.drawCircle(
      center,
      4.25,
      Paint()..color = accent.withAlphaFraction(0.95),
    );

    const lineLength = 5.0;
    canvas.drawLine(
      Offset(center.dx - lineLength, center.dy),
      Offset(center.dx + lineLength, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - lineLength),
      Offset(center.dx, center.dy + lineLength),
      crosshairPaint,
    );

    final arcPaint = Paint()
      ..color = accent.withAlphaFraction(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 16),
      -math.pi * 0.7,
      math.pi * 0.45,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CockpitTapFeedbackPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

final class _CockpitTapFeedbackMarkerModel {
  const _CockpitTapFeedbackMarkerModel({
    required this.id,
    required this.offset,
    required this.type,
    required this.createdAt,
  });

  final int id;
  final Offset offset;
  final CockpitGestureActionType type;
  final DateTime createdAt;
}

extension _CockpitColorAlpha on Color {
  Color withAlphaFraction(double alpha) {
    final normalized = alpha.clamp(0.0, 1.0);
    return withAlpha((normalized * 255).round());
  }
}
