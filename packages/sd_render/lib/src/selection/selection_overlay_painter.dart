import 'package:flutter/widgets.dart';

import '../scene/spatial_index.dart';
import '../viewport.dart';
import 'handles.dart';
import 'selection_model.dart';

/// Paints the selection outline + resize handles, and an in-progress
/// marquee rectangle, in their own layer above the static scene (§8:
/// "selection/handles overlay").
class SelectionOverlayPainter extends CustomPainter {
  SelectionOverlayPainter({
    required this.selection,
    required this.spatialIndex,
    required this.viewport,
    this.marquee,
  }) : super(repaint: selection);

  final SelectionModel selection;
  final SpatialIndex spatialIndex;
  final SigmaViewport viewport;

  /// The marquee (rubber-band) rectangle being dragged, in screen space, or
  /// `null` if none is in progress.
  final Rect? marquee;

  static const _accent = Color(0xFF2F6FED);

  @override
  void paint(Canvas canvas, Size size) {
    final marqueeRect = marquee;
    if (marqueeRect != null) {
      canvas.drawRect(
        marqueeRect,
        Paint()..color = _accent.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        marqueeRect,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    if (selection.isEmpty) return;

    Rect? unionDoc;
    for (final element in selection.selected) {
      final bounds = spatialIndex.worldBoundsFor(element);
      if (bounds == null) continue;
      unionDoc = unionDoc == null ? bounds : unionDoc.expandToInclude(bounds);
    }
    if (unionDoc == null) return;

    final screenBounds = viewport.documentToScreenRect(unionDoc);
    canvas.drawRect(
      screenBounds,
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const handleSize = 8.0;
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    final stroke = Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final position in handlePositions(screenBounds).values) {
      final r = Rect.fromCenter(
        center: position,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant SelectionOverlayPainter oldDelegate) =>
      oldDelegate.selection != selection ||
      oldDelegate.spatialIndex != spatialIndex ||
      oldDelegate.viewport != viewport ||
      oldDelegate.marquee != marquee;
}
