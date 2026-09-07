import 'dart:io';
import 'dart:isolate';

import 'package:sd_document/sd_document.dart';

import 'pdf_export.dart';
import 'tikz_export.dart';

/// Raised when the external `pdftops` toolchain is missing or fails to
/// convert the compiled diagram to EPS. [log] carries its raw
/// stdout+stderr for diagnosis, separate from the short [message]. A
/// [PdfExportException] from the same call means the *earlier*
/// `pdflatex` compile step failed instead — see [exportToEps]'s own doc
/// comment on the two-stage pipeline this distinguishes.
class EpsExportException implements Exception {
  const EpsExportException(this.message, {this.log});

  final String message;
  final String? log;

  @override
  String toString() =>
      log == null ? 'EpsExportException: $message' : '$message\n$log';
}

/// Exports [document] to a real EPS file at [outputPath] (§11's "EPS/PS"
/// export target) via a two-stage pipeline: [exportToTikz]'s source is
/// first compiled to a PDF exactly as [exportToPdf] does (reusing
/// [compileTexToPdfInDirectory], the identical, already-verified step),
/// then that PDF is converted to EPS via `pdftops -eps` (poppler-utils).
///
/// This is *not* the classic `latex` (DVI output) + `dvips -E` pipeline
/// EPS export more traditionally uses, even though that toolchain is
/// also present — confirmed by hand that it produces a well-formed but
/// *empty* EPS for this project's TikZ diagrams: `dvips`'s reported
/// `%%BoundingBox` looked plausible, but Ghostscript's own ink-based
/// bounding-box detection (`gs -sDEVICE=bbox`) found nothing drawn at
/// all. The `standalone` document class's bounding-box computation (or
/// TikZ itself) apparently depends on pdfTeX-only primitives that a
/// plain, non-PDF `latex` run doesn't provide. Going through the PDF
/// this project already knows compiles correctly sidesteps that
/// entirely — `pdftops -eps` on the resulting PDF was confirmed by hand
/// to produce a real, correctly-bounded EPS (cross-checked the same way,
/// via Ghostscript's independent ink-based bounding box).
///
/// [scale] is forwarded to [exportToTikz] exactly as in [exportToPdf].
/// Compiles in a scratch temp directory, never [outputPath]'s own
/// directory — same reasoning as [exportToPdf]. Runs off the UI isolate
/// via [Isolate.run], same technique and reasoning as [exportToPdf].
///
/// Throws [PdfExportException] if the `pdflatex` compile stage fails (or
/// is missing), or [EpsExportException] if the subsequent `pdftops`
/// stage fails (or is missing) — no silent fallback either way, for the
/// same reason [exportToPdf] has none.
Future<void> exportToEps(
  SdDocument document,
  String outputPath, {
  double scale = 1 / svgUnitsPerCm,
}) async {
  final tex = exportToTikz(document, options: TikzExportOptions(scale: scale));
  await Isolate.run(() => _compileTexToEpsFile(tex, outputPath));
}

Future<void> _compileTexToEpsFile(String tex, String outputPath) async {
  final tempDir = await Directory.systemTemp.createTemp('sigmadraw-eps-');
  try {
    await compileTexToPdfInDirectory(tex, tempDir);

    final ProcessResult result;
    try {
      result = await Process.run('pdftops', [
        '-eps',
        'diagram.pdf',
        'diagram.eps',
      ], workingDirectory: tempDir.path);
    } on ProcessException catch (e) {
      throw EpsExportException(
        'pdftops is not available on PATH.',
        log: e.toString(),
      );
    }
    if (result.exitCode != 0) {
      throw EpsExportException(
        'pdftops could not convert this diagram to EPS.',
        log: '${result.stdout}\n${result.stderr}',
      );
    }

    await File('${tempDir.path}/diagram.eps').copy(outputPath);
  } finally {
    await tempDir.delete(recursive: true);
  }
}
