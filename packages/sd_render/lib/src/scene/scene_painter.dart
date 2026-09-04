import 'package:flutter/widgets.dart';

import '../viewport.dart';
import 'scene.dart';
import 'scene_node.dart';

/// Paints [node] and every descendant onto [canvas], applying each node's
/// own local transform as it recurses — the actual "draw this retained
/// scene tree" logic [ScenePainter] uses for its live, on-screen
/// `CustomPainter` repaints, factored out so a one-shot *offscreen* render
/// (§11's raster export, `sd_export`'s `exportToPng`) can reuse the exact
/// same drawing code against a plain [Canvas]/`PictureRecorder` instead of
/// a widget-tree `CustomPainter`.
void paintSceneNode(Canvas canvas, SceneNode node) {
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
    paintSceneNode(canvas, child);
  }
  canvas.restore();
}

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
    paintSceneNode(canvas, scene.root);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.viewport != viewport;
}
