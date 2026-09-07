import 'dart:math' as math;

import 'pressure_curve.dart';
import 'stroke_point.dart';

/// Converts a variable-width ink centerline into a **filled outline**
/// `<path>` — never a stroked centerline (§6: "convert the variable-width
/// centerline into a FILLED OUTLINE path (offset polygon each side)"), so
/// the stroke renders identically in any plain SVG viewer, with no
/// dependency on that viewer supporting variable-width strokes (nothing
/// in the SVG spec does).
///
/// At each point, offsets it perpendicular to the local tangent by half
/// the width [pressureCurve] assigns that point's pressure, producing two
/// "rails" (`left`/`right` of the direction of travel); the returned path
/// walks forward along one rail and back along the other, closing into one
/// polygon. End caps are flat ("butt caps" — the two rails simply meet at
/// each end) rather than round arcs, a deliberate scope cut (documented
/// here, not silently different from what §6 shows): with [centerline]
/// already densely resampled (see `fitCatmullRom`), this is visually
/// close to a round cap and meaningfully simpler to get right.
///
/// A single-point [centerline] (a tap, not a drag) is special-cased into
/// an actual filled circle of that point's width — a one-point "polygon"
/// by the above algorithm would be degenerate (no direction to derive a
/// tangent from).
///
/// Returns `''` for an empty [centerline] (nothing to draw).
String buildStrokeOutlinePath(
  List<StrokePoint> centerline, {
  required PressureCurve pressureCurve,
  required double nominalWidth,
}) {
  if (centerline.isEmpty) return '';
  if (centerline.length == 1) {
    return _dotPath(centerline.single, pressureCurve, nominalWidth);
  }

  final n = centerline.length;
  final left = List<(double, double)>.filled(n, (0, 0));
  final right = List<(double, double)>.filled(n, (0, 0));
  for (var i = 0; i < n; i++) {
    final p = centerline[i];
    final (tx, ty) = _tangentAt(centerline, i);
    final nx = -ty, ny = tx; // rotate tangent +90°
    final halfWidth =
        pressureCurve.widthFor(p.pressure ?? 1.0, nominalWidth) / 2;
    left[i] = (p.x + nx * halfWidth, p.y + ny * halfWidth);
    right[i] = (p.x - nx * halfWidth, p.y - ny * halfWidth);
  }

  final buffer = StringBuffer('M ${_fmt(left[0].$1)},${_fmt(left[0].$2)}');
  for (var i = 1; i < n; i++) {
    buffer.write(' L ${_fmt(left[i].$1)},${_fmt(left[i].$2)}');
  }
  for (var i = n - 1; i >= 0; i--) {
    buffer.write(' L ${_fmt(right[i].$1)},${_fmt(right[i].$2)}');
  }
  buffer.write(' Z');
  return buffer.toString();
}

/// The unit tangent direction at `points[i]`, from a central difference
/// (or a one-sided difference at either end). Returns `(1, 0)` for a
/// degenerate (coincident-neighbor) point rather than dividing by zero —
/// arbitrary, but only ever affects a stroke that doubles back on itself
/// exactly, which has no well-defined "sideways" anyway.
(double, double) _tangentAt(List<StrokePoint> points, int i) {
  final a = points[math.max(0, i - 1)];
  final b = points[math.min(points.length - 1, i + 1)];
  final dx = b.x - a.x, dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  return len < 1e-9 ? (1.0, 0.0) : (dx / len, dy / len);
}

String _dotPath(
  StrokePoint p,
  PressureCurve pressureCurve,
  double nominalWidth,
) {
  final r = pressureCurve.widthFor(p.pressure ?? 1.0, nominalWidth) / 2;
  if (r <= 0) return '';
  // Two semicircle arcs all the way around — the standard trick for a
  // full circle in path data (a single 360° arc command is degenerate).
  return 'M ${_fmt(p.x - r)},${_fmt(p.y)} '
      'A ${_fmt(r)},${_fmt(r)} 0 1,0 ${_fmt(p.x + r)},${_fmt(p.y)} '
      'A ${_fmt(r)},${_fmt(r)} 0 1,0 ${_fmt(p.x - r)},${_fmt(p.y)} Z';
}

String _fmt(double v) {
  final rounded = (v * 1e4).round() / 1e4;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}
