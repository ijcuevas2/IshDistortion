# Xournal++ Architecture Notes → Flutter/Dart Ink Pipeline

Source: `~/xournalpp` (C++/GTK4). Purpose: extract the *concepts and defensive
rules* behind Xournal++'s input handling, ink model, eraser, LaTeX embedding
and repaint pipeline, and propose idiomatic Dart/Flutter equivalents for a
`packages/sd_input` (pointer/pen pipeline) and `packages/sd_ink`
(stroke/eraser model), plus proposals for LaTeX embedding and page repaint.
This is a translation of *architecture*, not a line-by-line port — C++
snippets below are quoted only where the exact logic/constants matter (e.g.
the pressure-inference formula); everywhere else the Dart types are original
designs shaped to fit Flutter idioms (`Listener`/`PointerEvent`,
immutable value types, `CustomPainter`/`RepaintBoundary`).

---

## 1. Input device pipeline

**Files:** `src/core/gui/inputdevices/{InputContext,AbstractInputHandler,PenInputHandler,StylusInputHandler,MouseInputHandler,TouchInputHandler,TouchDrawingInputHandler,HandRecognition,InputEvents,InputUtils,DeviceId,PositionInputData}.{h,cpp}`

### 1a. C++ architecture

**Single entry point, then classify-and-dispatch.** `InputContext` connects
one GTK `"event"` signal handler to the drawing widget (`InputContext::connect`,
`InputContext.cpp:86`). Every raw `GdkEvent` flows through `InputContext::handle`
(`InputContext.cpp:138`):

1. `InputEvents::translateEvent` normalizes the GTK event into a
   backend-agnostic `InputEvent` struct (type, device class, absolute +
   layout-relative coordinates, button, pressure, timestamp, a `DeviceId`).
2. The *device class* (`INPUT_DEVICE_MOUSE|PEN|ERASER|TOUCHSCREEN|IGNORE`) is
   **not** trusted from any single GDK enum. `InputEvents::translateDeviceType`
   looks up a **per-device-name override table** persisted in `Settings`
   (`getDeviceClassForDevice(name, GdkInputSource)`). The first time a given
   physical device is seen, `InputContext` auto-classifies it from
   `GdkInputSource` and remembers the choice (`knownDevices` set); the user can
   override this later in the settings dialog. This exists because no GTK
   backend reliably reports "this is a pen" vs "this is a touchscreen
   pretending to be a pen" the same way across X11/Wayland/Windows/macOS.
3. `HandRecognition::event()` is notified of every event's device class
   *before* routing (see palm rejection below).
4. Dispatch by device class to one singleton handler per class:
   `StylusInputHandler` (pen **and** eraser), `MouseInputHandler`,
   `TouchInputHandler` (pan/zoom gestures), and optionally
   `TouchDrawingInputHandler` first (if "touch drawing" is enabled in
   settings) falling through to `TouchInputHandler` if it declines the event.

**Shared state machine.** `StylusInputHandler`, `MouseInputHandler` and
`TouchDrawingInputHandler` all extend `PenInputHandler` (`PenInputHandler.h`),
which implements one state machine shared by every "thing that can draw":
`actionStart` → `actionMotion` (N times) → `actionEnd`, plus
`actionEnterWindow`/`actionLeaveWindow` and `actionPerform` (double/triple
click). This is where pressure resolution happens (§3) and where the events
get translated into page-relative `PositionInputData` and forwarded to
`XojPageView::onButtonPressEvent` / `onMotionNotifyEvent` / `onButtonReleaseEvent`.
`TouchInputHandler` (pure pan/zoom) does **not** extend `PenInputHandler` — it
never draws, it only pans/zooms, so it has its own much smaller state machine
(§ below).

**Device-class-specific quirks handled per handler:**
- `MouseInputHandler` tracks exactly one `pressedButton` and defends against
  double `BUTTON_PRESS` (logs a warning rather than corrupting state).
  Side-button numbering (mouse buttons 4/5) is **not** trusted to be constant
  across platforms: Linux backends report 8/9, Windows/macOS report 4/5 —
  handled with `#if defined(_WIN32) || defined(__APPLE__)` branches
  (`MouseInputHandler.cpp:105-126`).
- `StylusInputHandler` additionally tracks `eventsToIgnore` (see rule 5 below)
  and treats `INPUT_DEVICE_ERASER` (the eraser end of the pen, a distinct GDK
  device) as an automatic tool switch (`changeTool`).
- `TouchInputHandler` tracks up to two simultaneous sequences
  (`primarySequence`/`secondarySequence`) for pinch-zoom, plus an
  `invalidActive` set for touch points it has decided **not** to trust (see
  rule 3 below).
- `TouchDrawingInputHandler` lets a *single* touch draw like a pen, but any
  *second* simultaneous touch immediately cancels the in-progress stroke
  (`onSequenceCancelEvent`) and hands control back to `TouchInputHandler` for
  pan/zoom — this is the closest thing to geometric palm rejection in this
  codebase (see §1c below).

### Defensive rules ("never trust the input system")

Concrete rules found in this code, each citable:

1. **Zero/negative pressure is not "no pressure," it's noise — don't draw.**
   `StrokeHandler::onMotionNotifyEvent`: `if (pos.pressure == 0) { /* some
   devices emit a move event with pressure 0 when lifting the stylus tip */
   return true; }` — silently swallowed, not treated as a real sample.
2. **A pressure-sensitive device can still omit pressure on any single event.**
   `PenInputHandler::filterPressure` (`PenInputHandler.cpp:209`): if
   `pos.pressure == Point::NO_PRESSURE` even though the device is in
   `DEVICE_PRESSURE` mode, fall back to `lastPressure` rather than treating it
   as 0 or crashing.
3. **Touch sequence bookkeeping assumes you *will* miss an end/cancel event.**
   `TouchInputHandler::handleImpl`: if a new touch ID shows up while both
   primary+secondary slots are already occupied, *all three* are moved into an
   `invalidActive` set rather than guessing which one is stale; once every
   currently-tracked sequence is confirmed gone, it self-heals
   (`"Missed touch end/cancel event. Resetting touch input handler."`).
4. **A platform-specific null-sequence motion event is explicitly filtered.**
   `TouchInputHandler::handleImpl`: "On x11, a `GDK_MOTION_EVENT` with
   `sequence == nullptr` is emitted before `TOUCH_BEGIN`: Ignore it."
5. **The first N samples after stylus-down can be pure hardware jitter.**
   `StylusInputHandler::eventsToIgnore`, driven by the user setting
   `Settings::getIgnoredStylusEvents()` (`numIgnoredStylusEvents`, default 0):
   a configurable number of initial button-press/motion events are discarded
   before `actionStart` actually fires, as a workaround for tablets whose
   first contact reports are spatially/pressure-wise unreliable.
6. **Enter/Leave events' coordinates are sanity-checked, not trusted.**
   `StylusInputHandler::handleImpl` (`StylusInputHandler.cpp:91-97`): if an
   `ENTER`/`LEAVE` event arrives while a button is known pressed and its
   coordinates jump >100px from the last known position, it's discarded as
   "a bug of the hardware (there are such devices!)" rather than being
   allowed to yank the in-progress stroke somewhere impossible.
7. **Enter/Leave are not assumed to be symmetric or reliable at all.**
   `PenInputHandler` tracks `penInWidget` itself (not trusting GTK's
   enter/leave pairing) with a manual widget-bounds + `WIDGET_SCROLL_BORDER`
   margin check inside `actionMotion`, because of "misbehaving devices where
   Enter events are not published every time."
8. **A lost device grab is a hard signal to end the stroke, not silence.**
   Both `StylusInputHandler` and `MouseInputHandler` treat
   `GRAB_BROKEN_EVENT` as "force `actionEnd()` now" so a stroke can never be
   left stuck "open" forever because the window manager stole the grab.
9. **If the pointer flies off the page mid-drag, the stroke doesn't just die.**
   `PenInputHandler::actionEnd`: if there's no page under the release point,
   fall back to `lastHitEvent`'s page instead of dropping the up-event.
   Symmetrically, `actionMotion` synthesizes a fake end-on-page-A +
   start-on-page-B pair when a drag crosses a page boundary without ever
   getting a page-boundary event from GTK (`PenInputHandler.cpp:335-364`).
10. **Pressure can never resolve to (near-)zero width.** `filterPressure`
    always does `max(settings->getMinimumPressure(), pressure * multiplier)`,
    and `xoj_assert(settings->getMinimumPressure() >= 0.01)` — a bad inference
    or hardware glitch can't ever produce an invisible/zero-width stroke.
11. **A short, small, quick contact is reinterpreted as a tap, not committed
    as a micro-stroke.** `PenInputHandler::isCurrentTapSelection`
    (`PenInputHandler.cpp:236`) checks distance-moved (converted through
    physical dpmm, not raw pixels), duration, and a "not immediately after
    another tap" repetition guard; if all match, `actionEnd` cancels the
    sequence (`onSequenceCancelEvent`) instead of finalizing a stroke.

### Palm rejection specifically

Xournal++ does **not** do contact-size/geometric palm rejection anywhere.
Instead it uses two blunter, reliable strategies:

- **Temporal exclusivity (`HandRecognition`, `HandRecognition.{h,cpp}`).**
  Any pen/eraser event calls `penEvent()`, which immediately disables the
  *entire OS touchscreen device* (`InputContext::blockDevice(TOUCHSCREEN)` +,
  on X11, actually turning the XInput device off via `TouchDisableX11`, or
  running a user-configured shell command pair via `TouchDisableCustom`) and
  arms a `disableTimeout` (setting-controlled, clamped to ≥500ms). A GTK
  timer (`enableTimeout`) re-enables touch only after that many ms have
  elapsed with *no* further pen activity. This is pen-vs-touch mutual
  exclusion in **time**, not space — it assumes "if a pen was just used, any
  simultaneous touch is a resting hand," full stop.
- **Multi-touch-cancels-stroke (`TouchDrawingInputHandler`).** When
  single-finger touch-to-draw is enabled, a *second* concurrent touch point
  is presumed to be a palm/other fingers, not a second intentional drawing
  input: it immediately calls `onSequenceCancelEvent` on the in-progress
  stroke and yields the gesture to `TouchInputHandler` for pan/zoom instead.

### 1b. Dart translation — `packages/sd_input`

**Normalize once, at the boundary.** Convert every `PointerEvent` into one
immutable record in *document* coordinates (never raw screen pixels — see the
zoom-dependence bug called out in §3) as early as possible:

```dart
/// One normalized pointer sample. Dart analogue of Xournal++'s
/// PositionInputData + InputEvent, merged, and pre-converted to document
/// space so nothing downstream depends on zoom or DPI.
@immutable
class PenSample {
  const PenSample({
    required this.docPosition,   // page/document units, NOT screen px
    required this.timestamp,     // PointerEvent.timeStamp (monotonic)
    required this.kind,          // PointerDeviceKind: stylus/invertedStylus/touch/mouse
    required this.deviceId,      // PointerEvent.device
    required this.buttons,       // PointerEvent.buttons bitmask
    this.rawPressure,            // null = device did not report pressure
    this.tilt = 0,               // radians, PointerEvent.tilt (0 = perpendicular)
    this.orientation = 0,        // radians, PointerEvent.orientation (azimuth)
    this.distance = 0,           // hover distance; 0 while in contact
    this.radiusMajor = 0,        // contact ellipse — touch-blob heuristics
    this.radiusMinor = 0,
  });

  final Offset docPosition;
  final Duration timestamp;
  final PointerDeviceKind kind;
  final int deviceId;
  final int buttons;
  final double? rawPressure;
  final double tilt;
  final double orientation;
  final double distance;
  final double radiusMajor, radiusMinor;
}
```

Note Flutter already solves part of what Xournal++ has to work hard for:
`PointerDeviceKind` distinguishes `stylus` from `invertedStylus` (eraser end)
natively, so the "is this GDK device actually an eraser" override table
mostly collapses to a couple of `switch` cases. Keep a *small* per-`deviceId`
override map anyway (mirrors `knownDevices`) for the rare vendor stack that
misreports its kind — don't hardcode a single trust assumption.

```dart
enum InputRole { pen, eraser, touch, mouse, ignored }

abstract interface class DeviceClassifier {
  InputRole classify(PointerEvent e);
}
```

**`InputRouter`** — the Dart analogue of `InputContext::handle` +
`AbstractInputHandler`/`PenInputHandler`'s shared state machine. Wrap the
drawing surface in a `Listener` and forward every callback here; one
`InputRouter` per canvas, one internal per-pointer state record per active
`device` id (mirrors one `PenInputHandler` instance being reused across a
whole gesture):

```dart
class InputRouter {
  InputRouter({
    required this.classifier,
    required this.palmRejection,
    required this.pressureResolver,   // §3
    required this.stabilizerFactory,  // §2
    required this.targetForRole,      // InputRole -> PointerGestureTarget
  });

  final DeviceClassifier classifier;
  final PalmRejectionPolicy palmRejection;
  final PressureResolver pressureResolver;
  final StrokeStabilizer Function() stabilizerFactory;
  final PointerGestureTarget Function(InputRole) targetForRole;

  final Map<int, _PointerStream> _active = {};

  void onPointerDown(PointerDownEvent e) { /* classify, palm-gate, eventsToIgnore, actionStart */ }
  void onPointerMove(PointerMoveEvent e) { /* palm-gate, actionMotion */ }
  void onPointerUp(PointerUpEvent e)     { /* actionEnd, tap-filter check */ }
  void onPointerCancel(PointerCancelEvent e) { /* mirrors GRAB_BROKEN_EVENT: force-end */ }
  void onPointerHover(PointerHoverEvent e)   { /* proximity preview only — never committed as ink */ }
}

/// Per-active-pointer bookkeeping, created on down, destroyed on up/cancel.
/// Mirrors PenInputHandler's per-gesture fields (eventsToIgnore, lastEvent,
/// lastHitEvent, sequenceStartPosition, lastActionStartTimeStamp, ...).
class _PointerStream {
  _PointerStream(this.role, this.first, {required this.ignoreRemaining});
  final InputRole role;
  final PenSample first;          // for the tap-filter distance check
  int ignoreRemaining;            // mirrors StylusInputHandler::eventsToIgnore
  PenSample? last;                // mirrors PenInputHandler::lastEvent
  bool committed = false;         // true once ignoreRemaining is exhausted
  late final StrokeStabilizer stabilizer;
}
```

The boundary to `sd_ink` (and to pan/zoom/eraser/selection tools) is a small
target interface — mirrors `XojPageView`'s `onButtonPressEvent` /
`onMotionNotifyEvent` / `onButtonReleaseEvent` / `onSequenceCancelEvent` /
`onTapEvent`:

```dart
abstract interface class PointerGestureTarget {
  void start(PenSample sample);
  void update(PenSample sample);
  void end(PenSample sample);
  void cancel();                  // tap-filtered, second-touch, or lost-pointer
  void tap(PenSample sample);
  void hover(PenSample sample);   // proximity only, never becomes ink
}
```

**Palm rejection.** Translate both real strategies (temporal exclusion +
multi-touch-cancels), since a Flutter app cannot disable the OS touch
digitizer the way X11 XInput can — the "temporal" strategy becomes pure
software suppression of touch *routing*, not device disabling:

```dart
abstract interface class PalmRejectionPolicy {
  /// Return false to drop the event as a suspected palm/heel-of-hand touch.
  bool accept(PointerEvent e, InputRouterState state);
}

class StylusPriorityPalmRejection implements PalmRejectionPolicy {
  StylusPriorityPalmRejection({this.cooldown = const Duration(milliseconds: 500)});
  final Duration cooldown;        // mirrors HandRecognition::disableTimeout (min 500ms)
  Duration? _lastStylusActivity;

  @override
  bool accept(PointerEvent e, InputRouterState state) {
    if (e.kind case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus) {
      _lastStylusActivity = e.timeStamp;
      return true;
    }
    if (e.kind == PointerDeviceKind.touch) {
      final last = _lastStylusActivity;
      if (last != null && e.timeStamp - last < cooldown) {
        return false; // mirrors HandRecognition: recent pen activity -> ignore touch
      }
      if (state.hasActiveTouchStroke && !state.isTrackedTouch(e.device)) {
        state.cancelActiveTouchStroke(); // mirrors TouchDrawingInputHandler 2nd-touch-cancels
        return false;
      }
    }
    return true;
  }
}
```

Optional, *beyond* what Xournal++ does (call this out to whoever implements
it as an enhancement, not a port): Flutter also hands you `radiusMajor`/
`radiusMinor`, so a size-based heuristic (reject touch contacts above some
ellipse-area threshold as a palm) is easy to add as a second
`PalmRejectionPolicy` and compose — Xournal++ never had reliable contact-size
data on its target platforms, so it never built this, but there's no reason
not to in Dart if the target hardware reports it.

**`eventsToIgnore` / tap filter.** Keep both as small, independent, explicit
pieces rather than folding them into `InputRouter`: an `int ignoreRemaining`
counter seeded from a settings value on `onPointerDown` (rule 5), and a
`TapFilter` value object (max duration, max distance-in-mm converted through
DPI, min gap since last tap) invoked from `onPointerUp` before deciding
`target.end(...)` vs `target.tap(...)` — this mirrors
`isCurrentTapSelection` exactly but keeps it unit-testable in isolation.

---

## 2. Ink stroke model (`Stroke`, `Point`)

**Files:** `src/core/model/{Point,Stroke,StrokeContour}.{h,cpp}`,
`src/core/view/{StrokeView,StrokeViewHelper}.cpp`

### 2a. C++ model

**`Point`** (`Point.h`) is deceptively small: `double x, y, z`, where `z` is
pressure **and** doubles as `NO_PRESSURE = -1` sentinel. Critically, once a
point is attached to a `Stroke`, `z` is *not* a raw 0..1 pressure value — by
the time it's stored, it has already been resolved to the **actual
rendered line width in document units** for the segment starting at that
point (see `Stroke::getPoint(PathParameter)`'s comment: *"The point's width
should be that of the segment's first point"*, and `distanceTo()`'s
`p1.z == NO_PRESSURE ? this->width : p1.z`). `Stroke::hasPressure()` just
checks whether `points[0].z != NO_PRESSURE`; a stroke is either
uniform-width (fall back to `Stroke::width`) or fully variable-width, never
mixed.

**`Stroke`** (`Stroke.h/.cpp`) is `vector<Point> points` plus style metadata:
`width` (base/uniform width), `StrokeTool toolType` (`PEN`/`ERASER`/
`HIGHLIGHTER` — only `PEN` is pressure-sensitive, see
`StrokeTool::isPressureSensitive()`), `StrokeCapStyle` (`ROUND`/`BUTT`/
`SQUARE`), `fill` (-1 = unfilled, else 0..255 alpha), `LineStyle` (dashes).
Bounding boxes are maintained **incrementally** as points are added
(`Stroke::addPoint` → `updateBoundsLastTwoPressures`), not recomputed from
scratch each time — important for a tool that appends a point per motion
event.

**Rendering (how "variable width" actually becomes pixels).** This is the
part worth copying carefully: `StrokeViewHelper::drawWithPressure`
(`StrokeViewHelper.cpp:34`) does **not** stroke each segment with
`cairo_set_line_width` on the final raster target (it only does that on the
rarely-used direct-PDF-vector-export path, "to get smaller PDF files" per
the comment). For the normal raster path it builds **one filled outline
polygon** for the *entire* stroke via `StrokeContour` (`StrokeContour.cpp`)
and does a single `cairo_fill()`. `StrokeContour` walks the centerline,
offsets each side by half the local width along the segment normal, and
stitches consecutive segments together with an **exact arc** sized to the
width delta between them (not a generic miter/bevel) so a stroke that
tapers from thick to thin looks like a smooth cone, not a faceted polygon.
This is genuinely intricate trig (~350 lines) — worth knowing it exists, not
worth porting byte-for-byte (see Dart recommendation below).

**Translucent-tool correctness trick.** For the highlighter (drawn with
`CAIRO_OPERATOR_MULTIPLY` and alpha < 1), a naive fill would double-blend
wherever the stroke crosses itself. `StrokeView::draw` avoids this by
rendering the *entire* stroke fully opaque into an offscreen alpha-only
`Mask` first, then blitting that one mask at the desired group alpha in a
single compositing operation (`StrokeView.cpp:34-75`). Self-overlaps inside
the mask are opaque-over-opaque (harmless); only the final single blit
carries the transparency.

### 2b. Dart translation — `packages/sd_ink`

Keep points as an immutable value, and split "actively being drawn" from
"committed to the document" the same way Xournal++ implicitly does (an
`OverlayView`-drawn in-progress stroke vs. a `Stroke` sitting in a `Layer`):

```dart
/// One vertex of a stroke's centerline. Immutable (unlike Xournal++'s
/// mutable Point) so Stroke can be a cheap, shareable value — friendlier to
/// undo/redo and Flutter's rebuild model.
@immutable
class InkPoint {
  const InkPoint(this.x, this.y, [this.width]);
  final double x, y;
  /// null = "use Stroke.baseWidth" (Point.NO_PRESSURE sentinel).
  /// When set, this is the *resolved* width (document units) of the segment
  /// starting at this point — never a raw 0..1 pressure value. Resolve
  /// pressure -> width once, in the builder, not at paint time.
  final double? width;
}

enum InkTool { pen, highlighter, eraser } // eraser tool-type is only ever used by whiteout strokes — see §4
enum StrokeCap { round, butt, square }

@immutable
class Stroke {
  const Stroke({
    required this.points,
    required this.color,
    required this.baseWidth,
    this.tool = InkTool.pen,
    this.cap = StrokeCap.round,
    this.fillAlpha,     // null = unfilled (Point/Stroke's -1 sentinel, made a real nullable)
    this.dashPattern,
  });
  final List<InkPoint> points;
  final Color color;
  final double baseWidth;
  final InkTool tool;
  final StrokeCap cap;
  final int? fillAlpha;
  final List<double>? dashPattern;

  bool get hasVariableWidth => points.isNotEmpty && points.first.width != null;
  Rect get bounds => /* cached, computed like Stroke::calcSize */ ...;
}
```

```dart
/// Mutable, incremental builder used only while a pointer gesture is live.
/// Mirrors StrokeHandler's addPoint/paintTo behavior, including:
///  - PIXEL_MOTION_THRESHOLD: drop sub-threshold moves (but still let a
///    same-spot pressure *increase* thicken the first point).
///  - MAX_WIDTH_VARIATION: subdivide a segment into several shorter ones
///    when the pressure delta is too big, so the outline tapers smoothly
///    instead of forming a visible cone in one jump.
class StrokeBuilder {
  StrokeBuilder({required this.color, required this.baseWidth, required this.tool, this.cap = StrokeCap.round});
  static const pixelMotionThreshold = 0.3; // document units, == InputHandler::PIXEL_MOTION_THRESHOLD
  static const maxWidthVariation = 0.3;    // == StrokeHandler::MAX_WIDTH_VARIATION

  final Color color;
  final double baseWidth;
  final InkTool tool;
  final StrokeCap cap;
  final List<InkPoint> _points = [];

  void addSample(PenSample s, {required double? resolvedWidth}) { /* threshold + subdivision logic */ }
  Stroke build() => Stroke(points: List.unmodifiable(_points), color: color, baseWidth: baseWidth, tool: tool, cap: cap);
}
```

**Rendering recommendation.** Reproduce the *strategy*, simplify the
*geometry*:
1. **Do** build one filled outline path per stroke and fill it once — never
   stroke many overlapping segments on a raster target, for exactly the
   overdraw/blending reasons Xournal++ avoids it.
2. **Do** reproduce the translucent-correctness trick using Flutter's own
   built-in primitive for it — `Canvas.saveLayer(bounds, Paint()..color =
   color.withOpacity(alpha))`, draw the shape fully opaque inside that
   layer, then `restore()`. This is a direct, idiomatic match for the
   manual cairo-mask-then-blit dance and needs no cairo-style plumbing.
3. **Don't** feel obliged to port `StrokeContour`'s exact arc-jointing at
   segment-width transitions. A pragmatic default that looks correct at ink
   scale and is far simpler to implement/maintain: build the outline as a
   **capsule chain** — a filled circle of the local width at every vertex
   plus a filled quad (trapezoid) connecting each consecutive pair of
   vertices, all accumulated into one `Path` (even-odd or nonzero fill) or
   drawn as one `saveLayer` group of primitives per point 2's alpha trick.
   Round per-vertex stamps naturally produce round joins with no extra
   miter logic. Only reach for the exact `StrokeContour` algorithm later if
   a design review specifically wants pixel-parity tapering.
4. The eraser's geometric hit-testing (§4) needs the *same* per-segment
   width lookup as rendering — implement `Stroke.widthAt(int segmentIndex)`
   once and share it between the painter and `ErasableStroke`.

---

## 3. Pressure inference for pressureless devices

**File:** `src/core/gui/inputdevices/PenInputHandler.cpp:183-234` (declared
`PenInputHandler.h:143,153`, mode enum at `PenInputHandler.h:23`).

### 3a. The exact formula found

```cpp
double PenInputHandler::inferPressureValue(PositionInputData const& pos, XojPageView* page) {
    PositionInputData lastPos = getInputDataRelativeToCurrentPage(page, this->lastEvent);

    double dt = (pos.timestamp - lastPos.timestamp) / 10.0;
    double distance = xoj::util::Point<double>(pos.x, pos.y)
                           .distance(xoj::util::Point<double>(lastPos.x, lastPos.y));
    double inverseSpeed = dt / (distance + 0.001);

    // Arctan for its sigmoid-like shape, so lim(inverseSpeed->inf) is finite.
    double newPressure = 3.142 / 2.0 + std::atan(inverseSpeed * 3.14 - 1.3);

    // Weighted average: smooths abrupt jumps and ramps pressure up initially.
    newPressure = std::min(newPressure, 2.0) / 5.0 + this->lastPressure * 4.0 / 5.0;

    // Single-point case (no movement since last sample).
    if (distance == 0) {
        newPressure = std::sqrt(dt / 10.0) - 0.1;
    }

    this->lastPressure = newPressure;
    return (newPressure * 1.1 + 0.8) / 2.0;   // final rescale
}
```

This **confirms the shape the task described** (`π/2 + atan(inverseSpeed·3.14
− 1.3)`), with corrections worth preserving exactly if parity matters:

- The distance-guard epsilon is **0.001, not 0.01**.
- `π/2` is written as the literal `3.142/2.0`, while the multiplier inside
  `atan` uses the *separate* literal `3.14` — two slightly different
  hand-rounded approximations of π in the same expression. Reproduce as-is
  if bit-for-bit behavior matters; otherwise both can safely become
  `math.pi` in Dart (the intent is clearly π either way, and the visual
  difference is imperceptible).
- The raw arctan result is **not** the final answer: it's clamped
  (`min(_, 2.0)`), then blended 20%-new/80%-previous with the last accepted
  pressure (an exponential moving average) — this is the actual smoothing
  Xournal++ applies frame-to-frame, not a separate stabilizer.
- There's a **stationary-pointer special case**: if `distance == 0` (two
  samples at the exact same pixel), pressure instead grows as `sqrt(dt/10) −
  0.1`, i.e. purely a function of elapsed time — this is what makes
  pressure ramp up visibly if you press down and hold before moving.
- The return value is **not a 0..1 pressure** — it's rescaled by
  `(x·1.1+0.8)/2`, landing roughly in the 0.4–1.5ish range, then in
  `filterPressure` gets `max(minimumPressure, value * pressureMultiplier)`
  applied (`Settings` defaults: `minimumPressure = 0.05` floor-clamped to
  ≥0.01, `pressureMultiplier = 1.0`). Downstream (`StrokeHandler`), this
  number is used **directly as a width multiplier**
  (`point.z = pressure * stroke->getWidth()`), not as a normalized
  intensity that gets remapped again. Treat "pressure" throughout this
  pipeline as *"a width-scale factor,"* not *"0..1 intensity."*

**Where it's applied.** `PenInputHandler` picks one of three modes at
`actionStart` (`PressureMode` enum, `PenInputHandler.h:23`):
`DEVICE_PRESSURE` (the very first sample already reported real pressure),
`INFERRED_PRESSURE` (first sample had none, but
`Settings::isPressureGuessingEnabled()` is on), or `NO_PRESSURE` (flat
width). The chosen mode is fixed for the whole gesture and re-evaluated
through `filterPressure` on every subsequent `actionMotion`/`actionEnd` —
this pipeline runs identically for stylus **and mouse** input (mouse
gestures always end up in `INFERRED_PRESSURE` or `NO_PRESSURE`, never
`DEVICE_PRESSURE`), so a mouse-drawn stroke also gets natural-looking
variable width if pressure guessing is enabled.

**A subtlety worth deliberately fixing, not replicating:** `pos.x`/`pos.y`
here are **on-screen pixel coordinates at the current zoom** (they come from
`getInputDataRelativeToCurrentPage`, which subtracts the page's *pixel*
position from the event's *layout pixel* coordinates — zoom is not divided
out until later, inside `StrokeHandler`). That makes the inferred-pressure
curve implicitly zoom-dependent: the same physical hand speed produces a
different `distance` (and thus a different inferred pressure) at 100% zoom
vs 400% zoom. This looks unintentional. **For the Dart port, compute
`distance` in document units** (i.e., after dividing by zoom), so inferred
line width is stable regardless of the user's current zoom level.

### 3b. Dart translation

```dart
enum PressureSource { device, inferred, none }

abstract interface class PressureEstimator {
  void start(PenSample first);
  /// [previous] is the last *accepted* sample (mirrors PenInputHandler::lastEvent).
  /// Returns a width-scale factor, not a normalized 0..1 value — matches the
  /// original's semantics exactly so downstream width math needs no rescale.
  double resolve(PenSample sample, PenSample previous);
}

class SpeedBasedPressureEstimator implements PressureEstimator {
  double _lastPressure = 0.0;

  @override
  void start(PenSample first) => _lastPressure = 0.0;

  @override
  double resolve(PenSample sample, PenSample previous) {
    final dtMs = (sample.timestamp - previous.timestamp).inMicroseconds / 1000.0 / 10.0;
    // NOTE: docPosition must already be in document units (zoom divided out) —
    // this is the deliberate fix vs. the C++ source's screen-pixel distance.
    final distance = (sample.docPosition - previous.docPosition).distance;
    final inverseSpeed = dtMs / (distance + 0.001);

    var p = (math.pi / 2) + math.atan(inverseSpeed * math.pi - 1.3);
    p = math.min(p, 2.0) / 5.0 + _lastPressure * 4.0 / 5.0;
    if (distance == 0) {
      p = math.sqrt(dtMs / 10.0) - 0.1;
    }
    _lastPressure = p;
    return (p * 1.1 + 0.8) / 2.0;
  }
}

/// Ties device/inferred/none together, mirrors PenInputHandler's PressureMode
/// selection + filterPressure's clamp-and-scale.
class PressureResolver {
  PressureResolver({
    required this.guessingEnabled,
    required this.minimumWidthScale,  // Settings::minimumPressure, default 0.05, floor 0.01
    required this.multiplier,         // Settings::pressureMultiplier, default 1.0
    required this.estimator,
  });
  final bool guessingEnabled;
  final double minimumWidthScale;
  final double multiplier;
  final PressureEstimator estimator;

  PressureSource? _mode;
  double _lastAccepted = 0.0;

  double? resolveFirst(PenSample first) {
    _mode = first.rawPressure != null
        ? PressureSource.device
        : (guessingEnabled ? PressureSource.inferred : PressureSource.none);
    estimator.start(first);
    return _mode == PressureSource.none ? null : _clamp(first.rawPressure ?? 0);
  }

  double? resolve(PenSample sample, PenSample previous) {
    if (_mode == PressureSource.none) return null;
    final raw = switch (_mode!) {
      PressureSource.inferred => estimator.resolve(sample, previous),
      PressureSource.device => sample.rawPressure ?? _lastAccepted, // last-known fallback, rule 2
      PressureSource.none => 0.0,
    };
    _lastAccepted = raw;
    return _clamp(raw);
  }

  double _clamp(double v) => math.max(minimumWidthScale, v * multiplier);
}
```

`StrokeBuilder.addSample` (§2b) calls `PressureResolver` once per sample and
multiplies the result by `baseWidth` to get `InkPoint.width` — exactly
mirroring `point.z = pressure * stroke->getWidth()`.

---

## 4. `EraseHandler` — standard / whiteout / delete-stroke

**Files:** `src/core/control/tools/EraseHandler.{h,cpp}`,
`src/core/model/eraser/{ErasableStroke,ErasableStrokeOverlapTree}.{h,cpp}`,
`src/core/model/Stroke.cpp` (`intersects`, `intersectWithPaddedBox`)

### 4a. C++ algorithm

`EraseHandler::erase(x, y)` (`EraseHandler.cpp:46`) is called once per
pointer-move sample while the eraser is down. It first does a broad-phase
query: build a square eraser footprint (`2×halfEraserSize`) and iterate only
the strokes on the active layer whose **bounding box** intersects it
(`Element::getBoundingBox().intersects(eraserRect)`), then dispatches per
stroke to `eraseStroke`, which branches on `EraserType`:

**Delete-stroke mode (`ERASER_TYPE_DELETE_STROKE`).** Narrow-phase hit test
via `Stroke::intersects(x, y, halfEraserSize)` (`Stroke.cpp:444`): for each
segment, either the eraser square contains one of its endpoints, or the
segment passes close enough to the square's center (perpendicular
distance-to-infinite-line check, then a distance-to-segment-midpoint circle
check as a cheap "is it actually near *this* segment, not just the infinite
line" guard). On any hit, the **entire element** is removed from the layer
immediately and recorded in a `DeleteUndoAction` (one shared action across
the whole eraser drag, appended to as more strokes get hit).

**Standard mode (default).** This is the interesting one. On first contact
with a stroke, it's wrapped in an `ErasableStroke` (a *copy* of the original
`Stroke`, `ErasableStroke.cpp:23`) whose entire job is to track **which
sub-intervals of the stroke's path parameter space are still ink**, as a
`UnionOfIntervals<PathParameter>`. A `PathParameter` is `(segmentIndex, t ∈
[0,1])` — a position along the polyline. The hit box itself is padded:
`PaddedBox{ inner = exact eraser square, outer = inner + capStyleCoefficient
× strokeWidth }` (`EraseHandler.cpp:101-102`), with
`PADDING_COEFFICIENT_CAP = {ROUND: 0.4, BUTT: 0.01, SQUARE: 0.5}` indexed by
`StrokeCapStyle` — the **outer** box is what actually gets removed (so a
thick stroke doesn't leave a visible stub right at the cursor edge), but a
segment only counts as hit if it also touches the tighter **inner** box
(so you don't erase pixels that were never visually near the cursor,
`ErasableStroke.cpp:31-38` doc comment explains this explicitly). Each move
sample calls `Stroke::intersectWithPaddedBox` to get new
in/out-of-box crossing parameters, which get subtracted
(`UnionOfIntervals::intersect`) from the remaining-sections set — **no
geometry is rebuilt per move**, it's pure interval algebra, so a long erase
drag over a complex stroke stays cheap. A bounding-box cache
(`boundingBoxes`, keyed by sub-section) avoids recomputing a sub-range's
`Range` repeatedly during the same drag. Only when the eraser gesture ends
does `EraseHandler::finalize()` → `ErasableStroke::getStrokes()` materialize
the surviving intervals into actual new `Stroke` objects via
`Stroke::cloneSection`/`cloneCircularSectionOfClosedStroke` (the latter
handles a *closed* stroke — e.g. a hand-drawn circle — correctly stitching
the wrap-around segment into one piece instead of two), and these replace
the original stroke in the layer as one `EraseUndoAction`.

For highlighter and filled strokes specifically, `ErasableStroke` does
extra work (`addOverlapsToRange`, backed by `ErasableStrokeOverlapTree`, a
small per-erase binary tree of segment bounding boxes) purely to compute a
*tighter* repaint region where a split stroke's two halves visually overlap
(translucent strokes need that overlap repainted, opaque ones don't) — this
is a repaint-optimization detail, not a correctness requirement.

**Whiteout mode is not in `EraseHandler` at all.** Confirmed at
`EraseHandler.cpp:44`: *"Handle eraser event: 'Delete Stroke' and
'Standard', Whiteout is not handled here."* It's routed at the
tool-dispatch layer: `XojPageView::onButtonPressEvent`
(`PageView.cpp:256-258`) treats `TOOL_ERASER` + `ERASER_TYPE_WHITEOUT`
exactly like `TOOL_PEN`/`TOOL_HIGHLIGHTER` and constructs a `StrokeHandler`.
`InputHandler::createStroke` (`InputHandler.cpp:48-50`) then sets
`toolType = StrokeTool::ERASER` (used only for later identification) but
forces `color = Colors::white`, and `StrokeTool::isPressureSensitive()`
returns `false` for `ERASER` — so **whiteout is just an ordinary, fully
opaque, non-pressure-sensitive pen stroke drawn in a fixed color**, going
through the exact same `StrokeHandler`/stabilizer/rendering pipeline as any
other stroke. It has no geometric relationship to the eraser at all.

### 4b. Dart translation — `packages/sd_ink`

```dart
/// A position along a stroke's centerline: segment index + local t ∈ [0,1].
/// Mirrors Xournal++'s PathParameter; Comparable so spans can be ordered/merged.
@immutable
class StrokePathParam implements Comparable<StrokePathParam> {
  const StrokePathParam(this.segmentIndex, this.t);
  final int segmentIndex;
  final double t;
  @override
  int compareTo(StrokePathParam o) =>
      segmentIndex != o.segmentIndex ? segmentIndex.compareTo(o.segmentIndex) : t.compareTo(o.t);
}

@immutable
class StrokeSpan {
  const StrokeSpan(this.min, this.max);
  final StrokePathParam min, max; // inclusive run of still-remaining ink
}

/// Padded hit box for one eraser sample: `inner` gates whether a segment
/// counts as touched at all, `outer` is what actually gets removed —
/// mirrors EraseHandler's PaddedBox + PADDING_COEFFICIENT_CAP.
class PaddedEraserBox {
  PaddedEraserBox(Offset center, double halfEraserSize, double strokeWidth, StrokeCap cap)
      : inner = Rect.fromCircle(center: center, radius: halfEraserSize),
        outer = Rect.fromCircle(center: center, radius: halfEraserSize + _padding[cap]! * strokeWidth);
  final Rect inner, outer;
  static const _padding = {StrokeCap.round: 0.4, StrokeCap.butt: 0.01, StrokeCap.square: 0.5};
}

/// Tracks which parts of one stroke remain, for the lifetime of one eraser
/// drag. Pure parameter-space bookkeeping — mirrors ErasableStroke: no
/// geometry is rebuilt per pointer-move, only interval subtraction.
class ErasableStroke {
  ErasableStroke(this.original)
      : _remaining = [StrokeSpan(const StrokePathParam(0, 0), StrokePathParam(original.points.length - 2, 1))];

  final Stroke original;
  List<StrokeSpan> _remaining;

  bool get isFullyErased => _remaining.isEmpty;

  /// Subtracts every sub-span whose segments cross [box.outer] and touch
  /// [box.inner]; returns the document-space rect that needs repainting.
  Rect erase(PaddedEraserBox box) { /* interval subtraction, mirrors ErasableStroke::erase */ throw UnimplementedError(); }

  /// Materializes remaining spans into 0..N strokes on pointer-up. Handles
  /// the closed-stroke wrap-around case like cloneCircularSectionOfClosedStroke.
  List<Stroke> commit() { throw UnimplementedError(); }
}
```

```dart
enum EraserMode { standard, deleteStroke } // whiteout deliberately excluded — see below

class EraseController {
  EraseController(this.layer, this.mode, this.eraserDiameter);
  final InkLayer layer;
  final EraserMode mode;
  final double eraserDiameter;
  final Map<Stroke, ErasableStroke> _inProgress = {};
  Rect? _dirty;

  /// Called per pointer-move sample. Broad-phase: only strokes whose bounds
  /// intersect the eraser footprint are touched (mirrors EraseHandler::erase's
  /// initial bounding-box filter).
  void eraseAt(Offset point) {
    final half = eraserDiameter / 2;
    for (final stroke in layer.strokesIntersecting(Rect.fromCircle(center: point, radius: half))) {
      if (mode == EraserMode.deleteStroke) {
        if (stroke.hitTest(point, half)) {
          layer.remove(stroke);
          _markDirty(stroke.bounds);
        }
        continue;
      }
      final erasable = _inProgress.putIfAbsent(stroke, () => ErasableStroke(stroke));
      _markDirty(erasable.erase(PaddedEraserBox(point, half, stroke.baseWidth, stroke.cap)));
    }
  }

  void _markDirty(Rect r) => _dirty = _dirty == null ? r : _dirty!.expandToInclude(r);

  /// Call on pointer-up: replace each touched stroke with its remaining
  /// pieces (or remove it entirely), as ONE undo entry — mirrors
  /// EraseHandler::finalize() + EraseUndoAction/DeleteUndoAction.
  EraseResult finish() { throw UnimplementedError(); }
}
```

**Whiteout stays out of `EraseController` entirely** — reproduce the
original's routing decision, not a special case inside the eraser. Branch
at tool-selection time, before input even reaches the eraser vs. stroke
pipeline:

```dart
PointerGestureTarget resolveDrawingTarget(InkTool selectedTool, EraserMode? eraserMode, Color activeColor, Color pageBackground) {
  final isWhiteout = selectedTool == InkTool.eraser && eraserMode == null /* == whiteout in this design */;
  if (selectedTool != InkTool.eraser || isWhiteout) {
    return StrokeBuilderTarget(
      color: isWhiteout ? pageBackground : activeColor,
      pressureSensitive: selectedTool == InkTool.pen, // matches StrokeTool::isPressureSensitive()
    );
  }
  return EraseTarget(controller: eraseController); // standard / deleteStroke only
}
```

The `ErasableStrokeOverlapTree` self-overlap-repaint-region optimization is
safe to skip in a first pass: falling back to "repaint the whole bounding
box of any stroke that got split" is strictly correct, just occasionally
repaints a bit more than necessary for translucent strokes — a perf
refinement, not a correctness requirement, and easy to add later behind the
same `_markDirty` call site.

---

## 5. LaTeX integration

**Files:** `src/core/control/{LatexController,latex/LatexGenerator}.{h,cpp}`,
`src/core/model/TexImage.{h,cpp}`, `src/core/control/settings/LatexSettings.h`

### 5a. C++ architecture

Three cooperating pieces:

- **`LatexController`** (`LatexController.h/.cpp`) — orchestrates a dialog
  session: finds/creates the temp working dir, drives the "re-render on
  every keystroke" loop, and performs the final document insert/replace.
- **`LatexGenerator`** (`latex/LatexGenerator.h/.cpp`) — stateless-ish
  process runner + template substitution.
- **`TexImage`** (`model/TexImage.h/.cpp`) — the embedded document element.

**Template substitution** (`LatexGenerator::templateSub`,
`LatexGenerator.cpp:26`): the user's global template file contains
`%%XPP_KEY%%` placeholders. The *typed* LaTeX source is pre-scanned line by
line for `%xpp:KEY=value` directives (letting a formula override
template variables inline); its remaining body becomes the
`%%XPP_TOOL_INPUT%%` substitution, and the tool's current color becomes
`%%XPP_TEXT_COLOR%%` (as a hex string) — so the compiled snippet always
picks up the pen color the user had selected when opening the dialog.

**Temp file handling.** One temp directory per session
(`Util::getTmpDirSubfolder("tex")`), reused for every re-render — the file
is always named `tex.tex` in / `tex.pdf` out, simply **overwritten** on each
keystroke-triggered recompile. There is **no cache keyed by formula content**
across renders or across app runs; regenerating is cheap enough (a few
hundred ms of `pdflatex`) that Xournal++ doesn't bother memoizing identical
strings. The directory *does* implicitly serve as a single-slot "last
render" cache purely because the filenames are fixed.

**Process invocation** (`LatexGenerator::asyncRun`,
`LatexGenerator.cpp:96`): the configured command template
(default `pdflatex -halt-on-error -interaction=nonstopmode '{}'`, with `{}`
substituted for the tex file's OS-encoded path) is tokenized via
`g_shell_parse_argv`, the program resolved via `g_find_program_in_path`
(with a Flatpak-specific error hint if not found — "install the freedesktop
Tex Live extension"), then spawned via `GSubprocess` with stdout+stderr
**merged into one stream** and run **asynchronously**
(`g_subprocess_communicate_utf8_async`) so the UI never blocks. A
`GCancellable` is kept so a still-running compile can be cancelled if the
dialog closes.

**Debounced re-render while typing** (`LatexController::triggerImageUpdate`
+ `handleTexChanged` + `onPdfRenderComplete`): a text-changed signal calls
`triggerImageUpdate`, which is a no-op if a render is already in flight
(`isUpdating()`); on completion, `onPdfRenderComplete` checks whether the
buffer's text changed *again* while that render was running
(`shouldUpdate = lastPreviewedTex != currentTex`) and immediately kicks off
another render if so — this coalesces bursts of keystrokes into "always
converge to a render of the *latest* text" without ever queuing more than
one compile at a time.

**Embedding — both source and output persist in the document.**
`TexImage::serialize` (`TexImage.cpp:132`) writes **both** the original
LaTeX source string (`text`) and the raw compiled **PDF bytes**
(`binaryData`) into the `.xopp` file. On load, `TexImage::loadData`
(`TexImage.cpp:82`) sniffs the byte signature (`"...PDF"` vs `"...PNG"`,
PNG being a deprecated legacy path) and loads the PDF via
`poppler_document_new_from_bytes` for on-demand rasterization at any zoom —
**no LaTeX toolchain is needed just to *view* a document that already
contains rendered formulas**, only to *edit* one. This is what makes the
embed both "editable" (the exact source round-trips back into the edit
dialog) and "self-contained" (rendering never depends on external state
after the fact).

**Insert/replace flow** (`LatexController::insertLatex` /
`insertTexImage`): clicking near an existing `TexImage` or `Text` element
pre-loads its source into the dialog (`initialTex = img->getText()`) for
in-place editing; on confirm, the old element is removed and the new one
inserted preserving the **on-page height and aspect ratio** of the old one,
as a single `GroupUndoAction` wrapping a delete + an insert — so undo
reverts the edit as one step, not two.

### 5b. Dart translation

Natural home: a small standalone package (e.g. `packages/sd_latex`) that
plugs into wherever the embedded-object/document model lives, since it's
conceptually adjacent to but independent of `sd_ink`.

```dart
/// An embedded, re-editable LaTeX object. Both fields persist in the
/// document — mirrors TexImage storing both `text` and `binaryData`.
@immutable
class LatexEmbed {
  const LatexEmbed({required this.id, required this.source, required this.renderedPdfBytes, required this.rect});
  final String id;
  final String source;             // exact LaTeX typed by the user
  final Uint8List renderedPdfBytes; // compiled output — render-from-this, never re-invoke LaTeX just to *view*
  final Rect rect;                 // page placement + size
}
```

```dart
class LatexGenerator {
  LatexGenerator(this.settings);
  final LatexSettings settings; // command template ("{}" placeholder), template file path

  Future<LatexRenderResult> render(String source, {required Color textColor}) async {
    final dir = await _sessionTempDir();               // one reused dir, mirrors Util::getTmpDirSubfolder("tex")
    final texContents = _substituteTemplate(source, await _loadTemplate(), textColor);
    final texFile = File(p.join(dir.path, 'tex.tex'))..writeAsStringSync(texContents);

    final argv = _tokenizeCommand(settings.genCmd, texFile.path); // same "{}" substitution + shell-style tokenizing
    final proc = await Process.start(argv.first, argv.skip(1).toList(),
        workingDirectory: dir.path, runInShell: false);
    final output = await _mergedStdoutStderr(proc);     // merge streams, mirrors STDERR_MERGE
    final exitCode = await proc.exitCode;

    if (exitCode != 0) return LatexRenderResult.failure(output: output);
    final pdfBytes = await File(p.join(dir.path, 'tex.pdf')).readAsBytes();
    return LatexRenderResult.success(pdfBytes: pdfBytes, output: output);
  }
}
```

Reproduce the coalescing-while-typing state machine explicitly (it is the
one piece of real control flow worth keeping, not just the process call):

```dart
/// Mirrors LatexController's isUpdating()-guarded + "re-run if text changed
/// meanwhile" loop: never more than one compile in flight, always converges
/// to a render of the latest text.
class LatexEditSession extends ChangeNotifier {
  LatexEditSession(this._generator);
  final LatexGenerator _generator;

  LatexRenderResult? preview;
  bool get isRendering => _inFlight;
  bool _inFlight = false;
  String _pending = '';
  String _lastRendered = '';

  void onSourceChanged(String source) {
    _pending = source;
    if (_inFlight) return; // coalesce
    _runNext();
  }

  Future<void> _runNext() async {
    _inFlight = true;
    final source = _lastRendered = _pending;
    preview = await _generator.render(source, textColor: activeColor);
    _inFlight = false;
    notifyListeners();
    if (_pending != _lastRendered) _runNext(); // text moved on while we were compiling
  }
}
```

**Rendering note.** Dart has no built-in PDF rasterizer. Two honest
options, either way keeping the PDF (or an SVG) as the persisted source of
truth so files stay portable and re-editable exactly like `TexImage`:
(a) use a PDF-rendering plugin to rasterize on demand at the current zoom
(closest fidelity to Poppler+cairo doing it live), or (b) rasterize once at
insert time to a fixed-resolution raster cached per zoom bucket, accepting
some softness at extreme zoom. Don't design the model around a specific
package choice — `LatexEmbed.renderedPdfBytes` stays the same regardless.

**Insert/replace**: mirror `insertTexImage`'s three behaviors directly —
replace-in-place when editing an existing `LatexEmbed` (preserve its height
and aspect ratio from the *old* rect when sizing the new one from its
native PDF page size), insert-new otherwise, and wrap a replace as one
grouped undo command (delete-old + insert-new) so undo is one step.

---

## 6. Repaint / dirty-region invalidation (`XojPageView` et al.)

**Files:** `src/core/gui/{PageView,RepaintHandler,LegacyRedrawable}.{h,cpp}`,
`src/core/view/{Repaintable.h,Mask.h}`,
`src/core/control/jobs/{RenderJob,Scheduler,XournalScheduler}.{h,cpp}`,
`src/core/gui/widgets/XournalWidget.cpp` (`gtk_xournal_repaint_area`)

### 6a. C++ architecture

**Repaint vs. rerender — the load-bearing distinction.** Spelled out in
`LegacyRedrawable.h`'s deprecation comment: *repaint* = "ask GTK to blit the
existing buffer again" (cheap — no content regeneration); *rerender* =
"change the buffer's content" (expensive — re-run Cairo drawing from the
document model). Nearly every optimization in this subsystem exists to
keep input handling on the *repaint* side and push *rerender* onto a
background thread, batched, and clipped to the smallest possible rectangle.

**Persistent per-page raster buffer.** Each `XojPageView` owns one
`xoj::view::Mask buffer` — a real, persistent Cairo surface that survives
across frames (`PageView.h:264`). The GTK draw callback,
`XojPageView::paintPage` (`PageView.cpp:1089`), does almost nothing: scale
for zoom, **blit the existing buffer** (`buffer.paintTo(cr)`), then draw
every entry in `overlayViews` on top (`PageView.cpp:1117-1119`) — the
in-progress stroke, selection handles, text cursor, etc. Overlays are
redrawn **fresh from their own in-memory state every single frame**; they
never touch `buffer` until they're finished.

**Dirty-rect coalescing.** `XojPageView::rerenderRect`
(`PageView.cpp:914`) merges each new dirty rectangle into
`rerenderRects` by unioning it with the first pending rect it intersects
("it's faster to redraw only one rect than repaint twice the same area"),
appending only if it overlaps nothing pending, then schedules **one**
`RenderJob` for the page (`XournalScheduler::addRerenderPage`, which
no-ops if a render job for that page is already queued —
`existsSource(...)`). So N rapid `rangeChanged`/`rectChanged` calls between
two frames collapse into exactly one background job operating on one
unioned rect list.

**Background execution.** `RenderJob::run()` (`RenderJob.cpp:63`) executes
on a `Scheduler` thread pool at `JOB_PRIORITY_URGENT`, off the UI thread. It
either (a) if a full-page rerender was requested (`rerenderComplete`, e.g.
after a page resize), builds an entirely new full-page `Mask` from scratch
via `DocumentView::drawPage` and atomically `swap`s it in under
`drawingMutex`; or, far more commonly, (b) for each accumulated dirty
rect, renders *only that rect* (padded by 1px to avoid antialiasing seams,
`RenderJob.cpp:45`) into a small scratch `Mask`, then `paintTo`s that patch
onto the existing persistent `buffer` under the same mutex — the big
surface is **patched incrementally**, never discarded.

**Invalidate only what's visible.** After patching the buffer, the job asks
the UI thread (`Util::execInUiThread`) to invalidate the corresponding
*widget*-space rectangle. `gtk_xournal_repaint_area`
(`XournalWidget.cpp:252`) intersects that rectangle with the **currently
visible scroll viewport** first and drops the call entirely if the result
is empty — a page-40 edit while viewing page 2 never reaches
`gtk_widget_queue_draw_area` at all. Only the surviving, viewport-clipped
rect is queued for GTK's own partial repaint.

**Why an in-progress stroke never triggers this whole pipeline per
motion event.** `StrokeHandler`'s view is an `OverlayView`, added to
`overlayViews` once at button-press. Every motion event just appends a
point to it and calls `flagDirtyRegion` for the small growing region —
that's a `repaintArea`, i.e. the *cheap* path (`XojPageView::flagDirtyRegion`
→ `repaintArea` → `RepaintHandler::repaintPageArea` →
`gtk_xournal_repaint_area`, straight to GTK, **no background `RenderJob`
involved**). Only on button-release does the finished stroke get baked in —
and even then, `drawAndDeleteToolView` (`PageView.cpp:869`) draws the
overlay's final content **directly onto the live `buffer`** under
`drawingMutex` in one shot, still without going through the
accumulate-then-background-rerender machinery; that machinery exists for
document mutations that need real re-rasterization from the model (undo,
loading, other layers changing underneath), not for the hot path of "a
stroke is currently being drawn."

### 6b. Flutter/Dart translation

Map the two-tier repaint/rerender split onto two stacked, independently
`RepaintBoundary`-wrapped layers per page — this is the direct structural
analogue of "persistent buffer + live overlay list":

```dart
/// The "buffer": committed document content only. Wrapped in its own
/// RepaintBoundary so Flutter caches its rasterization as a compositor
/// layer and skips re-running paint() unless shouldRepaint says otherwise —
/// this **is** "repaint = blit the cached surface" in Flutter terms.
class CommittedContentLayer extends StatelessWidget {
  const CommittedContentLayer({required this.page, required this.epoch});
  final PageModel page;
  final int epoch; // bumped only when committed content actually changes
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _CommittedPainter(page, epoch)),
      );
}

class _CommittedPainter extends CustomPainter {
  _CommittedPainter(this.page, this.epoch);
  final PageModel page;
  final int epoch;
  @override
  void paint(Canvas canvas, Size size) { /* draw every committed Stroke/embed */ }
  @override
  bool shouldRepaint(_CommittedPainter old) => old.epoch != epoch; // the "rerender" trigger
}

/// The "overlayViews": current gesture only (in-progress stroke, eraser
/// cursor, selection handles). A separate RepaintBoundary + its own cheap
/// repaint driven straight from pointer callbacks — never touches the
/// committed layer's cache.
class ActiveGestureLayer extends StatelessWidget {
  const ActiveGestureLayer({required this.liveStroke});
  final ValueListenable<Stroke?> liveStroke; // updated on every onPointerMove
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ValueListenableBuilder<Stroke?>(
          valueListenable: liveStroke,
          builder: (context, stroke, _) => CustomPaint(painter: _LiveStrokePainter(stroke)),
        ),
      );
}
```

**Dirty-region coalescing** — reproduce the merge-then-flush-once-per-frame
behavior explicitly rather than relying on widget rebuilds alone, since
`shouldRepaint` is a boolean, not a rectangle: keep an accumulator so many
small model mutations inside one frame become exactly one epoch bump / one
tile patch, mirroring `rerenderRect`'s merge loop plus
`XournalScheduler::addRerenderPage`'s de-dup:

```dart
/// Coalesces document-space dirty rects between frames, mirroring
/// XojPageView::rerenderRect's merge-on-intersect loop + the single
/// RenderJob-per-page de-dup in XournalScheduler::addRerenderPage.
class DirtyRegionAccumulator {
  DirtyRegionAccumulator(this.onFlush);
  final void Function(List<Rect> rects) onFlush;
  final List<Rect> _pending = [];
  bool _scheduled = false;

  void markDirty(Rect r) {
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i].overlaps(r)) {
        _pending[i] = _pending[i].expandToInclude(r);
        _schedule();
        return;
      }
    }
    _pending.add(r);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final rects = List<Rect>.of(_pending);
      _pending.clear();
      onFlush(rects);
    });
  }
}
```

**Patch, don't rebuild, for large documents.** A single `CustomPainter`
re-running `paint()` for a whole busy page on every small edit is the
Flutter equivalent of Xournal++ choosing `rerenderComplete` (full-page
rebuild) — fine occasionally, wasteful as the steady state. For the steady
state, mirror the "patch the persistent Mask" behavior directly: maintain a
cached `ui.Image` (rendered once via `PictureRecorder`/`Canvas`) per page (or
per macro-tile for very large pages), and on each accumulated-dirty-rect
flush, paint *only the new/changed strokes* onto a small offscreen canvas
sized to the union of the flushed rects and composite that patch onto the
cached image — instead of re-drawing every stroke on the page again. This
is strictly an optimization to reach for once profiling shows
whole-page-`CustomPainter` isn't cheap enough; ship the simple
`shouldRepaint`-on-epoch version first.

**Viewport clipping comes for free — use it.** Xournal++ has to manually
intersect every dirty rect with the current scroll viewport
(`gtk_xournal_repaint_area`) because GTK doesn't know which pages are
off-screen. In Flutter, put pages in a `ListView.builder`/`SliverList` (or
a custom `Viewport`) so off-screen pages are never built or painted at
all — structurally stronger than the manual check, not an equivalent to
reimplement. Only *visible* `CommittedContentLayer`/`ActiveGestureLayer`
pairs exist as widgets in the first place; an edit to an off-screen page
should only bump that page's `epoch`/cached image, not attempt to touch a
widget that doesn't currently exist.

**Gesture-end commit** mirrors `drawAndDeleteToolView`: on pointer-up,
paint the just-finished stroke directly onto the page's cached committed
image once (a single incremental patch), then swap `liveStroke` back to
`null` — avoid bumping `epoch` and forcing a full `_CommittedPainter.paint()`
re-run just to bake in the one stroke that was, until a moment ago, already
being drawn correctly by `ActiveGestureLayer`.

---

## Summary: where each concept lands

| Xournal++ concept | File(s) | Proposed Dart type | Package |
|---|---|---|---|
| `InputContext`/`AbstractInputHandler` dispatch | `gui/inputdevices/InputContext.cpp`, `AbstractInputHandler.cpp` | `InputRouter` | `sd_input` |
| `PositionInputData`/`InputEvent` | `PositionInputData.h`, `InputEvents.h` | `PenSample` | `sd_input` |
| Device classification / `knownDevices` | `InputEvents.cpp`, `DeviceId.h` | `DeviceClassifier` | `sd_input` |
| `HandRecognition` + `TouchDrawingInputHandler` 2nd-touch | `HandRecognition.cpp`, `TouchDrawingInputHandler.cpp` | `PalmRejectionPolicy` | `sd_input` |
| `eventsToIgnore` / tap filter | `StylusInputHandler.cpp`, `PenInputHandler.cpp:236` | `_PointerStream.ignoreRemaining`, `TapFilter` | `sd_input` |
| `PenInputHandler::inferPressureValue`/`filterPressure` | `PenInputHandler.cpp:183-234` | `PressureEstimator`, `PressureResolver` | `sd_input` |
| `Point`/`Stroke` | `model/Point.*`, `model/Stroke.*` | `InkPoint`, `Stroke` | `sd_ink` |
| `StrokeHandler`/`StrokeStabilizer` | `control/tools/StrokeHandler.cpp`, `StrokeStabilizer.cpp` | `StrokeBuilder`, `StrokeStabilizer` impls | `sd_ink` |
| `StrokeContour` variable-width fill | `model/StrokeContour.cpp`, `view/StrokeViewHelper.cpp` | outline-path painter (simplified capsule chain) | `sd_ink` |
| `EraseHandler`/`ErasableStroke` | `control/tools/EraseHandler.cpp`, `model/eraser/ErasableStroke.cpp` | `EraseController`, `ErasableStroke` | `sd_ink` |
| Whiteout routing | `PageView.cpp:256-258`, `InputHandler.cpp:48-50` | `resolveDrawingTarget()` branch | `sd_ink` |
| `LatexController`/`LatexGenerator`/`TexImage` | `control/LatexController.cpp`, `control/latex/LatexGenerator.cpp`, `model/TexImage.cpp` | `LatexEmbed`, `LatexGenerator`, `LatexEditSession` | `sd_latex` |
| Buffer vs. overlay repaint split | `gui/PageView.cpp`, `view/Repaintable.h` | `CommittedContentLayer`, `ActiveGestureLayer` | page/canvas widget layer |
| `rerenderRect` coalescing + `RenderJob` | `PageView.cpp:914`, `control/jobs/RenderJob.cpp` | `DirtyRegionAccumulator` | page/canvas widget layer |
