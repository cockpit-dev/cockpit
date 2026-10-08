import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import 'cockpit_recorder_panel_widgets.dart';

/// A step row's leading glyph: the interaction kind drawn as a 16-point
/// line glyph inside a 32-point rounded tile of the elevated surface.
///
/// The stroke color is the row's single state channel — replay outcomes,
/// unresolved targets, neutral otherwise — so state stays visible without
/// a color-per-kind rainbow: the glyph shape carries the kind, the color
/// carries the outcome.
final class CockpitRecorderStepGlyph extends StatelessWidget {
  /// Creates a glyph for [kind] stroked in [color].
  const CockpitRecorderStepGlyph({
    required this.kind,
    required this.color,
    super.key,
  });

  final CockpitInteractionStepKind kind;

  /// Stroke color; callers pass the row's state color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const ShapeDecoration(
        color: cockpitRecorderSurfaceElevated,
        shape: cockpitRecorderGlyphShape,
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(16, 16),
          painter: _StepGlyphPainter(kind: kind, color: color),
        ),
      ),
    );
  }
}

final class _StepGlyphPainter extends CustomPainter {
  _StepGlyphPainter({required this.kind, required this.color});

  final CockpitInteractionStepKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;
    switch (kind) {
      case CockpitInteractionStepKind.tap:
        canvas.drawCircle(const Offset(8, 8), 5.2, stroke);
        canvas.drawCircle(const Offset(8, 8), 1.4, fill);
      case CockpitInteractionStepKind.longPress:
        canvas.drawCircle(const Offset(8, 8), 5.2, stroke);
        canvas.drawCircle(const Offset(8, 8), 2.6, fill);
      case CockpitInteractionStepKind.text:
        canvas.drawLine(const Offset(8, 2.5), const Offset(8, 13.5), stroke);
        canvas.drawLine(
          const Offset(5.8, 2.5),
          const Offset(10.2, 2.5),
          stroke,
        );
        canvas.drawLine(
          const Offset(5.8, 13.5),
          const Offset(10.2, 13.5),
          stroke,
        );
      case CockpitInteractionStepKind.scroll:
        _polyline(canvas, stroke, const <Offset>[
          Offset(5, 7.2),
          Offset(8, 4.2),
          Offset(11, 7.2),
        ]);
        _polyline(canvas, stroke, const <Offset>[
          Offset(5, 8.8),
          Offset(8, 11.8),
          Offset(11, 8.8),
        ]);
      case CockpitInteractionStepKind.routeChange:
        canvas.drawLine(const Offset(3.5, 3), const Offset(3.5, 13), stroke);
        canvas.drawLine(const Offset(6, 8), const Offset(12.5, 8), stroke);
        _polyline(canvas, stroke, const <Offset>[
          Offset(9.8, 5.3),
          Offset(12.6, 8),
          Offset(9.8, 10.7),
        ]);
      case CockpitInteractionStepKind.back:
        canvas.drawLine(const Offset(13, 8), const Offset(3.5, 8), stroke);
        _polyline(canvas, stroke, const <Offset>[
          Offset(6.2, 5.3),
          Offset(3.4, 8),
          Offset(6.2, 10.7),
        ]);
      case CockpitInteractionStepKind.marker:
        final path = Path()
          ..moveTo(4.5, 2.5)
          ..lineTo(11.5, 2.5)
          ..lineTo(11.5, 13.5)
          ..lineTo(8, 10.4)
          ..lineTo(4.5, 13.5)
          ..close();
        canvas.drawPath(path, stroke);
      case CockpitInteractionStepKind.note:
        canvas.drawLine(const Offset(3.5, 4), const Offset(12.5, 4), stroke);
        canvas.drawLine(const Offset(3.5, 8), const Offset(12.5, 8), stroke);
        canvas.drawLine(const Offset(3.5, 12), const Offset(9, 12), stroke);
    }
  }

  void _polyline(Canvas canvas, Paint paint, List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StepGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
