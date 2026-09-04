import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

/// The `(lo, hi)` range spanning [values] with ~10% padding on each side,
/// or [fallback] if [values] is empty (nothing finite to plot yet) or
/// degenerately flat (padding a zero-width range would divide by zero
/// later). Caps the displayed dynamic range at 100 units even if the true
/// minimum is far lower (e.g. `-infinity` at an exact zero) — otherwise
/// one deep notch would crush the rest of the curve into a flat line at
/// the top of the plot.
(double, double) bodeAxisRange(
  List<double> values, {
  required (double, double) fallback,
}) {
  if (values.isEmpty) return fallback;
  var lo = values.first, hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  lo = lo < hi - 100 ? hi - 100 : lo;
  var range = hi - lo;
  if (range < 1e-9) range = 1;
  final padding = range * 0.1;
  return (lo - padding, hi + padding);
}

/// A classic two-pane Bode plot (§5.11's "Analysis Plot — Bode"):
/// magnitude (dB) on top, unwrapped phase (degrees) below, both against
/// normalized angular frequency `0` to `pi` rad/sample (DC to Nyquist) —
/// see [computeBodePlot]'s own doc comment on why a linear, not log,
/// frequency axis is the right one for a discrete-time transfer function.
///
/// A magnitude value of `+-infinity` (a pole/zero landing exactly on the
/// unit circle at the plotted frequency) is clamped to the chart's own
/// displayed range rather than left off-canvas — the curve visibly runs
/// to the top/bottom edge and stays there, the same convention real
/// plotting tools use. A `NaN` value (only reachable if numerator and
/// denominator are *both* exactly zero at the same frequency — a pole-
/// zero cancellation sitting exactly on the unit circle) breaks the curve
/// at that point instead of connecting through a meaningless value.
class BodePlotPainter extends CustomPainter {
  const BodePlotPainter({required this.points, this.gap = 16});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, an
  /// algebraic loop, or an unresolved coefficient) — still draws the
  /// frame and zero-reference lines so the plot area isn't just blank.
  final List<BodePoint>? points;

  /// Vertical space between the magnitude and phase panes.
  final double gap;

  static const _frameColor = Color(0xFFBDBDBD);
  static const _zeroLineColor = Color(0xFF9E9E9E);
  static const _magnitudeColor = Color(0xFF1565C0);
  static const _phaseColor = Color(0xFF6A1B9A);
  static const _labelStyle = TextStyle(fontSize: 9, color: Color(0xFF616161));

  @override
  void paint(Canvas canvas, Size size) {
    final paneHeight = (size.height - gap) / 2;
    final magnitudeArea = Rect.fromLTWH(0, 0, size.width, paneHeight);
    final phaseArea = Rect.fromLTWH(
      0,
      paneHeight + gap,
      size.width,
      paneHeight,
    );

    final points = this.points;
    final magnitudes = [
      for (final p in points ?? const <BodePoint>[])
        if (p.magnitudeDb.isFinite) p.magnitudeDb,
    ];
    final phases = [
      for (final p in points ?? const <BodePoint>[]) p.phaseDegrees,
    ];

    final (magLo, magHi) = bodeAxisRange(magnitudes, fallback: (-40, 40));
    final (phaseLo, phaseHi) = bodeAxisRange(phases, fallback: (-180, 180));

    _drawPane(
      canvas,
      magnitudeArea,
      title: 'Magnitude (dB)',
      lo: magLo,
      hi: magHi,
      zeroLine: 0,
      points: points?.map((p) => (p.omega, p.magnitudeDb)).toList(),
      curveColor: _magnitudeColor,
    );
    _drawPane(
      canvas,
      phaseArea,
      title: 'Phase (deg)',
      lo: phaseLo,
      hi: phaseHi,
      zeroLine: 0,
      points: points?.map((p) => (p.omega, p.phaseDegrees)).toList(),
      curveColor: _phaseColor,
    );
  }

  void _drawPane(
    Canvas canvas,
    Rect area, {
    required String title,
    required double lo,
    required double hi,
    required double zeroLine,
    required List<(double omega, double value)>? points,
    required Color curveColor,
  }) {
    canvas.drawRect(
      area,
      Paint()
        ..color = _frameColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    double yOf(double value) {
      final clamped = value.clamp(lo, hi);
      return area.bottom - (clamped - lo) / (hi - lo) * area.height;
    }

    if (zeroLine > lo && zeroLine < hi) {
      final y = yOf(zeroLine);
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        Paint()
          ..color = _zeroLineColor
          ..strokeWidth = 1,
      );
    }

    _drawLabel(canvas, hi.toStringAsFixed(0), Offset(area.left + 2, area.top));
    _drawLabel(
      canvas,
      lo.toStringAsFixed(0),
      Offset(area.left + 2, area.bottom - 11),
    );
    _drawLabel(
      canvas,
      title,
      Offset(area.right - title.length * 5.2 - 2, area.top),
    );

    if (points == null || points.isEmpty) return;

    final path = Path();
    var started = false;
    for (final (omega, value) in points) {
      final x = area.left + omega / math.pi * area.width;
      if (value.isNaN) {
        started = false;
        continue;
      }
      final y = yOf(value);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset topLeft) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, topLeft);
  }

  // Always repaints: BodePoint doesn't override `==`, and the panel that
  // owns this painter recomputes a fresh list on every document change
  // anyway — the same reasoning PoleZeroPlotPainter/InkPreviewPainter
  // already document for the same shape of painter.
  @override
  bool shouldRepaint(covariant BodePlotPainter oldDelegate) => true;
}
