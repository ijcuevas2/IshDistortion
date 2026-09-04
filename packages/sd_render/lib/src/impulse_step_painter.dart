import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

import 'bode_plot_painter.dart' show bodeAxisRange;

/// A combined impulse/step response plot (§5.11's "Analysis Plot —
/// impulse/step stem" — one named item covering both, drawn as two
/// stacked stem/lollipop panes, one vertical line per sample rather
/// than a connected curve, the conventional way a discrete-time
/// response is drawn). Reuses `bodeAxisRange` for each pane's own
/// vertical range, the same way `GroupDelayPainter`/
/// `spectrogramMagnitudeRange` already do.
class ImpulseStepPainter extends CustomPainter {
  const ImpulseStepPainter({
    required this.impulse,
    required this.step,
    this.gap = 16,
  });

  /// `null` when there's nothing to plot yet — see `SpectrogramPainter`'s
  /// own doc comment for why (no source/sink, an algebraic loop, or an
  /// unresolved coefficient).
  final List<ImpulseResponseSample>? impulse;
  final List<ImpulseResponseSample>? step;

  /// Vertical space between the two panes.
  final double gap;

  static const _frameColor = Color(0xFFBDBDBD);
  static const _zeroLineColor = Color(0xFF9E9E9E);
  static const _stemColor = Color(0xFF6A1B9A);
  static const _labelStyle = TextStyle(fontSize: 9, color: Color(0xFF616161));

  @override
  void paint(Canvas canvas, Size size) {
    final paneHeight = (size.height - gap) / 2;
    final impulseArea = Rect.fromLTWH(0, 0, size.width, paneHeight);
    final stepArea = Rect.fromLTWH(0, paneHeight + gap, size.width, paneHeight);

    _drawPane(canvas, impulseArea, title: 'Impulse response', samples: impulse);
    _drawPane(canvas, stepArea, title: 'Step response', samples: step);
  }

  void _drawPane(
    Canvas canvas,
    Rect area, {
    required String title,
    required List<ImpulseResponseSample>? samples,
  }) {
    canvas.drawRect(
      area,
      Paint()
        ..color = _frameColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final values = [
      for (final s in samples ?? const <ImpulseResponseSample>[]) s.value,
    ];
    final (lo, hi) = bodeAxisRange(values, fallback: (-1, 1));

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

    _drawLabel(canvas, title, Offset(area.left + 2, area.top));

    final s = samples;
    if (s == null || s.isEmpty) return;
    final cellWidth = area.width / s.length;
    final zeroY = yOf(0);
    final stemPaint = Paint()
      ..color = _stemColor
      ..strokeWidth = 1.5;
    final headPaint = Paint()..color = _stemColor;
    for (var i = 0; i < s.length; i++) {
      final x = area.left + (i + 0.5) * cellWidth;
      final y = yOf(s[i].value);
      canvas.drawLine(Offset(x, zeroY), Offset(x, y), stemPaint);
      canvas.drawCircle(Offset(x, y), 2, headPaint);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset topLeft) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, topLeft);
  }

  // Always repaints — same reasoning every other analysis painter in
  // this package already documents.
  @override
  bool shouldRepaint(covariant ImpulseStepPainter oldDelegate) => true;
}
