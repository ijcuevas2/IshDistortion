import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';

/// One retained, paintable node mirroring one [SdElement] (or, for a
/// `<use>` instance, a synthesized wrapper around its resolved target —
/// see `scene_builder.dart`). The whole tree is rebuilt from the document
/// on every change rather than incrementally patched — see the [Scene]
/// class doc for why that's an acceptable simplification at this phase.
class SceneNode {
  const SceneNode({
    required this.element,
    required this.transform,
    this.fillPath,
    this.fillPaint,
    this.strokePath,
    this.strokePaint,
    this.textPainter,
    this.textOrigin,
    required this.localBounds,
    required this.children,
    this.isSelectionBoundary = false,
  });

  /// The element this node renders. For a `<use>` wrapper, this is the
  /// `<use>` element itself (not its target) — see [SpatialIndex], which
  /// keys entries by element and needs this to point at what a hit-test
  /// should report as "clicked".
  final SdElement element;

  /// This node's own local transform (its `transform` attribute, composed
  /// with any `<use>` x/y and `viewBox`-fit offset — identity if none).
  /// Applied via `Canvas.save()`/`.transform()`/`.restore()` around this
  /// node's own geometry *and* its children when painting.
  final Matrix4 transform;

  final Path? fillPath;
  final Paint? fillPaint;
  final Path? strokePath;
  final Paint? strokePaint;

  final TextPainter? textPainter;
  final Offset? textOrigin;

  /// This node's own geometry bounds (fill/stroke/text), in its local
  /// coordinate space — i.e. *before* [transform] is applied. Does not
  /// include children; `SpatialIndex` unions those in separately while
  /// walking with accumulated world transforms.
  final Rect localBounds;

  final List<SceneNode> children;

  /// True for a `<use>` wrapper node: tells [SpatialIndex] that hit-testing
  /// anywhere in this subtree should report *this* node's [element] (the
  /// `<use>`) rather than whatever element deep inside the resolved target
  /// actually owns the geometry that was clicked. Without this, clicking a
  /// rendered symbol instance would select a node living in `<defs>` —
  /// editing which would silently edit every instance of that symbol at
  /// once, rather than selecting the instance itself.
  final bool isSelectionBoundary;

  bool get hasOwnGeometry =>
      fillPath != null || strokePath != null || textPainter != null;
}
