import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';

import 'scene_node.dart';

/// One indexed element: its retained paint node, its accumulated
/// world-space transform (root-to-here, used to map a click point into
/// this node's local space for precise hit-testing), and its own-geometry
/// bounding box already transformed into world/document space.
class SpatialEntry {
  const SpatialEntry({
    required this.node,
    required this.selectableElement,
    required this.parentWorldTransform,
    required this.worldTransform,
    required this.worldBounds,
    required this.paintOrder,
  });

  final SceneNode node;

  /// The element hit-testing should report for this entry — [node.element]
  /// itself, unless this entry lives inside a `<use>` subtree, in which
  /// case it's that `<use>` element (see [SceneNode.isSelectionBoundary]).
  final SdElement selectableElement;

  /// The accumulated world transform *up to but not including* this
  /// node's own [SceneNode.transform] — i.e. what the element's `transform`
  /// attribute is relative to. Needed to correctly rewrite that attribute
  /// when dragging a move/scale handle on an element nested inside one or
  /// more transformed groups (see `sigma_canvas.dart`).
  final Matrix4 parentWorldTransform;

  final Matrix4 worldTransform;
  final Rect worldBounds;

  /// Position in document (paint) order — later entries paint on top.
  final int paintOrder;

  SdElement get element => selectableElement;
}

/// A quadtree over the scene's world-space element bounding boxes: bbox
/// prefiltering for hit-testing and viewport culling (§8).
///
/// Rebuilt from scratch alongside the [SceneNode] tree on every document
/// change (see [Scene]'s doc comment for why that's fine at this phase's
/// target scale) rather than updated incrementally.
class SpatialIndex {
  SpatialIndex._(this._root, this.entries);

  final _QuadNode _root;

  /// Every indexed entry, in paint order.
  final List<SpatialEntry> entries;

  factory SpatialIndex.build(SceneNode sceneRoot) {
    final entries = <SpatialEntry>[];

    void walk(
      SceneNode node,
      Matrix4 parentWorld,
      SdElement? selectableOverride,
    ) {
      final world = parentWorld * node.transform;
      final effectiveOverride = node.isSelectionBoundary
          ? node.element
          : selectableOverride;
      if (node.hasOwnGeometry) {
        entries.add(
          SpatialEntry(
            node: node,
            selectableElement: effectiveOverride ?? node.element,
            parentWorldTransform: parentWorld,
            worldTransform: world,
            worldBounds: MatrixUtils.transformRect(world, node.localBounds),
            paintOrder: entries.length,
          ),
        );
      }
      for (final child in node.children) {
        walk(child, world, effectiveOverride);
      }
    }

    walk(sceneRoot, Matrix4.identity(), null);

    if (entries.isEmpty) {
      return SpatialIndex._(_QuadNode(bounds: Rect.zero, depth: 0), entries);
    }
    var bounds = entries.first.worldBounds;
    for (final entry in entries.skip(1)) {
      bounds = bounds.expandToInclude(entry.worldBounds);
    }
    if (bounds.width == 0 || bounds.height == 0) {
      bounds = bounds.inflate(1);
    }
    final root = _QuadNode(bounds: bounds, depth: 0);
    for (final entry in entries) {
      root.insert(entry);
    }
    return SpatialIndex._(root, entries);
  }

  /// Entries whose world bounding box intersects [area], in paint order.
  /// [area] must have positive width/height — [Rect.overlaps] always
  /// reports no overlap for a zero-size rect, so a point query should pass
  /// e.g. `Rect.fromCircle(center: point, radius: tolerance)`, not a
  /// zero-size rect at the point.
  List<SpatialEntry> query(Rect area) {
    final result = <SpatialEntry>[];
    _root.query(area, result);
    result.sort((a, b) => a.paintOrder.compareTo(b.paintOrder));
    return result;
  }

  /// The world-space bounding box of everything [element] is responsible
  /// for — the union of every entry's `worldBounds` reporting it as their
  /// [SpatialEntry.element] (normally just one, but a `<use>` instance's
  /// bounds are the union of its whole resolved subtree; see
  /// [SceneNode.isSelectionBoundary]). `null` if [element] isn't in the
  /// scene (e.g. it has no direct geometry and isn't a `<use>` instance).
  Rect? worldBoundsFor(SdElement element) {
    Rect? bounds;
    for (final entry in entries) {
      if (entry.element != element) continue;
      bounds = bounds == null
          ? entry.worldBounds
          : bounds.expandToInclude(entry.worldBounds);
    }
    return bounds;
  }
}

class _QuadNode {
  _QuadNode({required this.bounds, required this.depth});

  static const _maxEntriesBeforeSplit = 8;
  static const _maxDepth = 10;

  final Rect bounds;
  final int depth;
  final List<SpatialEntry> _entries = [];
  List<_QuadNode>? _children;

  void insert(SpatialEntry entry) {
    final children = _children;
    if (children != null) {
      final child = _childFor(children, entry.worldBounds);
      if (child != null) {
        child.insert(entry);
      } else {
        _entries.add(entry); // straddles more than one quadrant
      }
      return;
    }
    _entries.add(entry);
    if (_entries.length > _maxEntriesBeforeSplit && depth < _maxDepth) {
      _split();
    }
  }

  void _split() {
    final hw = bounds.width / 2;
    final hh = bounds.height / 2;
    final cx = bounds.left + hw;
    final cy = bounds.top + hh;
    final children = [
      _QuadNode(
        bounds: Rect.fromLTWH(bounds.left, bounds.top, hw, hh),
        depth: depth + 1,
      ),
      _QuadNode(
        bounds: Rect.fromLTWH(cx, bounds.top, hw, hh),
        depth: depth + 1,
      ),
      _QuadNode(
        bounds: Rect.fromLTWH(bounds.left, cy, hw, hh),
        depth: depth + 1,
      ),
      _QuadNode(bounds: Rect.fromLTWH(cx, cy, hw, hh), depth: depth + 1),
    ];
    _children = children;
    final toRedistribute = List.of(_entries);
    _entries.clear();
    for (final entry in toRedistribute) {
      insert(entry);
    }
  }

  _QuadNode? _childFor(List<_QuadNode> children, Rect entryBounds) {
    for (final child in children) {
      if (_rectContains(child.bounds, entryBounds)) return child;
    }
    return null;
  }

  void query(Rect area, List<SpatialEntry> result) {
    if (!bounds.overlaps(area)) return;
    for (final entry in _entries) {
      if (entry.worldBounds.overlaps(area)) result.add(entry);
    }
    final children = _children;
    if (children != null) {
      for (final child in children) {
        child.query(area, result);
      }
    }
  }
}

bool _rectContains(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;
