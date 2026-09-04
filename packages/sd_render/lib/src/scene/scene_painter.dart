import 'package:flutter/widgets.dart';

import '../viewport.dart';
import 'scene.dart';
import 'scene_node.dart';

/// Paints the retained scene (§8): the static "what does the document look
/// like" layer. Repaints automatically when [scene] changes (it's a
/// `Listenable`); wrap in a `RepaintBoundary` (see `SigmaCanvas`) so this
/// repaints independently of the selection/ink overlays above it.
class ScenePainter extends CustomPainter {
  ScenePainter({required this.scene, required this.viewport})
    : super(repaint: scene);

  final Scene scene;
  final SigmaViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(viewport.toMatrix4().storage);
    _paintNode(canvas, scene.root);
    canvas.restore();
  }

  void _paintNode(Canvas canvas, SceneNode node) {
    canvas.save();
    canvas.transform(node.transform.storage);

    final fillPath = node.fillPath;
    final fillPaint = node.fillPaint;
    if (fillPath != null && fillPaint != null) {
      canvas.drawPath(fillPath, fillPaint);
    }
    final strokePath = node.strokePath;
    final strokePaint = node.strokePaint;
    if (strokePath != null && strokePaint != null) {
      canvas.drawPath(strokePath, strokePaint);
    }
    final textPainter = node.textPainter;
    final textOrigin = node.textOrigin;
    if (textPainter != null && textOrigin != null) {
      textPainter.paint(canvas, textOrigin);
    }

    for (final child in node.children) {
      _paintNode(canvas, child);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.viewport != viewport;
}
