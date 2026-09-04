import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import 'spatial_index.dart';

/// Default padding (document units) added around a stroke's centerline for
/// hit-testing, so thin wires stay clickable at any zoom level rather than
/// needing a pixel-perfect click on an infinitesimally thin line.
const double kDefaultHitTolerance = 3.0;

/// Precise point hit-testing: bbox prefilter via [SpatialIndex.query], then
/// `Path.contains` for filled shapes / stroke-outline proximity for
/// stroked ones (§8). Returns the topmost (last-painted) element under
/// [documentPoint], or `null`.
SdElement? hitTestPoint(
  SpatialIndex index,
  Offset documentPoint, {
  double tolerance = kDefaultHitTolerance,
}) {
  final candidates = index.query(
    Rect.fromCircle(center: documentPoint, radius: tolerance),
  );
  for (final entry in candidates.reversed) {
    final local = _toLocal(entry.worldTransform, documentPoint);
    if (local == null) continue;

    final fillPath = entry.node.fillPath;
    if (fillPath != null && fillPath.contains(local)) return entry.element;

    final strokePath = entry.node.strokePath;
    if (strokePath != null) {
      final strokeWidth = entry.node.strokePaint?.strokeWidth ?? 1.0;
      if (_isNearPath(
        strokePath,
        local,
        math.max(strokeWidth / 2, tolerance),
      )) {
        return entry.element;
      }
    }

    if (entry.node.textPainter != null &&
        entry.worldBounds.inflate(tolerance).contains(documentPoint)) {
      return entry.element;
    }
  }
  return null;
}

/// Every element whose bounding box intersects [area] — bbox-only (a shape
/// is included if any part of its box is in the area), matching common
/// rubber-band/marquee-select UX. Used for marquee selection.
List<SdElement> hitTestRect(SpatialIndex index, Rect area) =>
    index.query(area).map((e) => e.element).toList();

Offset? _toLocal(Matrix4 worldTransform, Offset worldPoint) {
  final inverse = Matrix4.tryInvert(worldTransform);
  if (inverse == null) return null;
  final local = inverse.transform3(Vector3(worldPoint.dx, worldPoint.dy, 0));
  return Offset(local.x, local.y);
}

/// Whether any point on [path] is within [radius] of [point], sampled
/// along each contour at a resolution tied to [radius]. Only runs per
/// candidate on an actual click/tap (never per frame), so O(samples) here
/// is cheap in practice.
bool _isNearPath(Path path, Offset point, double radius) {
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length == 0) {
      final tangent = metric.getTangentForOffset(0);
      if (tangent != null && (tangent.position - point).distance <= radius) {
        return true;
      }
      continue;
    }
    final steps = (length / math.max(radius * 0.5, 0.5)).ceil().clamp(8, 2000);
    for (var i = 0; i <= steps; i++) {
      final tangent = metric.getTangentForOffset(length * i / steps);
      if (tangent != null && (tangent.position - point).distance <= radius) {
        return true;
      }
    }
  }
  return false;
}
