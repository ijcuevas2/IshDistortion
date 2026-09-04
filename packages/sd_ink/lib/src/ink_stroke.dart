import 'package:sd_document/sd_document.dart';

import 'pressure_curve.dart';
import 'stabilizers.dart';
import 'stroke_outline.dart';
import 'stroke_point.dart';

/// Ties together the whole §6 pipeline — pressure inference, smoothing,
/// simplification, curve fitting, and outline generation — into one call
/// that turns a raw pointer-sample list into a real `<path>` element ready
/// to place in a document (§9: "in-progress stroke ... committed to the
/// scene on pen-up" — this is that commit step; the *in-progress* overlay
/// itself is `sd_render`'s job, drawing raw samples directly for zero
/// pipeline latency while the pen is still down).
class InkStroke {
  const InkStroke({
    this.pressureCurve = const PressureCurve(),
    this.nominalWidth = 6,
    this.smoothingWindow = 3,
    this.simplifyEpsilon = 0.75,
    this.samplesPerSpan = 8,
    this.referenceSpeed = 800,
  });

  final PressureCurve pressureCurve;

  /// The stroke's width (document units) at pressure `1.0` — every other
  /// pressure scales it via [pressureCurve].
  final double nominalWidth;

  final int smoothingWindow;
  final double simplifyEpsilon;
  final int samplesPerSpan;
  final double referenceSpeed;

  /// Runs [rawPoints] through the full pipeline and builds the resulting
  /// filled-outline `<path>` (§6), with `sd:stroke`/`sd:strokePoints`/
  /// `sd:pressure` set from the *simplified* centerline (the smoothed,
  /// RDP-reduced control polygon — few enough points to be a sane "drag
  /// this point" editing target later; the further-subdivided Catmull-Rom
  /// samples used for the outline geometry itself are a rendering-time
  /// detail, not persisted). Returns `null` for an empty [rawPoints] (a
  /// pointer-down immediately followed by cancel, with no samples in
  /// between) — nothing to commit.
  SdElement? build(
    List<StrokePoint> rawPoints, {
    required String strokeId,
    String color = '#1a1a1a',
  }) {
    if (rawPoints.isEmpty) return null;

    final withPressure = inferPressureFromSpeed(
      rawPoints,
      referenceSpeed: referenceSpeed,
    );
    final smoothed = movingAverageSmooth(
      withPressure,
      windowSize: smoothingWindow,
    );
    final simplified = simplifyRdp(smoothed, epsilon: simplifyEpsilon);
    final fitted = fitCatmullRom(simplified, samplesPerSpan: samplesPerSpan);
    final path = buildStrokeOutlinePath(
      fitted,
      pressureCurve: pressureCurve,
      nominalWidth: nominalWidth,
    );
    if (path.isEmpty) return null;

    return SdElement(
        const SdQName('path'),
        attributes: {
          const SdQName('d'): path,
          const SdQName('fill'): color,
          const SdQName('fill-rule'): 'nonzero',
        },
      )
      ..strokeId = strokeId
      ..strokeCenterline = [for (final p in simplified) (x: p.x, y: p.y)]
      ..strokePressures = [for (final p in simplified) p.pressure ?? 1.0];
  }
}
