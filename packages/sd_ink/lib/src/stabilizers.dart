import 'dart:math' as math;

import 'stroke_point.dart';

/// A simple centered moving-average smoother (§6's stabilizer menu — the
/// simplest entry on it; Kalman/Krita "pulled string" are not built, see
/// the package doc comment). The first and last points are left exactly
/// as sampled, so a smoothed stroke still starts/ends where the user
/// actually put the pen down/up rather than "shrinking" its endpoints.
List<StrokePoint> movingAverageSmooth(
  List<StrokePoint> points, {
  int windowSize = 3,
}) {
  if (windowSize < 2 || points.length < 3) return List.of(points);
  final half = windowSize ~/ 2;
  return [
    for (var i = 0; i < points.length; i++)
      if (i == 0 || i == points.length - 1)
        points[i]
      else
        _averageAround(points, i, half),
  ];
}

StrokePoint _averageAround(List<StrokePoint> points, int i, int half) {
  final lo = math.max(0, i - half);
  final hi = math.min(points.length - 1, i + half);
  double sx = 0, sy = 0, sp = 0;
  var n = 0;
  for (var j = lo; j <= hi; j++) {
    sx += points[j].x;
    sy += points[j].y;
    sp += points[j].pressure ?? 1.0;
    n++;
  }
  return StrokePoint(
    x: sx / n,
    y: sy / n,
    pressure: sp / n,
    tilt: points[i].tilt,
    timestamp: points[i].timestamp,
  );
}

/// Ramer-Douglas-Peucker point-reduction (§6): keeps only the points
/// needed to stay within [epsilon] (document units) of the original
/// polyline's shape, discarding near-collinear ones — fewer points for
/// [fitCatmullRom]/the outline builder to process, without a visible
/// shape change at reasonable epsilons. Endpoints are always kept.
List<StrokePoint> simplifyRdp(
  List<StrokePoint> points, {
  double epsilon = 1.0,
}) {
  if (points.length < 3) return List.of(points);
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _rdpRange(points, 0, points.length - 1, epsilon, keep);
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

void _rdpRange(
  List<StrokePoint> points,
  int start,
  int end,
  double epsilon,
  List<bool> keep,
) {
  if (end <= start + 1) return;
  var maxDist = 0.0;
  var maxIndex = -1;
  for (var i = start + 1; i < end; i++) {
    final d = _perpendicularDistance(points[i], points[start], points[end]);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }
  if (maxIndex != -1 && maxDist > epsilon) {
    keep[maxIndex] = true;
    _rdpRange(points, start, maxIndex, epsilon, keep);
    _rdpRange(points, maxIndex, end, epsilon, keep);
  }
}

double _perpendicularDistance(StrokePoint p, StrokePoint a, StrokePoint b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final lenSq = dx * dx + dy * dy;
  if (lenSq < 1e-12) {
    return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
  }
  final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
  final projX = a.x + t * dx, projY = a.y + t * dy;
  final ddx = p.x - projX, ddy = p.y - projY;
  return math.sqrt(ddx * ddx + ddy * ddy);
}

/// Resamples [points] along the smooth Catmull-Rom spline through them
/// (§6: "Catmull-Rom/cubic-Bezier fitting"), producing [samplesPerSpan]
/// evenly-`t`-spaced points between every consecutive pair — `x`, `y`,
/// *and* `pressure` are all spline-interpolated together (not just
/// position, so a pressure ramp reads as smoothly as the curve it's
/// drawn along), while `timestamp` is linearly interpolated (a cubic
/// blend of four timestamps isn't guaranteed monotonic, which would
/// break anything downstream that assumes samples are time-ordered).
/// Fewer than 3 input points can't define a spline span, so returns
/// [points] unchanged.
List<StrokePoint> fitCatmullRom(
  List<StrokePoint> points, {
  int samplesPerSpan = 8,
}) {
  if (points.length < 3) return List.of(points);
  final result = <StrokePoint>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[math.max(0, i - 1)];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[math.min(points.length - 1, i + 2)];
    for (var s = 1; s <= samplesPerSpan; s++) {
      result.add(_catmullRomPoint(p0, p1, p2, p3, s / samplesPerSpan));
    }
  }
  return result;
}

double _catmullRom(double v0, double v1, double v2, double v3, double t) {
  final t2 = t * t, t3 = t2 * t;
  return 0.5 *
      ((2 * v1) +
          (-v0 + v2) * t +
          (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2 +
          (-v0 + 3 * v1 - 3 * v2 + v3) * t3);
}

StrokePoint _catmullRomPoint(
  StrokePoint p0,
  StrokePoint p1,
  StrokePoint p2,
  StrokePoint p3,
  double t,
) {
  final pressure = _catmullRom(
    p0.pressure ?? 1.0,
    p1.pressure ?? 1.0,
    p2.pressure ?? 1.0,
    p3.pressure ?? 1.0,
    t,
  ).clamp(0.0, 1.0);
  return StrokePoint(
    x: _catmullRom(p0.x, p1.x, p2.x, p3.x, t),
    y: _catmullRom(p0.y, p1.y, p2.y, p3.y, t),
    pressure: pressure,
    tilt: p1.tilt,
    timestamp: p1.timestamp + (p2.timestamp - p1.timestamp) * t,
  );
}
