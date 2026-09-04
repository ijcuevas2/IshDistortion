import 'package:flutter/widgets.dart';

/// The 8 SPKnot-style control points around a selection's bounding box
/// (§9). Rotate/flip handles are not implemented yet (Phase 2 scope: move
/// + uniform corner-scale only — see `sigma_canvas.dart`).
enum HandleKind {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

Map<HandleKind, Offset> handlePositions(Rect bounds) => {
  HandleKind.topLeft: bounds.topLeft,
  HandleKind.topCenter: bounds.topCenter,
  HandleKind.topRight: bounds.topRight,
  HandleKind.centerLeft: bounds.centerLeft,
  HandleKind.centerRight: bounds.centerRight,
  HandleKind.bottomLeft: bounds.bottomLeft,
  HandleKind.bottomCenter: bounds.bottomCenter,
  HandleKind.bottomRight: bounds.bottomRight,
};

/// The handle at [screenPoint] (within [hitRadius] of it), if any, given
/// the selection's bounding box *in screen space*. Picks the *closest*
/// qualifying handle, not just the first found in iteration order — for a
/// selection smaller than ~2×[hitRadius], adjacent handles' hit regions
/// overlap (e.g. a 10x10 selection's `centerRight` and `bottomRight` are
/// only 5px apart), so "first in iteration order" would pick the wrong one
/// depending on `handlePositions`' insertion order.
HandleKind? hitTestHandle(
  Rect screenBounds,
  Offset screenPoint, {
  double hitRadius = 8,
}) {
  HandleKind? closest;
  var closestDistance = double.infinity;
  for (final entry in handlePositions(screenBounds).entries) {
    final distance = (entry.value - screenPoint).distance;
    if (distance <= hitRadius && distance < closestDistance) {
      closest = entry.key;
      closestDistance = distance;
    }
  }
  return closest;
}

/// The bounding-box corner a [HandleKind] scales *from* — i.e. the fixed
/// anchor point on the opposite side, per the usual drag-a-corner-to-
/// resize convention.
Offset anchorFor(HandleKind handle, Rect bounds) => switch (handle) {
  HandleKind.topLeft => bounds.bottomRight,
  HandleKind.topCenter => bounds.bottomCenter,
  HandleKind.topRight => bounds.bottomLeft,
  HandleKind.centerLeft => bounds.centerRight,
  HandleKind.centerRight => bounds.centerLeft,
  HandleKind.bottomLeft => bounds.topRight,
  HandleKind.bottomCenter => bounds.topCenter,
  HandleKind.bottomRight => bounds.topLeft,
};

/// Whether dragging [handle] changes width, height, or both.
(bool affectsWidth, bool affectsHeight) handleAxes(HandleKind handle) =>
    switch (handle) {
      HandleKind.topCenter || HandleKind.bottomCenter => (false, true),
      HandleKind.centerLeft || HandleKind.centerRight => (true, false),
      _ => (true, true),
    };
