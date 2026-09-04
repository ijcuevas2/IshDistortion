import 'package:meta/meta.dart';

/// One raw sample of a pen/mouse/touch stroke (§6): position, an optional
/// pressure (`null`, not `0`, means "this device doesn't report pressure at
/// all" — [inferPressureFromSpeed] fills that in; an actual `0` means "the
/// device reported zero pressure", e.g. a hover sample that shouldn't ink
/// at all per §7's "only ink on positive pressure"), an optional tilt angle
/// in radians (device-dependent meaning; unused by the outline geometry
/// itself, carried through for a future tilt-shaped nib), and a timestamp
/// used by speed-based pressure inference and by a future velocity-based
/// width modulation (§6) — not by anything built so far.
@immutable
class StrokePoint {
  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure,
    this.tilt,
    this.timestamp = Duration.zero,
  });

  final double x;
  final double y;
  final double? pressure;
  final double? tilt;
  final Duration timestamp;

  StrokePoint copyWith({double? pressure}) => StrokePoint(
    x: x,
    y: y,
    pressure: pressure ?? this.pressure,
    tilt: tilt,
    timestamp: timestamp,
  );

  @override
  String toString() =>
      'StrokePoint($x, $y, pressure: $pressure, t: ${timestamp.inMicroseconds}us)';
}
