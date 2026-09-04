import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';

import '../geometry/svg_paint.dart';
import '../geometry/svg_shapes.dart';
import '../geometry/svg_transform.dart';
import 'scene_node.dart';

/// SVG-namespace elements that are non-rendering containers *in place* —
/// they only ever render when explicitly instantiated via `<use>` (`defs`,
/// `symbol`), referenced from a paint property (`marker`, `clipPath`,
/// `mask`, `pattern` — none of which are applied yet; see the class doc
/// below), or aren't visual content at all (`style`, `script`, `title`,
/// `desc`, `metadata`).
const _nonRenderingContainers = {
  'defs',
  'symbol',
  'marker',
  'clipPath',
  'mask',
  'pattern',
  'style',
  'script',
  'title',
  'desc',
  'metadata',
};

/// Builds the retained [SceneNode] tree for [document].
///
/// Known Phase 2 scope cuts (all namespace/element-driven, so gracefully
/// forward-compatible — nothing crashes, the content is just not yet
/// painted): `marker-start`/`marker-end` arrowheads are not instantiated;
/// `clipPath`/`mask`/`pattern`/gradients are not applied; `<tspan>`
/// sub-styling inside `<text>` is flattened to one run. All revisited in
/// Phase 7 (full stencil set, which needs arrowheads) or Phase 10 (export
/// fidelity).
SceneNode buildScene(SdDocument document) {
  final ids = <String, SdElement>{
    for (final e in document.root.descendantElements)
      // ignore: use_null_aware_elements (nullable *key*, not value)
      if (e.getAttribute(const SdQName('id')) case final id?) id: e,
  };
  return _build(
        document.root,
        SvgPaintState.initial,
        ids,
        const {},
        isUseTarget: false,
      ) ??
      SceneNode(
        element: document.root,
        transform: Matrix4.identity(),
        localBounds: Rect.zero,
        children: const [],
      );
}

SceneNode? _build(
  SdElement element,
  SvgPaintState inherited,
  Map<String, SdElement> ids,
  Set<String> resolvingUseIds, {
  required bool isUseTarget,
}) {
  // Foreign (non-SVG-namespace) content — including our own `sd:` payload
  // when it isn't riding along on a real SVG element — is metadata, not
  // renderable geometry: skip it and its subtree entirely, same as any
  // real SVG viewer would for a namespace it doesn't recognize.
  if (element.name.namespaceUri != SdNamespace.svg) return null;

  final local = element.name.local;
  final state = inherited.resolve(element);
  final transformAttr = element.getAttribute(const SdQName('transform'));
  final transform = transformAttr == null
      ? Matrix4.identity()
      : parseSvgTransform(transformAttr);

  if (local == 'use') {
    return _buildUse(element, state, transform, ids, resolvingUseIds);
  }

  if (_nonRenderingContainers.contains(local) && !isUseTarget) {
    return SceneNode(
      element: element,
      transform: transform,
      localBounds: Rect.zero,
      children: const [],
    );
  }

  if (local == 'text') {
    return _buildText(element, state, transform, ids, resolvingUseIds);
  }

  final path = svgShapeToPath(element);
  final children = <SceneNode>[
    for (final child in element.childElements)
      ?_build(child, state, ids, resolvingUseIds, isUseTarget: false),
  ];

  if (path == null) {
    // A generic container (`g`, nested `svg`, `a`, an unrecognized-but-SVG
    // tag, or a `defs`/`symbol` being built *as a use target*): no
    // geometry of its own, just its children.
    return SceneNode(
      element: element,
      transform: transform,
      localBounds: Rect.zero,
      children: children,
    );
  }

  final fillPaint = state.fillPaint;
  final strokePaint = state.strokePaint;
  return SceneNode(
    element: element,
    transform: transform,
    fillPath: fillPaint == null ? null : path,
    fillPaint: fillPaint,
    strokePath: strokePaint == null ? null : path,
    strokePaint: strokePaint,
    localBounds: path.getBounds(),
    children: children,
  );
}

double? _num(SdElement e, String name) {
  final raw = e.getAttribute(SdQName(name));
  return raw == null ? null : double.tryParse(raw.trim());
}

SceneNode? _buildUse(
  SdElement element,
  SvgPaintState state,
  Matrix4 ownTransform,
  Map<String, SdElement> ids,
  Set<String> resolvingUseIds,
) {
  final href =
      element.getAttribute(const SdQName('href', SdNamespace.xlink)) ??
      element.getAttribute(const SdQName('href'));
  if (href == null || !href.startsWith('#')) {
    return SceneNode(
      element: element,
      transform: ownTransform,
      localBounds: Rect.zero,
      children: const [],
    );
  }
  final targetId = href.substring(1);
  if (resolvingUseIds.contains(targetId)) {
    return SceneNode(
      element: element,
      transform: ownTransform,
      localBounds: Rect.zero,
      children: const [],
    );
  }
  final target = ids[targetId];
  if (target == null) {
    return SceneNode(
      element: element,
      transform: ownTransform,
      localBounds: Rect.zero,
      children: const [],
    );
  }

  var placement = Matrix4.translationValues(
    _num(element, 'x') ?? 0,
    _num(element, 'y') ?? 0,
    0,
  );

  // `<use width height>` against a `<symbol>`/`<svg>` target's `viewBox`:
  // scale-to-fit + center, i.e. the default `preserveAspectRatio="xMidYMid
  // meet"` behavior (other alignments/`slice` are not implemented).
  final viewBox = target.getAttribute(const SdQName('viewBox'));
  final useW = _num(element, 'width');
  final useH = _num(element, 'height');
  if (viewBox != null &&
      useW != null &&
      useH != null &&
      (target.name.local == 'symbol' || target.name.local == 'svg')) {
    final parts = viewBox.trim().split(RegExp(r'[\s,]+'));
    if (parts.length == 4) {
      final vb = parts.map(double.tryParse).toList();
      if (!vb.contains(null) && vb[2]! > 0 && vb[3]! > 0) {
        final vbX = vb[0]!, vbY = vb[1]!, vbW = vb[2]!, vbH = vb[3]!;
        final scale = math.min(useW / vbW, useH / vbH);
        final tx = (useW - vbW * scale) / 2 - vbX * scale;
        final ty = (useH - vbH * scale) / 2 - vbY * scale;
        placement =
            placement *
            (Matrix4.translationValues(tx, ty, 0)
              ..scaleByDouble(scale, scale, 1.0, 1.0));
      }
    }
  }
  placement = placement * ownTransform;

  final resolved = _build(target, state, ids, {
    ...resolvingUseIds,
    targetId,
  }, isUseTarget: true);
  if (resolved == null) {
    return SceneNode(
      element: element,
      transform: placement,
      localBounds: Rect.zero,
      children: const [],
    );
  }
  return SceneNode(
    element: element,
    transform: placement,
    localBounds: Rect.zero,
    children: [resolved],
    isSelectionBoundary: true,
  );
}

/// Renders `<text>` as a single run (its concatenated direct text content,
/// styled from its own resolved paint state) via [TextPainter] — per §8.
/// `<tspan>` sub-styling/positioning is not implemented (Phase 2 scope cut
/// noted on [buildScene]).
SceneNode? _buildText(
  SdElement element,
  SvgPaintState state,
  Matrix4 transform,
  Map<String, SdElement> ids,
  Set<String> resolvingUseIds,
) {
  final buffer = StringBuffer();
  void collect(SdElement e) {
    for (final child in e.children) {
      switch (child) {
        case SdText():
          buffer.write(child.data);
        case SdElement():
          collect(child); // flatten <tspan> text into the run
        default:
          break;
      }
    }
  }

  collect(element);
  final text = buffer.toString().trim();
  final x = _num(element, 'x') ?? 0;
  final y = _num(element, 'y') ?? 0;
  final fontSize = _num(element, 'font-size') ?? 16;

  if (text.isEmpty) {
    return SceneNode(
      element: element,
      transform: transform,
      localBounds: Rect.zero,
      children: const [],
    );
  }

  final color = state.fillPaint?.color ?? const Color(0xFF000000);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // SVG anchors `<text>` at its text baseline; TextPainter positions from
  // the top-left of the laid-out box, so shift up by the (approximate)
  // ascent to land the baseline at (x, y).
  final origin = Offset(x, y - painter.height * 0.8);
  return SceneNode(
    element: element,
    transform: transform,
    textPainter: painter,
    textOrigin: origin,
    localBounds: Rect.fromLTWH(
      origin.dx,
      origin.dy,
      painter.width,
      painter.height,
    ),
    children: const [],
  );
}
