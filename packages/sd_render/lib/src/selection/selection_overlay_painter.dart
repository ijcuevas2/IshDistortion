import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../scene/port_handles.dart';
import '../scene/spatial_index.dart';
import '../viewport.dart';
import 'handles.dart';
import 'selection_model.dart';

/// Paints the selection outline + resize handles, port dots, and an
/// in-progress marquee-select or connector-drag, in their own layer above
/// the static scene (§8: "selection/handles overlay"; §9: "connectors
/// attach to typed ports").
class SelectionOverlayPainter extends CustomPainter {
  SelectionOverlayPainter({
    required this.selection,
    required this.spatialIndex,
    required this.viewport,
    this.marquee,
    this.portHandles = const [],
    this.connectStart,
    this.connectCurrentScreen,
  }) : super(repaint: selection);

  final SelectionModel selection;
  final SpatialIndex spatialIndex;
  final SigmaViewport viewport;

  /// The marquee (rubber-band) rectangle being dragged, in screen space, or
  /// `null` if none is in progress.
  final Rect? marquee;

  /// Every port on the document, so a small dot shows where a connector
  /// can be started/ended.
  final List<PortHandle> portHandles;

  /// The port a connector drag started from, and the drag's current
  /// screen position — both `null` when no connector is being drawn.
  final PortHandle? connectStart;
  final Offset? connectCurrentScreen;

  static const _accent = Color(0xFF2F6FED);
  static const _portColor = Color(0xFF9AA5B1);

  @override
  void paint(Canvas canvas, Size size) {
    if (portHandles.isNotEmpty) {
      final points = [
        for (final h in portHandles) viewport.documentToScreen(h.position),
      ];
      canvas.drawPoints(
        PointMode.points,
        points,
        Paint()
          ..color = _portColor
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }

    final start = connectStart;
    final end = connectCurrentScreen;
    if (start != null && end != null) {
      canvas.drawLine(
        viewport.documentToScreen(start.position),
        end,
        Paint()
          ..color = _accent
          ..strokeWidth = 2,
      );
    }

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
      oldDelegate.marquee != marquee ||
      oldDelegate.portHandles != portHandles ||
      oldDelegate.connectStart != connectStart ||
      oldDelegate.connectCurrentScreen != connectCurrentScreen;
}
