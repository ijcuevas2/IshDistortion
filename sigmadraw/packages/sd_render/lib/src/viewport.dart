import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The camera for SigmaDraw's infinite canvas: a pan translation plus a
/// uniform zoom scale, mapping document (SVG user-unit) space to screen
/// (widget-pixel) space. Deliberately *not* a full affine [Matrix4] — the
/// canvas itself only ever pans and zooms (§8: "matrix transform (pan/
/// zoom), zoom-to-cursor, fit-to-content"); individual elements carry
/// their own rotate/skew via their SVG `transform` attribute instead.
@immutable
class SigmaViewport {
  const SigmaViewport({this.translation = Offset.zero, this.scale = 1.0});

  final Offset translation;
  final double scale;

  static const double minScale = 0.02;
  static const double maxScale = 256.0;

  Offset documentToScreen(Offset doc) => doc * scale + translation;

  Offset screenToDocument(Offset screen) => (screen - translation) / scale;

  Rect documentToScreenRect(Rect r) => Rect.fromPoints(
    documentToScreen(r.topLeft),
    documentToScreen(r.bottomRight),
  );

  Rect screenToDocumentRect(Rect r) => Rect.fromPoints(
    screenToDocument(r.topLeft),
    screenToDocument(r.bottomRight),
  );

  /// A 4x4 matrix equivalent to this viewport, for feeding to
  /// `Canvas.transform`/`MatrixUtils` alongside per-element transforms.
  Matrix4 toMatrix4() => Matrix4.identity()
    ..translateByDouble(translation.dx, translation.dy, 0.0, 1.0)
    ..scaleByDouble(scale, scale, 1.0, 1.0);

  SigmaViewport panBy(Offset screenDelta) =>
      SigmaViewport(translation: translation + screenDelta, scale: scale);

  /// Zooms by [factor], keeping the document point currently under
  /// [screenFocalPoint] (typically the cursor) fixed on screen.
  SigmaViewport zoomBy(double factor, Offset screenFocalPoint) {
    final newScale = (scale * factor).clamp(minScale, maxScale).toDouble();
    final applied = newScale / scale;
    final newTranslation =
        screenFocalPoint - (screenFocalPoint - translation) * applied;
    return SigmaViewport(translation: newTranslation, scale: newScale);
  }

  /// A viewport that centers and scales-to-fit [contentBounds] within
  /// [viewportSize], leaving [margin] screen pixels of breathing room.
  static SigmaViewport fitting(
    Rect contentBounds,
    Size viewportSize, {
    double margin = 32,
  }) {
    if (contentBounds.isEmpty || viewportSize.isEmpty) {
      return const SigmaViewport();
    }
    final availableW = math.max(1.0, viewportSize.width - margin * 2);
    final availableH = math.max(1.0, viewportSize.height - margin * 2);
    final scale = math
        .min(
          availableW / contentBounds.width,
          availableH / contentBounds.height,
        )
        .clamp(minScale, maxScale)
        .toDouble();
    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final translation = viewportCenter - contentBounds.center * scale;
    return SigmaViewport(translation: translation, scale: scale);
  }

  @override
  bool operator ==(Object other) =>
      other is SigmaViewport &&
      other.translation == translation &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(translation, scale);
}
