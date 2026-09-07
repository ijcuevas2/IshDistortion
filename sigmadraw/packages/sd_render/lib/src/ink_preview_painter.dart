import 'package:flutter/widgets.dart';
import 'package:sd_ink/sd_ink.dart';

import 'viewport.dart';

/// The in-progress-stroke overlay (§6: "In-progress stroke drawn into a
/// lightweight overlay layer/Picture, committed to the scene on pen-up.
/// Never re-render the whole scene per point.") — a cheap raw polyline
/// through the not-yet-committed sample points, not the actual filled
/// outline [InkStroke.build] eventually produces (running the full
/// smoothing/simplification/curve-fit/offset pipeline on every single
/// pointer-move, for a potentially long stroke, would be exactly the kind
/// of per-point heavy work §6 says not to do here — that whole pipeline
/// runs exactly once, at pen-up).
class InkPreviewPainter extends CustomPainter {
  const InkPreviewPainter({
    required this.points,
    required this.viewport,
    required this.color,
    required this.nominalWidth,
  });

  final List<StrokePoint> points;
  final SigmaViewport viewport;
  final Color color;
  final double nominalWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = nominalWidth * viewport.scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final first = viewport.documentToScreen(
      Offset(points.first.x, points.first.y),
    );
    path.moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final screen = viewport.documentToScreen(Offset(p.x, p.y));
      path.lineTo(screen.dx, screen.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant InkPreviewPainter oldDelegate) =>
      // Not an identity/length/deep-equality check on `points`: the caller
      // (SigmaCanvas) mutates one shared list in place across an entire
      // stroke rather than reassigning it per point (see `_inkPoints`), so
      // identity never changes and length can repeat (e.g. after a point
      // is added then the widget rebuilds for an unrelated reason). This
      // is a small, transient overlay that only exists while a stroke is
      // actively being drawn, so simply always repainting is cheap and,
      // unlike any of those checks, can't under-repaint.
      true;
}
