import 'dart:io';
import 'dart:isolate';

import 'package:sd_document/sd_document.dart';

import 'tikz_export.dart';

/// Raised when the external `pdflatex` toolchain is missing or fails to
/// compile the generated diagram. [log] carries its raw stdout+stderr for
/// diagnosis, separate from the short [message].
class PdfExportException implements Exception {
  const PdfExportException(this.message, {this.log});

  final String message;
  final String? log;

  @override
  String toString() =>
      log == null ? 'PdfExportException: $message' : '$message\n$log';
}

/// Exports [document] to a real PDF file at [outputPath] (§11's "PDF"
/// export target) by compiling the same standalone TikZ source
/// [exportToTikz] produces, via an external `pdflatex` process — the
/// exact toolchain `tikz_export_test.dart` already verifies actually
/// compiles, now driving a real library entry point instead of only a
/// test assertion.
///
/// [scale] is forwarded to [exportToTikz] (SVG user units per TikZ unit —
/// see [TikzExportOptions.scale]); `standalone` is always forced `true`
/// regardless of that option's own default, since a bare `tikzpicture`
/// snippet has nothing to compile on its own.
///
/// Compiles in a scratch temp directory, never [outputPath]'s own
/// directory, so `pdflatex`'s intermediate `.aux`/`.log`/... files never
/// leak into a caller's chosen output location — only the resulting
/// `.pdf` is copied there. Runs off the UI isolate via [Isolate.run] (per
/// §2/§14's "do not block the UI isolate on ... export" — the same
/// reasoning, and the same technique, as `sd_latex`'s
/// `compileLatexToSvg`): only plain strings (the generated TikZ source
/// and the two file paths) cross the isolate boundary, never an
/// [SdDocument] itself.
///
/// Throws [PdfExportException] if `pdflatex` is missing from `PATH` or
/// the source fails to compile (a genuine LaTeX error) — there is no
/// silent fallback, since an explicit export request should surface a
/// real failure loudly rather than write a blank or wrong file.
Future<void> exportToPdf(
  SdDocument document,
  String outputPath, {
  double scale = 1 / svgUnitsPerCm,
}) async {
  final tex = exportToTikz(document, options: TikzExportOptions(scale: scale));
  await Isolate.run(() => _compileTexToPdfFile(tex, outputPath));
}

Future<void> _compileTexToPdfFile(String tex, String outputPath) async {
  final tempDir = await Directory.systemTemp.createTemp('sigmadraw-pdf-');
  try {
    await compileTexToPdfInDirectory(tex, tempDir);
    await File('${tempDir.path}/diagram.pdf').copy(outputPath);
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Compiles [tex] via `pdflatex` inside [tempDir] (assumed already
/// created and empty), leaving a `diagram.pdf` there on success — the
/// exact compile step [exportToPdf] itself uses, factored out so
/// `eps_export.dart`'s `exportToEps` can start from the same,
/// once-verified step before running its own further `pdftops -eps`
/// conversion on the result, rather than duplicating this logic.
///
/// Deliberately public (not `_`-private) despite being called from only
/// one other file in this package — the same reasoning
/// `tikz_export.dart`'s `svgUnitsPerCm` documents: Dart's privacy is
/// per-*file*, and there's no narrower "package-private" visibility to
/// reach for instead.
///
/// Throws [PdfExportException] exactly as [exportToPdf] does; does
/// *not* itself run inside an `Isolate.run` (unlike [exportToPdf]) —
/// that's the caller's job, so a caller doing further isolate-local work
/// (like `exportToEps`'s own `Process.run` for `pdftops`) doesn't pay for
/// a second isolate hop in between.
Future<void> compileTexToPdfInDirectory(String tex, Directory tempDir) async {
  File('${tempDir.path}/diagram.tex').writeAsStringSync(tex);

  final ProcessResult result;
  try {
    result = await Process.run('pdflatex', [
      '-interaction=nonstopmode',
      '-halt-on-error',
      'diagram.tex',
    ], workingDirectory: tempDir.path);
  } on ProcessException catch (e) {
    throw PdfExportException(
      'pdflatex is not available on PATH.',
      log: e.toString(),
    );
  }
  if (result.exitCode != 0) {
    throw PdfExportException(
      'pdflatex could not compile this diagram.',
      log: '${result.stdout}\n${result.stderr}',
    );
  }
}
