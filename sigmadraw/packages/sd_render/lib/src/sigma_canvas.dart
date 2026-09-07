import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_ink/sd_ink.dart';
import 'package:sd_input/sd_input.dart';

import 'geometry/svg_transform.dart';
import 'grid_painter.dart';
import 'ink_preview_painter.dart';
import 'scene/hit_test.dart';
import 'scene/port_handles.dart';
import 'scene/scene.dart';
import 'scene/scene_painter.dart';
import 'selection/handles.dart';
import 'selection/selection_model.dart';
import 'selection/selection_overlay_painter.dart';
import 'viewport.dart';

/// Document-unit tolerance (before dividing by zoom) for starting/ending a
/// connector drag on a port dot.
const double kPortHitTolerance = 8;

/// Which gesture a pointer-down starts (§10: a real tool selector — a
/// ribbon Home-tab button group — is Phase 5's job; this is the minimal
/// two-value precursor that makes the ink tool possible before that
/// exists). [select] is this widget's original behavior in full (click/
/// marquee-select, move/scale drag handles, drag-to-connect); [ink] makes
/// every pointer gesture draw an ink stroke instead (§6/§7), regardless
/// of what's under the pointer.
enum CanvasTool { select, ink }

/// The composed, interactive infinite canvas (§8/§9): pan/zoom/grid, the
/// retained scene, click/marquee selection, and move + uniform-corner-scale
/// via drag handles.
///
/// Uses `Listener`, not `GestureDetector` (§7), so its own multi-modal
/// drag handling (pan vs. marquee vs. move vs. scale, decided at
/// pointer-down by what's under the cursor) doesn't have to contend with
/// the gesture arena — and so the eventual ink tool (Phase 6) can share
/// this same pointer-routing style.
///
/// Dragging from one port dot to another creates a real `sd:edge` (§9:
/// "connectors attach to typed ports") as a straight line — orthogonal
/// routing (a pure-Dart port of libavoid's algorithm), snapping, and edge
/// dtype validation feedback are Phase 9's job, not this one's.
///
/// Not implemented yet (later phases — see §9, §12): rotate/flip handles,
/// snapping, shift-click multi-select, keyboard nudge.
class SigmaCanvas extends StatefulWidget {
  const SigmaCanvas({
    super.key,
    required this.document,
    this.gridStyle = GridStyle.dots,
    this.selection,
    this.undoStack,
    this.tool = CanvasTool.select,
    this.inkStroke = const InkStroke(),
    this.inkColor = const Color(0xff1a1a1a),
  });

  final SdDocument document;
  final GridStyle gridStyle;

  /// Which gesture a pointer-down starts — see [CanvasTool].
  final CanvasTool tool;

  /// The pipeline (pressure curve, smoothing/simplification/fit settings)
  /// [tool] `ink` commits a finished stroke through.
  final InkStroke inkStroke;

  /// Fill color for a newly-drawn ink stroke's outline (and its live
  /// preview) — a single global color, not per-stroke color selection
  /// (§10's ribbon color picker isn't built).
  final Color inkColor;

  /// Share selection state with e.g. an inspector panel by providing one;
  /// otherwise the canvas creates and owns its own.
  final SelectionModel? selection;

  /// Routes every document mutation this canvas makes (move/scale drags,
  /// connector creation) through this stack instead of mutating directly,
  /// so they become undoable — share one with e.g. an inspector panel the
  /// same way as [selection]. `null` (the default) preserves this widget's
  /// original direct-mutation behavior with no undo tracking at all.
  ///
  /// A move or scale drag opens one transaction at pointer-down and
  /// commits it at pointer-up, so however many intermediate per-frame
  /// edits a drag makes collapse into the single undo step a user actually
  /// expects "Undo" to reverse (see [UndoStack]'s own doc comment).
  final UndoStack? undoStack;

  @override
  State<SigmaCanvas> createState() => SigmaCanvasState();
}

enum _DragMode { none, pan, marquee, move, scale, connect, ink }

class SigmaCanvasState extends State<SigmaCanvas> {
  late final Scene scene;
  late final SelectionModel selection;
  bool _ownsSelection = false;

  SigmaViewport viewport = const SigmaViewport();

  _DragMode _dragMode = _DragMode.none;

  /// The `PointerEvent.pointer` id driving the current [_dragMode], or
  /// `null` when none is active. This canvas's drag state (move/scale/
  /// marquee/connect/ink) is a single global state machine, not one per
  /// simultaneous pointer — realistic for a desktop-first app where only
  /// one hand drags at a time, but a second pointer arriving mid-drag
  /// (a stylus writing while the other hand's palm also touches down) is
  /// a real scenario once ink is involved. Every handler below ignores
  /// any event whose `pointer` doesn't match this, so a second pointer
  /// can never clobber the first's in-progress `_dragMode`/`_inkPoints`/
  /// etc. — see the palm-rejection tests in `ink_tool_test.dart` for the
  /// bug this fixes. This does *not* make simultaneous multi-pointer
  /// drags work correctly in general — it only prevents a second,
  /// ignored pointer from corrupting the first's state — and it resolves
  /// ties by whichever pointer went down *first*, so a stylus that goes
  /// down *after* an already-dragging touch is itself ignored rather
  /// than preempting it, unlike the reverse order (§7 palm rejection, as
  /// implemented, only correctly covers "stylus first, then palm").
  int? _dragPointer;
  Offset _dragStartScreen = Offset.zero;
  Offset _lastScreen = Offset.zero;
  Rect? _marqueeScreen;
  HandleKind? _activeHandle;
  Rect? _scaleAnchorDocBounds;
  final Map<SdElement, Matrix4> _dragStartLocalTransforms = {};
  PortHandle? _connectStart;
  Offset? _connectCurrentScreen;
  final List<StrokePoint> _inkPoints = [];

  /// §7's palm-rejection state — fed every pointer event this canvas sees
  /// (down/move/up/cancel/hover), regardless of tool or drag mode, so it
  /// stays accurate even while, say, the select tool is active.
  final PalmRejectionFilter _palmRejection = PalmRejectionFilter();

  @override
  void initState() {
    super.initState();
    scene = Scene(widget.document);
    final providedSelection = widget.selection;
    if (providedSelection != null) {
      selection = providedSelection;
    } else {
      selection = SelectionModel();
      _ownsSelection = true;
    }
    selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    selection.removeListener(_onSelectionChanged);
    if (_ownsSelection) selection.dispose();
    scene.dispose();
    super.dispose();
  }

  void _onSelectionChanged() => setState(() {});

  /// Frames [viewport] to show the whole document, with a margin.
  void fitToContent(Size viewportSize) {
    final entries = scene.spatialIndex.entries;
    if (entries.isEmpty) return;
    var bounds = entries.first.worldBounds;
    for (final entry in entries.skip(1)) {
      bounds = bounds.expandToInclude(entry.worldBounds);
    }
    setState(() => viewport = SigmaViewport.fitting(bounds, viewportSize));
  }

  /// [fitToContent], using this canvas's own current on-screen size — the
  /// no-argument convenience a toolbar/ribbon "Zoom to Fit" button needs,
  /// since it has no `Size` of its own to pass in.
  void fitToContentAuto() {
    // context.size (not context.findRenderObject()'s size — found by a
    // real test to disagree with it here, returning the whole test
    // surface's size instead of this canvas's own constrained size) is
    // the documented, correct way to ask a BuildContext "what's my own
    // current on-screen size", valid any time after the first layout.
    final size = context.size;
    if (size != null) fitToContent(size);
  }

  /// Zooms by [factor] (`>1` zooms in, `<1` zooms out) about this canvas's
  /// own on-screen center — for a toolbar/ribbon zoom button, which
  /// (unlike scroll-wheel zoom, see [_onPointerSignal]) has no pointer
  /// position of its own to anchor to.
  void zoomByFactor(double factor) {
    final size = context.size;
    final center = size == null
        ? Offset.zero
        : Offset(size.width / 2, size.height / 2);
    setState(() => viewport = viewport.zoomBy(factor, center));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      onPointerSignal: _onPointerSignal,
      // Proximity (§7): a stylus hovering, not yet down, still counts as
      // "active" for palm rejection — this is the only handler that
      // exists purely to feed _palmRejection; it drives no drag mode.
      onPointerHover: _palmRejection.onPointerEvent,
      child: SizedBox.expand(
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: GridPainter(
                  viewport: viewport,
                  style: widget.gridStyle,
                ),
                size: Size.infinite,
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: ScenePainter(scene: scene, viewport: viewport),
                size: Size.infinite,
              ),
            ),
            CustomPaint(
              painter: SelectionOverlayPainter(
                selection: selection,
                spatialIndex: scene.spatialIndex,
                viewport: viewport,
                marquee: _marqueeScreen,
                portHandles: collectPortHandles(widget.document),
                connectStart: _connectStart,
                connectCurrentScreen: _connectCurrentScreen,
              ),
              size: Size.infinite,
            ),
            if (_dragMode == _DragMode.ink)
              CustomPaint(
                painter: InkPreviewPainter(
                  points: _inkPoints,
                  viewport: viewport,
                  color: widget.inkColor,
                  nominalWidth: widget.inkStroke.nominalWidth,
                ),
                size: Size.infinite,
              ),
          ],
        ),
      ),
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final zoomModifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    setState(() {
      if (zoomModifier) {
        final factor = math.exp(-event.scrollDelta.dy / 200);
        viewport = viewport.zoomBy(factor, event.localPosition);
      } else {
        viewport = viewport.panBy(-event.scrollDelta);
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _palmRejection.onPointerEvent(event);
    if (_dragPointer != null && _dragPointer != event.pointer) {
      return; // a different pointer already owns the active gesture.
    }
    _dragPointer = event.pointer;
    _dragStartScreen = event.localPosition;
    _lastScreen = event.localPosition;

    if (event.buttons & kMiddleMouseButton != 0) {
      _dragMode = _DragMode.pan;
      return;
    }
    if (event.buttons & kPrimaryButton == 0) {
      _dragMode = _DragMode.none;
      return;
    }

    if (widget.tool == CanvasTool.ink) {
      if (!_palmRejection.shouldInk(event.kind)) {
        // Palm rejection (§7): a touch while a stylus is active pans
        // instead of inking, rather than being silently swallowed. Only
        // reachable while the stylus is merely *hovering* (not yet its
        // own `_dragPointer`) — once it's actually down and dragging,
        // the reentrancy guard above already returned before this line,
        // so a touch arriving *then* is ignored outright rather than
        // panning (seeing this pointer's later move/up events at all
        // would require tracking it independently of the stylus's own
        // drag, which nothing here does — see `_dragPointer`'s doc
        // comment).
        _dragMode = _DragMode.pan;
        return;
      }
      final sample = _sampleFrom(event);
      if (!hasInkablePressure(sample.pressure)) {
        // Xournal++'s defensive rule (§7): never trust the input system —
        // a reported-zero pressure (e.g. a mis-flagged hover) never
        // starts a stroke.
        _dragMode = _DragMode.none;
        return;
      }
      _dragMode = _DragMode.ink;
      _inkPoints.clear();
      setState(() => _inkPoints.add(sample));
      return;
    }

    final docPointForPorts = viewport.screenToDocument(event.localPosition);
    final startPort = nearestPortHandle(
      collectPortHandles(widget.document),
      docPointForPorts,
      kPortHitTolerance / viewport.scale,
    );
    if (startPort != null) {
      _dragMode = _DragMode.connect;
      _connectStart = startPort;
      setState(() => _connectCurrentScreen = event.localPosition);
      return;
    }

    if (!selection.isEmpty) {
      final unionDoc = _unionSelectionBounds();
      if (unionDoc != null) {
        final handle = hitTestHandle(
          viewport.documentToScreenRect(unionDoc),
          event.localPosition,
        );
        if (handle != null) {
          _dragMode = _DragMode.scale;
          widget.undoStack?.beginTransaction();
          _activeHandle = handle;
          _scaleAnchorDocBounds = unionDoc;
          _dragStartLocalTransforms
            ..clear()
            ..addEntries(
              selection.selected.map(
                (e) => MapEntry(e, currentLocalTransform(e)),
              ),
            );
          return;
        }
      }
    }

    final docPoint = viewport.screenToDocument(event.localPosition);
    final hit = hitTestPoint(
      scene.spatialIndex,
      docPoint,
      tolerance: kDefaultHitTolerance / viewport.scale,
    );
    if (hit != null) {
      if (!selection.isSelected(hit)) selection.selectOnly(hit);
      _dragMode = _DragMode.move;
      widget.undoStack?.beginTransaction();
      return;
    }

    selection.clear();
    _dragMode = _DragMode.marquee;
    setState(
      () => _marqueeScreen = Rect.fromPoints(
        event.localPosition,
        event.localPosition,
      ),
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    _palmRejection.onPointerEvent(event);
    if (_dragPointer != null && event.pointer != _dragPointer) return;
    final screenDelta = event.localPosition - _lastScreen;
    _lastScreen = event.localPosition;

    switch (_dragMode) {
      case _DragMode.none:
        return;
      case _DragMode.pan:
        setState(() => viewport = viewport.panBy(screenDelta));
      case _DragMode.marquee:
        setState(
          () => _marqueeScreen = Rect.fromPoints(
            _dragStartScreen,
            event.localPosition,
          ),
        );
      case _DragMode.move:
        final docDelta = screenDelta / viewport.scale;
        final worldDelta = Matrix4.translationValues(
          docDelta.dx,
          docDelta.dy,
          0,
        );
        final undoStack = widget.undoStack;
        for (final element in selection.selected) {
          if (undoStack == null) {
            applyWorldDelta(element, worldDelta);
            continue;
          }
          final newValue = computeWorldDeltaTransform(element, worldDelta);
          if (newValue == null) continue;
          undoStack.execute(
            SetAttributeCommand(
              element,
              const SdQName('transform'),
              newValue,
              description: 'Move',
            ),
          );
        }
      case _DragMode.scale:
        _applyScaleDrag(event.localPosition);
      case _DragMode.connect:
        setState(() => _connectCurrentScreen = event.localPosition);
      case _DragMode.ink:
        setState(() => _inkPoints.add(_sampleFrom(event)));
    }
  }

  /// Converts a raw pointer event into a document-space [StrokePoint]
  /// (§6/§7), using `sd_input`'s [classifyDevice] to decide whether to
  /// trust its pressure at all: a mouse or touch pointer reports a
  /// constant, meaningless `1.0` for [PointerEvent.pressure] rather than
  /// genuinely having none, so passing that straight through would defeat
  /// [InkStroke]'s own speed-based pressure *inference* for exactly the
  /// pressureless devices that fallback exists for — `null` here is what
  /// tells it "this sample has no real pressure, infer one". Palm
  /// rejection and the "only ink on positive pressure" rule are applied
  /// at the call site (see [_onPointerDown]'s ink-tool branch), not here
  /// — this just does the unit conversion.
  StrokePoint _sampleFrom(PointerEvent event) {
    final role = classifyDevice(event);
    final hasRealPressure =
        role == DeviceRole.pen || role == DeviceRole.penEraser;
    final docPoint = viewport.screenToDocument(event.localPosition);
    return StrokePoint(
      x: docPoint.dx,
      y: docPoint.dy,
      pressure: hasRealPressure ? event.pressure : null,
      timestamp: event.timeStamp,
    );
  }

  void _onPointerUp(PointerEvent event) {
    _palmRejection.onPointerEvent(event);
    if (_dragPointer != null && event.pointer != _dragPointer) return;
    if (_dragMode == _DragMode.marquee && _marqueeScreen != null) {
      final hits = hitTestRect(
        scene.spatialIndex,
        viewport.screenToDocumentRect(_marqueeScreen!),
      );
      if (hits.isNotEmpty) selection.selectAll(hits);
    }
    if (_dragMode == _DragMode.connect && _connectStart != null) {
      _finishConnector(event.localPosition);
    }
    if (_dragMode == _DragMode.move) {
      widget.undoStack?.commitTransaction(description: 'Move');
    } else if (_dragMode == _DragMode.scale) {
      widget.undoStack?.commitTransaction(description: 'Resize');
    } else if (_dragMode == _DragMode.ink) {
      _finishInkStroke();
    }
    setState(() {
      _marqueeScreen = null;
      _connectStart = null;
      _connectCurrentScreen = null;
      _inkPoints.clear();
    });
    _dragMode = _DragMode.none;
    _dragPointer = null;
    _activeHandle = null;
    _scaleAnchorDocBounds = null;
    _dragStartLocalTransforms.clear();
  }

  /// Completes a connector drag if [screenPosition] lands on a port that
  /// pairs validly with [_connectStart] — one output, one input, on
  /// different blocks — creating a real `sd:edge` (§9: "connectors attach
  /// to typed ports"). Routing is a straight line for now; orthogonal
  /// routing is Phase 9's `libavoid`-inspired router.
  void _finishConnector(Offset screenPosition) {
    final start = _connectStart!;
    final docPoint = viewport.screenToDocument(screenPosition);
    final end = nearestPortHandle(
      collectPortHandles(widget.document),
      docPoint,
      kPortHitTolerance / viewport.scale,
    );
    if (end == null || identical(end.element, start.element)) return;

    final PortHandle output;
    final PortHandle input;
    if (start.isOutput && !end.isOutput) {
      output = start;
      input = end;
    } else if (!start.isOutput && end.isOutput) {
      output = end;
      input = start;
    } else {
      return; // output-to-output or input-to-input: not a valid connection.
    }
    final fromId = output.element.blockId;
    final toId = input.element.blockId;
    if (fromId == null || toId == null) return;

    final edgeElement =
        SdElement(
            const SdQName('path'),
            attributes: {
              const SdQName('d'):
                  'M${output.position.dx},${output.position.dy} '
                  'L${input.position.dx},${input.position.dy}',
              const SdQName('stroke'): '#1a1a1a',
              const SdQName('stroke-width'): '2',
              const SdQName('fill'): 'none',
              const SdQName('vector-effect'): 'non-scaling-stroke',
            },
          )
          ..edgeId = _freshEdgeId()
          ..edgeFrom = '$fromId:${output.portId}'
          ..edgeTo = '$toId:${input.portId}';
    final undoStack = widget.undoStack;
    if (undoStack == null) {
      widget.document.root.appendChild(edgeElement);
    } else {
      undoStack.execute(
        InsertChildCommand(
          widget.document.root,
          edgeElement,
          description: 'Create connector',
        ),
      );
    }
  }

  String _freshEdgeId() {
    final existing = widget.document.root.descendantElements
        .map((e) => e.edgeId)
        .whereType<String>()
        .toSet();
    var n = 1;
    while (existing.contains('e$n')) {
      n++;
    }
    return 'e$n';
  }

  /// Runs the accumulated `_inkPoints` through [widget.inkStroke]'s full
  /// pipeline and commits the resulting filled-outline `<path>` (§6) — the
  /// one point at which that whole pipeline runs, not per pointer-move
  /// (see `InkPreviewPainter`'s doc comment for why).
  void _finishInkStroke() {
    final element = widget.inkStroke.build(
      _inkPoints,
      strokeId: _freshStrokeId(),
      color: _colorToCss(widget.inkColor),
    );
    if (element == null) return;
    final undoStack = widget.undoStack;
    if (undoStack == null) {
      widget.document.root.appendChild(element);
    } else {
      undoStack.execute(
        InsertChildCommand(
          widget.document.root,
          element,
          description: 'Draw stroke',
        ),
      );
    }
  }

  String _freshStrokeId() {
    final existing = widget.document.root.descendantElements
        .map((e) => e.strokeId)
        .whereType<String>()
        .toSet();
    var n = 1;
    while (existing.contains('ink$n')) {
      n++;
    }
    return 'ink$n';
  }

  Rect? _unionSelectionBounds() {
    Rect? union;
    for (final element in selection.selected) {
      final bounds = scene.spatialIndex.worldBoundsFor(element);
      if (bounds == null) continue;
      union = union == null ? bounds : union.expandToInclude(bounds);
    }
    return union;
  }

  /// Recomputes the *total* scale from the drag's start (rather than
  /// composing many small incremental scales) so the anchor point can't
  /// drift over a long drag and floating-point error can't compound.
  void _applyScaleDrag(Offset currentScreen) {
    final handle = _activeHandle;
    final startBounds = _scaleAnchorDocBounds;
    if (handle == null || startBounds == null) return;

    final anchor = anchorFor(handle, startBounds);
    final originalHandlePos = handlePositions(startBounds)[handle]!;
    final dragPointDoc = viewport.screenToDocument(currentScreen);
    final (affectsWidth, affectsHeight) = handleAxes(handle);

    double axisScale(
      double dragCoord,
      double originalCoord,
      double anchorCoord,
      bool affects,
    ) {
      if (!affects) return 1.0;
      final denom = originalCoord - anchorCoord;
      if (denom.abs() < 1e-6) return 1.0;
      return (dragCoord - anchorCoord) / denom;
    }

    final scaleX = axisScale(
      dragPointDoc.dx,
      originalHandlePos.dx,
      anchor.dx,
      affectsWidth,
    );
    final scaleY = axisScale(
      dragPointDoc.dy,
      originalHandlePos.dy,
      anchor.dy,
      affectsHeight,
    );

    final worldDelta = Matrix4.translationValues(anchor.dx, anchor.dy, 0)
      ..scaleByDouble(scaleX, scaleY, 1.0, 1.0)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0.0, 1.0);

    final undoStack = widget.undoStack;
    for (final element in selection.selected) {
      final originalLocal = _dragStartLocalTransforms[element];
      if (originalLocal == null) continue;
      final parentWorld = parentWorldTransformOf(element);
      final parentInverse = Matrix4.tryInvert(parentWorld);
      if (parentInverse == null) continue;
      final newLocal = parentInverse * worldDelta * parentWorld * originalLocal;
      final newValue = matrixToSvgTransform(newLocal);
      if (undoStack == null) {
        element.setAttribute(const SdQName('transform'), newValue);
      } else {
        undoStack.execute(
          SetAttributeCommand(
            element,
            const SdQName('transform'),
            newValue,
            description: 'Resize',
          ),
        );
      }
    }
  }
}

/// Formats [color] as a CSS hex color (`#rrggbb`, or `#rrggbbaa` if it has
/// any transparency) for an SVG `fill`/`stroke` attribute — the inverse of
/// `parseSvgColor` (`svg_paint.dart`), which nothing needed until an ink
/// stroke's color became caller-configurable rather than always a
/// hard-coded literal string.
String _colorToCss(Color color) {
  String channel(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0');
  final hex = '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
  return color.a >= 1.0 ? hex : '$hex${channel(color.a)}';
}
