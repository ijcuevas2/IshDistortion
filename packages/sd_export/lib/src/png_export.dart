import 'dart:io';
import 'dart:ui' as ui;

import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

/// Options for [exportToPng].
class PngExportOptions {
  const PngExportOptions({this.scale = 1});

  /// Pixels per document (SVG user) unit — e.g. `2` renders at twice the
  /// document's own declared `width`/`height` (a "2x"/retina-style
  /// export), matching how DPI scaling for a raster export is usually
  /// expressed as a multiplier on the vector source's natural size.
  final double scale;
}

/// Exports [document] as a PNG raster image at [outputPath] (§11's
/// "PNG@DPI" export target), rendering it via the exact same retained-
/// scene painting [SigmaCanvas] uses on screen ([buildScene] +
/// [paintSceneNode]) rather than a second, separate rendering path — what
/// a user sees on screen is what gets exported, by construction, not by
/// two implementations happening to agree.
///
/// The image is sized to the document's own declared `width`/`height`
/// (the same SVG root attributes `createBlankSdDocument` sets and
/// `writeSdDocument` round-trips) times [PngExportOptions.scale] — not
/// the bounding box of its actual content, matching how any standard SVG
/// viewer treats those attributes as the image's natural raster size.
/// Throws [ArgumentError] if the document has no valid `width`/`height`.
///
/// Deliberately *not* run through `Isolate.run` (unlike `exportToPdf`):
/// `dart:ui`'s rendering primitives (`PictureRecorder`, `Image`) are tied
/// to the single UI isolate a Flutter engine runs on — there is no
/// "background isolate" to hand this off to, unlike an external process
/// invocation. `Picture.toImage`/`Image.toByteData` are still genuinely
/// asynchronous (the rasterization itself happens on the engine's own
/// raster thread, not synchronously on the calling isolate), so this
/// doesn't block the event loop the way a long synchronous computation
/// would — the same reason `RenderRepaintBoundary.toImage()` elsewhere in
/// the framework needs no isolate offloading either.
Future<void> exportToPng(
  SdDocument document,
  String outputPath, {
  PngExportOptions options = const PngExportOptions(),
}) async {
  final width = _numAttr(document, 'width');
  final height = _numAttr(document, 'height');
  if (width == null || height == null) {
    throw ArgumentError(
      'Document has no valid width/height attribute to export at.',
    );
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(options.scale);
  paintSceneNode(canvas, buildScene(document));
  final picture = recorder.endRecording();

  final image = await picture.toImage(
    (width * options.scale).round(),
    (height * options.scale).round(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode this image as PNG.');
  }
  // Sync, not writeAsBytes: this project has confirmed (see the README's
  // Isolate.run/testWidgets note) that some async dart:io calls don't
  // reliably complete inside a testWidgets test, so every dialog/export
  // path here uses the sync form as a matter of course.
  File(outputPath).writeAsBytesSync(byteData.buffer.asUint8List());
}

double? _numAttr(SdDocument document, String name) {
  final raw = document.root.getAttribute(SdQName(name));
  return raw == null ? null : double.tryParse(raw);
}
