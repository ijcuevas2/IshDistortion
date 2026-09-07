import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'viewport.dart';

enum GridStyle { none, dots, lines }

/// Paints the canvas background plus a configurable dot/line grid (§8),
/// spaced in document units and adapted so the *screen-space* gap between
/// lines/dots stays legible regardless of zoom (doubling/halving the
/// document-unit spacing rather than a fixed pixel grid that would either
/// vanish or turn into mush at extreme zoom).
class GridPainter extends CustomPainter {
  const GridPainter({
    required this.viewport,
    this.style = GridStyle.dots,
    this.spacing = 20.0,
    this.color = const Color(0x33808080),
    this.background = const Color(0xFFFFFFFF),
  }) : super(repaint: null);

  final SigmaViewport viewport;
  final GridStyle style;

  /// Base spacing in document units before adaptive doubling/halving.
  final double spacing;
  final Color color;
  final Color background;

  static const double _minScreenSpacing = 8.0;
  static const double _maxScreenSpacing = 160.0;

  double _adaptiveSpacing() {
    var s = spacing;
    while (s * viewport.scale < _minScreenSpacing) {
      s *= 2;
    }
    while (s * viewport.scale > _maxScreenSpacing) {
      s /= 2;
    }
    return s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (style == GridStyle.none) return;

    final s = _adaptiveSpacing();
    final visibleDoc = viewport.screenToDocumentRect(Offset.zero & size);
    final startX = (visibleDoc.left / s).floor() * s;
    final startY = (visibleDoc.top / s).floor() * s;

    if (style == GridStyle.dots) {
      final points = <Offset>[
        for (var gx = startX; gx <= visibleDoc.right; gx += s)
          for (var gy = startY; gy <= visibleDoc.bottom; gy += s)
            viewport.documentToScreen(Offset(gx, gy)),
      ];
      canvas.drawPoints(
        PointMode.points,
        points,
        Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final paint = Paint()..color = color;
    for (var gx = startX; gx <= visibleDoc.right; gx += s) {
      final sx = viewport.documentToScreen(Offset(gx, 0)).dx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), paint);
    }
    for (var gy = startY; gy <= visibleDoc.bottom; gy += s) {
      final sy = viewport.documentToScreen(Offset(0, gy)).dy;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.style != style ||
      oldDelegate.spacing != spacing ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}
