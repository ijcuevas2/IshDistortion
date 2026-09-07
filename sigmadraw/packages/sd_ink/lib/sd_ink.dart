/// Stroke model, pressure-to-width curves, stabilizers, and outline
/// generation for pen ink (§6).
///
/// Pure Dart (no Flutter dependency), so the whole pipeline — pressure
/// inference, smoothing, simplification, curve fitting, outline geometry —
/// is unit-testable with plain `dart test` and safe to run in an isolate.
/// The live pointer-sampling/overlay-drawing half of §6 ("in-progress
/// stroke drawn into a lightweight overlay ... committed to the scene on
/// pen-up") is `sd_render`'s job (it needs `Listener`/`CustomPainter`),
/// using [InkStroke.build] for that final commit step.
///
/// Built: pressure->width transfer curve with a `gamma` shaping parameter
/// (a real, if simpler, stand-in for "user-editable"), speed-based
/// pressure inference for pressureless input, a moving-average smoother,
/// Ramer-Douglas-Peucker simplification, Catmull-Rom curve fitting, and
/// filled-outline (offset-polygon) generation. Not built: the Kalman/
/// Krita "pulled string" stabilizers, Schneider curve fitting, velocity-
/// based width modulation, and the eraser tools beyond whole-stroke
/// deletion (an ordinary `RemoveChildCommand` — no ink-specific logic
/// needed for that one).
library;

export 'src/ink_stroke.dart';
export 'src/pressure_curve.dart';
export 'src/stabilizers.dart';
export 'src/stroke_outline.dart';
export 'src/stroke_point.dart';
