import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';

import 'geometry/svg_transform.dart';
import 'grid_painter.dart';
import 'scene/hit_test.dart';
import 'scene/scene.dart';
import 'scene/scene_painter.dart';
import 'selection/handles.dart';
import 'selection/selection_model.dart';
import 'selection/selection_overlay_painter.dart';
import 'viewport.dart';

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
/// Not implemented yet (later phases — see §9, §12): rotate/flip handles,
/// snapping, connector routing, shift-click multi-select, keyboard nudge.
class SigmaCanvas extends StatefulWidget {
  const SigmaCanvas({
    super.key,
    required this.document,
    this.gridStyle = GridStyle.dots,
    this.selection,
  });

  final SdDocument document;
  final GridStyle gridStyle;

  /// Share selection state with e.g. an inspector panel by providing one;
  /// otherwise the canvas creates and owns its own.
  final SelectionModel? selection;

  @override
  State<SigmaCanvas> createState() => SigmaCanvasState();
}

enum _DragMode { none, pan, marquee, move, scale }

class SigmaCanvasState extends State<SigmaCanvas> {
  late final Scene scene;
  late final SelectionModel selection;
  bool _ownsSelection = false;

  SigmaViewport viewport = const SigmaViewport();

  _DragMode _dragMode = _DragMode.none;
  Offset _dragStartScreen = Offset.zero;
  Offset _lastScreen = Offset.zero;
  Rect? _marqueeScreen;
  HandleKind? _activeHandle;
  Rect? _scaleAnchorDocBounds;
  final Map<SdElement, Matrix4> _dragStartLocalTransforms = {};

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

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      onPointerSignal: _onPointerSignal,
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

    if (!selection.isEmpty) {
      final unionDoc = _unionSelectionBounds();
      if (unionDoc != null) {
        final handle = hitTestHandle(
          viewport.documentToScreenRect(unionDoc),
          event.localPosition,
        );
        if (handle != null) {
          _dragMode = _DragMode.scale;
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
        for (final element in selection.selected) {
          applyWorldDelta(element, worldDelta);
        }
      case _DragMode.scale:
        _applyScaleDrag(event.localPosition);
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_dragMode == _DragMode.marquee && _marqueeScreen != null) {
      final hits = hitTestRect(
        scene.spatialIndex,
        viewport.screenToDocumentRect(_marqueeScreen!),
      );
      if (hits.isNotEmpty) selection.selectAll(hits);
      setState(() => _marqueeScreen = null);
    }
    _dragMode = _DragMode.none;
    _activeHandle = null;
    _scaleAnchorDocBounds = null;
    _dragStartLocalTransforms.clear();
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

    for (final element in selection.selected) {
      final originalLocal = _dragStartLocalTransforms[element];
      if (originalLocal == null) continue;
      final parentWorld = parentWorldTransformOf(element);
      final parentInverse = Matrix4.tryInvert(parentWorld);
      if (parentInverse == null) continue;
      final newLocal = parentInverse * worldDelta * parentWorld * originalLocal;
      element.setAttribute(
        const SdQName('transform'),
        matrixToSvgTransform(newLocal),
      );
    }
  }
}
