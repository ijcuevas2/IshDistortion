# sd_pen_ios (Phase 6, not yet implemented)

Swift native pen plugin for iOS/iPadOS. Reads `UITouch.force` /
`maximumPossibleForce`, `altitudeAngle`, `azimuthAngle(in:)`, plus
`coalescedTouches`/`predictedTouches` for latency hiding and
estimated-property backfill. Wires `UIPencilInteraction` (double-tap on
Pencil, squeeze on Pencil Pro) and hover. Evaluate `flutter_apple_pencil`
and `pencil_kit` first (the latter may conflict with our custom
CustomPainter canvas — confirm before adopting).

Scaffold with `flutter create --template=plugin --platforms=ios` when this
phase starts.
