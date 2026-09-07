import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

import 'bode_plot_painter.dart' show bodeAxisRange;

/// A group-delay plot (§5.11's "Analysis Plot — group delay"): delay in
/// samples (vertical) against normalized angular frequency `0` to `pi`
/// rad/sample (horizontal, DC to Nyquist) — the same single-curve shape
/// as one of `BodePlotPainter`'s own two panes, deliberately not sharing
/// its private pane-drawing method (that would mean either exposing it
/// or passing this painter's own colors/labels through a wider public
/// surface than the reuse is worth for one more curve-vs-omega plot).
/// Reuses `bodeAxisRange` directly for the vertical range, the same way
/// `spectrogramMagnitudeRange` already does.
class GroupDelayPainter extends CustomPainter {
  const GroupDelayPainter({required this.points});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, an
  /// algebraic loop, or an unresolved coefficient) — still draws the
  /// frame and zero-reference line so the plot area isn't just blank.
  final List<GroupDelayPoint>? points;

  static const _frameColor = Color(0xFFBDBDBD);
  static const _zeroLineColor = Color(0xFF9E9E9E);
  static const _curveColor = Color(0xFF2E7D32);
  static const _labelStyle = TextStyle(fontSize: 9, color: Color(0xFF616161));

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      area,
      Paint()
        ..color = _frameColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final points = this.points;
    final delays = [
      for (final p in points ?? const <GroupDelayPoint>[]) p.delaySamples,
    ];
    final (lo, hi) = bodeAxisRange(delays, fallback: (-1, 5));

    double yOf(double value) {
      final clamped = value.clamp(lo, hi);
      return area.bottom - (clamped - lo) / (hi - lo) * area.height;
    }

    if (0 > lo && 0 < hi) {
      final y = yOf(0);
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        Paint()
          ..color = _zeroLineColor
          ..strokeWidth = 1,
      );
    }

    _drawLabel(canvas, hi.toStringAsFixed(1), Offset(area.left + 2, area.top));
    _drawLabel(
      canvas,
      lo.toStringAsFixed(1),
      Offset(area.left + 2, area.bottom - 11),
    );
    _drawLabel(
      canvas,
      'Group delay (samples)',
      Offset(area.right - 130, area.top),
    );

    if (points == null || points.isEmpty) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = area.left + points[i].omega / math.pi * area.width;
      final y = yOf(points[i].delaySamples);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _curveColor
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

  // Always repaints: GroupDelayPoint doesn't override `==`, and the
  // panel that owns this painter recomputes a fresh list on every
  // document change anyway — the same reasoning every other analysis
  // painter in this package already documents.
  @override
  bool shouldRepaint(covariant GroupDelayPainter oldDelegate) => true;
}
