import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

import 'bode_plot_painter.dart' show bodeAxisRange;

/// The `(lo, hi)` dB range spanning every *finite* magnitude across all
/// of [frames] (a `-infinity` cell — an exact zero in some frame's
/// spectrum — is excluded from the range itself, then clamped into it
/// for display, the same as [BodePoint.magnitudeDb]'s own convention),
/// with padding. Reuses `bode_plot_painter.dart`'s own `bodeAxisRange`
/// directly rather than a second, near-identical implementation — a
/// magnitude-in-dB range with a sensible fallback and a dynamic-range
/// cap is exactly the same problem in both places, just fed a
/// differently-shaped source of values.
(double, double) spectrogramMagnitudeRange(
  List<SpectrogramFrame> frames, {
  (double, double) fallback = (-80, 0),
}) {
  final finite = [
    for (final frame in frames)
      for (final db in frame.magnitudesDb)
        if (db.isFinite) db,
  ];
  return bodeAxisRange(finite, fallback: fallback);
}

/// Maps a magnitude in `[lo, hi]` dB (clamped if outside it) to a simple
/// two-stop heatmap color: dark blue at the low end, bright yellow at
/// the high end — loud enough to read clearly against the axis lines
/// without needing a full perceptually-uniform colormap implementation,
/// which this project doesn't otherwise need anywhere.
Color spectrogramHeatColor(double db, double lo, double hi) {
  final t = hi > lo ? ((db - lo) / (hi - lo)).clamp(0.0, 1.0) : 0.0;
  return Color.lerp(const Color(0xFF0D1B4C), const Color(0xFFFFE066), t)!;
}

/// A spectrogram (§5.11's "Analysis Plot — spectrogram"): time along the
/// horizontal axis (one column per [SpectrogramFrame] in [frames], left
/// to right), frequency along the vertical axis (DC at the bottom, rising
/// to Nyquist at the top — the same "up is higher" convention
/// `PoleZeroPlotPainter`/`NyquistPlotPainter` use for the imaginary
/// axis), and magnitude as color (see [spectrogramHeatColor]).
class SpectrogramPainter extends CustomPainter {
  const SpectrogramPainter({required this.frames});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, an
  /// algebraic loop, or an unresolved coefficient) — still draws the
  /// frame border so the plot area isn't just blank.
  final List<SpectrogramFrame>? frames;

  static const _borderColor = Color(0xFFBDBDBD);

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);

    final frames = this.frames;
    if (frames == null || frames.isEmpty) return;
    final binCount = frames.first.magnitudesDb.length;
    if (binCount == 0) return;

    final (lo, hi) = spectrogramMagnitudeRange(frames);
    final cellWidth = size.width / frames.length;
    final cellHeight = size.height / binCount;

    for (var f = 0; f < frames.length; f++) {
      final magnitudesDb = frames[f].magnitudesDb;
      for (var k = 0; k < binCount; k++) {
        final color = spectrogramHeatColor(magnitudesDb[k], lo, hi);
        // Bin k=0 is DC; drawn at the bottom (screen y grows downward,
        // but "up" should read as higher frequency).
        final y = size.height - (k + 1) * cellHeight;
        canvas.drawRect(
          Rect.fromLTWH(f * cellWidth, y, cellWidth, cellHeight),
          Paint()..color = color,
        );
      }
    }
  }

  // Always repaints: SpectrogramFrame doesn't override `==`, and the
  // panel that owns this painter recomputes a fresh list on every
  // document change anyway — the same reasoning every other analysis
  // painter in this file/package already documents.
  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) => true;
}
