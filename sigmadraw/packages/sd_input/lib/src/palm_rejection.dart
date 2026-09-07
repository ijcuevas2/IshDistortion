import 'package:flutter/gestures.dart';

import 'device_role.dart';

/// Tracks whether a stylus is currently in proximity or down, across every
/// pointer on the surface, to implement §7's palm-rejection rule: "While a
/// stylus is in proximity/down, route touch to pan/zoom only." A resting
/// palm registers as an ordinary touch pointer while the hand's stylus is
/// actively writing nearby — this is what tells a caller "that particular
/// touch is the palm, not a gesture", without needing to guess from
/// geometry (contact size/shape) the way some platforms' own heuristics do.
///
/// Feed *every* pointer event from the surface through [onPointerEvent], in
/// order, regardless of which device or gesture it belongs to — this is
/// inherently cross-pointer state (a stylus's own down/up events update it;
/// a touch event only reads it via [shouldInk]).
class PalmRejectionFilter {
  final Set<int> _activeStylusDevices = {};
  bool _stylusHovering = false;

  /// Whether a pen or pen-eraser is currently down or hovering in
  /// proximity anywhere on the surface.
  bool get isStylusActive => _activeStylusDevices.isNotEmpty || _stylusHovering;

  /// Updates the tracked state from one raw pointer event. Safe to call
  /// for every event kind, including ones this filter doesn't otherwise
  /// care about (touch, mouse) — those just don't change [isStylusActive].
  void onPointerEvent(PointerEvent event) {
    final role = classifyDevice(event);
    final isPenLike = role == DeviceRole.pen || role == DeviceRole.penEraser;
    if (!isPenLike) return;

    // Not a class-pattern switch: Flutter's PointerEvent hierarchy isn't
    // `sealed`, so the analyzer can't verify exhaustiveness over it — an
    // if-chain says the same thing without a misleading implied
    // exhaustiveness guarantee.
    if (event is PointerDownEvent) {
      _activeStylusDevices.add(event.device);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activeStylusDevices.remove(event.device);
    } else if (event is PointerHoverEvent) {
      _stylusHovering = true;
    } else if (event is PointerRemovedEvent) {
      _stylusHovering = false;
      _activeStylusDevices.remove(event.device);
    }
  }

  /// Whether a pointer of [kind] should be allowed to draw ink right now.
  /// Per §7, only a resting-palm *touch* is ever rejected — a pen, its
  /// eraser, and a mouse are always allowed (a mouse has no palm to reject
  /// in the first place, and disallowing it whenever a tablet happens to
  /// also be attached would be a strictly worse experience than the
  /// problem this filter exists to solve).
  bool shouldInk(PointerDeviceKind kind) =>
      !(kind == PointerDeviceKind.touch && isStylusActive);

  /// Resets all tracked state — e.g. if the app determines the platform's
  /// events can no longer be trusted (§7: "never trust the input system")
  /// and wants to fail safe rather than get stuck with a stylus considered
  /// permanently active.
  void reset() {
    _activeStylusDevices.clear();
    _stylusHovering = false;
  }
}

/// §7's Xournal++-derived defensive rule: "only ink on positive pressure".
/// [resolvedPressure] is the *already device-classified* pressure — `null`
/// meaning "this device doesn't report pressure at all" (a mouse; always
/// inkable, since there's nothing to distrust), not a literal `0` reading
/// from a genuine pressure sensor (which might be a hovering stylus some
/// platforms erroneously deliver as touching) — see `sd_ink`'s
/// `StrokePoint.pressure` doc comment for the same `null`-vs-`0` contract
/// this mirrors.
bool hasInkablePressure(double? resolvedPressure) =>
    resolvedPressure == null || resolvedPressure > 0;
