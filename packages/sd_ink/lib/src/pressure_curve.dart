import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'stroke_point.dart';

/// Maps a `0..1` pressure sample to a fraction of a stroke's nominal width
/// (§6: "pressure->width via user-editable transfer curve; default min
/// 20%, max 135% of nominal, per Xournal++").
///
/// [gamma] is the "user-editable" knob: `1` (the default) is a straight
/// linear ramp from [minWidthFraction] to [maxWidthFraction]; `>1` biases
/// most of the pressure range toward thin (a light touch stays thin
/// longer, only ramping up near full pressure); `<1` does the opposite. A
/// full curve *editor* (arbitrary control points) isn't built — this one
/// parameter is a real, if simpler, stand-in for "user-editable".
@immutable
class PressureCurve {
  const PressureCurve({
    this.minWidthFraction = 0.20,
    this.maxWidthFraction = 1.35,
    this.gamma = 1.0,
  }) : assert(minWidthFraction >= 0),
       assert(maxWidthFraction >= minWidthFraction),
       assert(gamma > 0);

  final double minWidthFraction;
  final double maxWidthFraction;
  final double gamma;

  /// The stroke width at [pressure] (clamped to `0..1`), as a fraction of
  /// [nominalWidth].
  double widthFor(double pressure, double nominalWidth) {
    final p = pressure.clamp(0.0, 1.0);
    final shaped = gamma == 1.0 ? p : math.pow(p, gamma).toDouble();
    final fraction =
        minWidthFraction + (maxWidthFraction - minWidthFraction) * shaped;
    return fraction * nominalWidth;
  }
}

/// Fills in a missing (`null`) [StrokePoint.pressure] for every point in
/// [points] using inter-point speed as a proxy (§6: "pressure inference
/// fallback (speed->atan sigmoid) for pressureless input") — the common
/// case being a mouse or a touch digitizer that reports no pressure at
/// all. Points that already carry a real pressure sample are left
/// unchanged, so a device that reports pressure for some samples and not
/// others (shouldn't normally happen, but isn't trusted per §7's "never
/// trust the input system") only has the gaps filled.
///
/// Convention: slower movement infers *higher* pressure (a deliberate,
/// pressed stroke) and faster movement infers lower pressure (a light,
/// quick one) — the same relationship a real pressure-sensitive pen
/// typically produces for a natural drawing gesture, and the direction
/// every mainstream pressure-inference fallback (Krita, Photoshop's brush
/// dynamics) uses. [referenceSpeed] (document units/second) is the speed
/// at which inferred pressure crosses the curve's midpoint; tune it to
/// the document's scale.
List<StrokePoint> inferPressureFromSpeed(
  List<StrokePoint> points, {
  double referenceSpeed = 800,
}) {
  if (points.length < 2) {
    return [for (final p in points) p.copyWith(pressure: p.pressure ?? 1.0)];
  }

  double speedAt(int i) {
    final a = points[math.max(0, i - 1)];
    final b = points[math.min(points.length - 1, i + 1)];
    final dt = (b.timestamp - a.timestamp).inMicroseconds / 1e6;
    if (dt <= 0) return 0;
    final dx = b.x - a.x, dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy) / dt;
  }

  return [
    for (var i = 0; i < points.length; i++)
      points[i].pressure != null
          ? points[i]
          : points[i].copyWith(
              pressure:
                  1 - (2 / math.pi) * math.atan(speedAt(i) / referenceSpeed),
            ),
  ];
}
