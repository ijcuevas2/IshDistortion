# sd_pen_macos (Phase 6, not yet implemented)

Swift native pen plugin for macOS. Flutter has no native tablet support on
macOS, so this taps `NSEvent` directly: a local monitor / overridden
responder methods for `NSEventType.tabletPoint`/proximity, and mouse events
with `subtype == .tabletPoint`. Reads pressure (0-1), tilt (NSPoint, -1..+1),
rotation, tangential pressure, and `buttonMask`
(NSPenTipMask/NSPenLowerSideMask/NSPenUpperSideMask). Streams `PenSample`
via EventChannel. Reference: the proof-of-concept linked from
flutter/flutter#146387.

Scaffold with `flutter create --template=plugin --platforms=macos` when this
phase starts.
