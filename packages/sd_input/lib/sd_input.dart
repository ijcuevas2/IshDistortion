/// Pointer/pen input pipeline: device classification and palm rejection
/// (§7).
///
/// Built: [DeviceRole]/[classifyDevice] (pen/eraser/touch/mouse, from
/// Flutter's own [PointerEvent.kind] — nothing platform-specific is
/// needed for that part), [PalmRejectionFilter] ("while a stylus is in
/// proximity/down, route touch to pan/zoom only"), and [hasInkablePressure]
/// (Xournal++'s "never trust the input system; only ink on positive
/// pressure"). `sd_render`'s `SigmaCanvas` uses all three for its ink
/// tool.
///
/// Not built: everything platform-specific §7 actually asks for — the 5
/// native plugins (`PenSample` EventChannel streams, capability-query
/// MethodChannels, and each platform's own pressure/tilt/twist/eraser
/// API) — this sandbox can only build/run the Linux desktop target
/// anyway, and even Linux's own pen support (libinput/XInput2/Wayland
/// tablet_v2) is real native-code work on its own. Coalesced/predicted
/// point history and a "Pen status" capability-surfacing UI aren't built
/// either.
library;

export 'src/device_role.dart';
export 'src/palm_rejection.dart';
