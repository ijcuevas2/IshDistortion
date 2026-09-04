import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

import 'pole_zero_painter.dart' show complexToCanvas;

/// Chooses a `unitsPerPixel` scale so every point in [points], plus the
/// origin and the classical Nyquist reference point `-1` (shown even if
/// nothing in [points] reaches it — a reader expects to see where it
/// *would* be), fits within [size] with a margin. Mirrors
/// `pole_zero_painter.dart`'s `scaleFor` — same reasoning, a different
/// source of points to fit.
double nyquistScaleFor(List<NyquistPoint> points, Size size) {
  var maxAbs = 1.0; // keeps the -1 reference point visible even alone.
  for (final p in points) {
    maxAbs = math.max(maxAbs, math.sqrt(p.re * p.re + p.im * p.im));
  }
  final available = math.min(size.width, size.height) / 2 * 0.8;
  return maxAbs / available;
}

/// A Nyquist plot (§5.11's "Analysis Plot — Nyquist"): `H(e^{j*omega})`
/// traced directly in the complex plane over the full closed contour
/// (see `computeNyquistPlot`'s own doc comment on why it's the full
/// contour, not just half). Marks the origin and the classical `-1`
/// reference point (the value a continuous-time Nyquist plot's
/// encirclement-counting stability criterion is stated in terms of) —
/// shown for orientation, since a reader used to Nyquist plots looks for
/// it by reflex, though this project doesn't implement encirclement
/// counting itself (§5.11's pole-zero plot already gives this project's
/// own, simpler stability readout for a discrete-time system: every pole
/// strictly inside the unit circle).
class NyquistPlotPainter extends CustomPainter {
  const NyquistPlotPainter({required this.points});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, an
  /// algebraic loop, or an unresolved coefficient) — still draws the
  /// axes and reference points so the plot area isn't just blank.
  final List<NyquistPoint>? points;

  static const _axisColor = Color(0xFFBDBDBD);
  static const _referenceColor = Color(0xFF9E9E9E);
  static const _curveColor = Color(0xFF1565C0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final points = this.points;
    final scale = nyquistScaleFor(points ?? const [], size);

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

    // The classical "-1" reference point, marked with a small cross.
    final minusOne = complexToCanvas(const Complex(-1), size, scale);
    const markerRadius = 4.0;
    final referenceMarker = Paint()
      ..color = _referenceColor
      ..strokeWidth = 1.5;
    canvas.drawLine(
      minusOne + const Offset(-markerRadius, -markerRadius),
      minusOne + const Offset(markerRadius, markerRadius),
      referenceMarker,
    );
    canvas.drawLine(
      minusOne + const Offset(-markerRadius, markerRadius),
      minusOne + const Offset(markerRadius, -markerRadius),
      referenceMarker,
    );

    if (points == null || points.isEmpty) return;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = complexToCanvas(
        Complex(points[i].re, points[i].im),
        size,
        scale,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    // The contour is closed (omega sweeps the full circle) — a real
    // Nyquist plot is drawn as a closed curve, not left with a visible
    // gap between its first and last sample.
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = _curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // Always repaints: NyquistPoint doesn't override `==`, and the panel
  // that owns this painter recomputes a fresh list on every document
  // change anyway — the same reasoning PoleZeroPlotPainter/
  // BodePlotPainter already document for the same shape of painter.
  @override
  bool shouldRepaint(covariant NyquistPlotPainter oldDelegate) => true;
}
