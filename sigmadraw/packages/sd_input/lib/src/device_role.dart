import 'package:flutter/gestures.dart';

/// What kind of physical input a pointer event came from (§7: "classify
/// each pointer (pen/eraser-tip/touch/mouse)"). A thin, deliberately
/// exhaustive wrapper over [PointerDeviceKind] — not a replacement for it —
/// so call sites reason in the vocabulary §7 actually uses instead of
/// Flutter's more generic device-kind enum.
enum DeviceRole {
  /// The writing tip of a stylus.
  pen,

  /// The eraser end of a stylus ([PointerDeviceKind.invertedStylus]) —
  /// Flutter's own name for this is easy to misread as "this pointer is
  /// upside-down", but it specifically means "the stylus's eraser end is
  /// what's touching", which is exactly §7's "eraser-tip".
  penEraser,
  touch,
  mouse,

  /// [PointerDeviceKind.trackpad] and anything the platform didn't
  /// classify — never trusted as ink-worthy, per §7's "never trust the
  /// input system".
  unknown,
}

/// Classifies [event] by [DeviceRole] (§7).
DeviceRole classifyDevice(PointerEvent event) {
  switch (event.kind) {
    case PointerDeviceKind.stylus:
      return DeviceRole.pen;
    case PointerDeviceKind.invertedStylus:
      return DeviceRole.penEraser;
    case PointerDeviceKind.touch:
      return DeviceRole.touch;
    case PointerDeviceKind.mouse:
      return DeviceRole.mouse;
    case PointerDeviceKind.trackpad:
    case PointerDeviceKind.unknown:
      return DeviceRole.unknown;
  }
}
