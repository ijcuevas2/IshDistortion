import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

/// Maps a point on the complex plane to canvas coordinates: centered at
/// [size]'s center, [unitsPerPixel] converting complex-plane distance to
/// screen pixels — the real axis maps to `x`, the imaginary axis to
/// *negative* `y` (screen `y` grows downward, but "up" should read as
/// positive-imaginary, the normal mathematical convention).
Offset complexToCanvas(Complex value, Size size, double unitsPerPixel) {
  final center = Offset(size.width / 2, size.height / 2);
  return Offset(
    center.dx + value.re / unitsPerPixel,
    center.dy - value.im / unitsPerPixel,
  );
}

/// Chooses a `unitsPerPixel` scale so the unit circle — the stability
/// reference every pole is judged against — and every pole/zero in
/// [result] all fit within [size] with a margin. Always shows at least
/// the unit circle even for an empty/trivial [result] (a lone gain block
/// has no poles or zeros at all), growing only as far as it needs to for
/// anything further out.
double scaleFor(PoleZeroResult result, Size size) {
  var maxAbs = 1.0;
  for (final p in result.poles) {
    maxAbs = math.max(maxAbs, p.abs());
  }
  for (final z in result.zeros) {
    maxAbs = math.max(maxAbs, z.abs());
  }
  final available = math.min(size.width, size.height) / 2 * 0.8;
  return maxAbs / available;
}

/// A classic pole-zero plot (§5.11's "Analysis Plot — pole-zero"): the
/// unit circle, axes, poles as `x` markers, zeros as `o` markers. A pole
/// strictly inside the unit circle (visually obvious against the drawn
/// circle) means a stable causal filter — this is the whole point of the
/// plot, not just a decoration.
class PoleZeroPlotPainter extends CustomPainter {
  const PoleZeroPlotPainter({required this.result, this.markerRadius = 5});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, or an
  /// algebraic loop) — still draws the axes and unit circle so the plot
  /// area isn't just blank.
  final PoleZeroResult? result;
  final double markerRadius;

  static const _axisColor = Color(0xFFBDBDBD);
  static const _circleColor = Color(0xFF9E9E9E);
  static const _poleColor = Color(0xFFC62828);
  static const _zeroColor = Color(0xFF1565C0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final result = this.result;
    final scale = result == null
        ? 1 / (math.min(size.width, size.height) / 2 * 0.8)
        : scaleFor(result, size);

    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      Paint()
        ..color = _axisColor
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      Paint()
        ..color = _axisColor
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      1 / scale,
      Paint()
        ..color = _circleColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (result == null) return;

    final poleMarker = Paint()
      ..color = _poleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final pole in result.poles) {
      final p = complexToCanvas(pole, size, scale);
      canvas.drawLine(
        p + Offset(-markerRadius, -markerRadius),
        p + Offset(markerRadius, markerRadius),
        poleMarker,
      );
      canvas.drawLine(
        p + Offset(-markerRadius, markerRadius),
        p + Offset(markerRadius, -markerRadius),
        poleMarker,
      );
    }

    final zeroMarker = Paint()
      ..color = _zeroColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final zero in result.zeros) {
      canvas.drawCircle(
        complexToCanvas(zero, size, scale),
        markerRadius,
        zeroMarker,
      );
    }
  }

  // Always repaints: [PoleZeroResult] doesn't override `==`, and the
  // panel that owns this painter recomputes a fresh one on every
  // document change anyway — a cheap plot like this doesn't need
  // anything cleverer (see InkPreviewPainter's identical reasoning).
  @override
  bool shouldRepaint(covariant PoleZeroPlotPainter oldDelegate) => true;
}
