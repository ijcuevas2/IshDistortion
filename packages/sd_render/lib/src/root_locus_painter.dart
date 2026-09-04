import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_graph/sd_graph.dart';

import 'pole_zero_painter.dart' show complexToCanvas;

/// Chooses a `unitsPerPixel` scale so the unit circle and every pole/
/// zero across every sample in [samples] fit within [size] with a
/// margin — the same reasoning `pole_zero_painter.dart`'s own `scaleFor`
/// already documents, generalized from one `PoleZeroResult` to a whole
/// swept sequence of them.
double rootLocusScaleFor(List<RootLocusSample> samples, Size size) {
  var maxAbs = 1.0;
  for (final s in samples) {
    for (final p in s.poles) {
      maxAbs = math.max(maxAbs, p.abs());
    }
    for (final z in s.zeros) {
      maxAbs = math.max(maxAbs, z.abs());
    }
  }
  final available = math.min(size.width, size.height) / 2 * 0.8;
  return maxAbs / available;
}

/// A root-locus plot (§5.11's "Analysis Plot — root locus"): the unit
/// circle and axes (the same stability-reference convention
/// `PoleZeroPlotPainter` already uses), then every pole (red) and zero
/// (blue) across every swept sample in [samples], plotted as a scatter
/// of points rather than connected per-root trajectories.
///
/// Deliberate scope cut: a textbook root-locus plot conventionally
/// connects each *individual* pole's own migration into a continuous
/// curve as the swept parameter varies — doing that correctly needs a
/// pole-tracking/matching step (nearest-neighbor assignment between
/// consecutive samples), since `findPolynomialRoots`' Durand-Kerner
/// iteration returns roots in no particular, trajectory-stable order
/// from one sample to the next. A scatter plot shows the *same*
/// migration information (where poles land as the parameter sweeps)
/// correctly and honestly without that extra, easy-to-get-subtly-wrong
/// matching logic — connected trajectories are a real, disclosed gap,
/// not a silent simplification.
class RootLocusPainter extends CustomPainter {
  const RootLocusPainter({required this.samples, this.markerRadius = 3});

  /// `null` when there's nothing to plot yet (e.g. no source/sink, an
  /// algebraic loop, or a different unresolved coefficient) — still
  /// draws the axes and unit circle so the plot area isn't just blank.
  final List<RootLocusSample>? samples;
  final double markerRadius;

  static const _axisColor = Color(0xFFBDBDBD);
  static const _circleColor = Color(0xFF9E9E9E);
  static const _poleColor = Color(0x80C62828);
  static const _zeroColor = Color(0x801565C0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final samples = this.samples;
    final scale = (samples == null || samples.isEmpty)
        ? 1 / (math.min(size.width, size.height) / 2 * 0.8)
        : rootLocusScaleFor(samples, size);

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

    if (samples == null) return;
    final poleDot = Paint()..color = _poleColor;
    final zeroDot = Paint()
      ..color = _zeroColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final sample in samples) {
      for (final pole in sample.poles) {
        canvas.drawCircle(
          complexToCanvas(pole, size, scale),
          markerRadius,
          poleDot,
        );
      }
      for (final zero in sample.zeros) {
        canvas.drawCircle(
          complexToCanvas(zero, size, scale),
          markerRadius,
          zeroDot,
        );
      }
    }
  }

  // Always repaints — same reasoning every other analysis painter in
  // this package already documents.
  @override
  bool shouldRepaint(covariant RootLocusPainter oldDelegate) => true;
}
