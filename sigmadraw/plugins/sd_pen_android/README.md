# sd_pen_android (Phase 6, not yet implemented)

Kotlin native pen plugin for Android. Reads full `MotionEvent` data:
pressure, `getAxisValue(AXIS_TILT)`, `AXIS_ORIENTATION`, `AXIS_DISTANCE`,
S Pen `BUTTON_STYLUS_PRIMARY`/`SECONDARY`, and batched `getHistorical*`
points for latency smoothing. Integrates `androidx.input` `MotionPredictor`;
consider a low-latency `GLFrontBufferRenderer` path for the in-progress ink
overlay.

Scaffold with `flutter create --template=plugin --platforms=android` when
this phase starts.
