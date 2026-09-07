import 'package:flutter/material.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_ink/sd_ink.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';

/// Wraps [SigmaCanvas] in a `DragTarget<StencilDefinition>` so dropping a
/// palette item (`StencilPalette`) places a real instance at the drop
/// point — §10's "drag-to-canvas". Exposes the underlying
/// [SigmaCanvasState] (viewport, selection) via [canvasKey] for callers
/// that need it (an inspector/tree wired up alongside this).
class StencilCanvasArea extends StatefulWidget {
  const StencilCanvasArea({
    super.key,
    required this.document,
    this.selection,
    this.canvasKey,
    this.undoStack,
    this.tool = CanvasTool.select,
    this.inkStroke = const InkStroke(),
    this.inkColor = const Color(0xff1a1a1a),
  });

  final SdDocument document;
  final SelectionModel? selection;
  final GlobalKey<SigmaCanvasState>? canvasKey;

  /// Passed straight through to the inner [SigmaCanvas] (so move/scale/
  /// connector edits become undoable) and used to wrap drop-to-place too.
  /// `null` (the default) preserves direct-mutation behavior throughout.
  final UndoStack? undoStack;

  /// Passed straight through to the inner [SigmaCanvas] — see
  /// [CanvasTool].
  final CanvasTool tool;
  final InkStroke inkStroke;
  final Color inkColor;

  @override
  State<StencilCanvasArea> createState() => _StencilCanvasAreaState();
}

class _StencilCanvasAreaState extends State<StencilCanvasArea> {
  late final GlobalKey<SigmaCanvasState> _canvasKey =
      widget.canvasKey ?? GlobalKey<SigmaCanvasState>();

  String _freshInstanceId(String stencilId) {
    final existing = widget.document.root.descendantElements
        .map((e) => e.blockId)
        .whereType<String>()
        .toSet();
    var n = 1;
    while (existing.contains('$stencilId-$n')) {
      n++;
    }
    return '$stencilId-$n';
  }

  void _placeAt(StencilDefinition stencil, Offset globalPosition) {
    final canvasState = _canvasKey.currentState;
    final renderBox = context.findRenderObject();
    if (canvasState == null || renderBox is! RenderBox) return;

    final localPosition = renderBox.globalToLocal(globalPosition);
    final docPoint = canvasState.viewport.screenToDocument(localPosition);
    final instance = stencil.instantiate(
      instanceId: _freshInstanceId(stencil.id),
      x: docPoint.dx - stencil.width / 2,
      y: docPoint.dy - stencil.height / 2,
    );
    final undoStack = widget.undoStack;
    if (undoStack == null) {
      widget.document.root.appendChild(instance);
    } else {
      undoStack.execute(
        InsertChildCommand(
          widget.document.root,
          instance,
          description: 'Place ${stencil.displayName}',
        ),
      );
    }
    canvasState.selection.selectOnly(instance);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<StencilDefinition>(
      onAcceptWithDetails: (details) => _placeAt(details.data, details.offset),
      builder: (context, candidateData, rejectedData) => SigmaCanvas(
        key: _canvasKey,
        document: widget.document,
        selection: widget.selection,
        undoStack: widget.undoStack,
        tool: widget.tool,
        inkStroke: widget.inkStroke,
        inkColor: widget.inkColor,
      ),
    );
  }
}
