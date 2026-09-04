/// SVG/PDF/PNG/EPS/TikZ export and printing for SigmaDraw (§11).
///
/// Implemented: TikZ export (`exportToTikz`) — tikz-dsp-style source from
/// the semantic graph, verified to actually `pdflatex`-compile (see
/// `tikz_export_test.dart`; §13's acceptance criterion #5); PDF export
/// (`exportToPdf`) compiles that same TikZ source to a real `.pdf` file
/// via the same toolchain; EPS export (`exportToEps`) converts that same
/// PDF to EPS via `pdftops -eps` (not the more traditional `dvips -E`
/// path — see `exportToEps`'s own doc comment on why that one produces
/// an empty file for this project's diagrams); PNG export
/// (`exportToPng`) rasterizes the document at its own declared size
/// (times an optional scale) through `sd_render`'s exact on-screen
/// scene-painting code, not a second rendering path. SVG native/plain
/// export already lives in `sd_document`'s `writeSdDocument`
/// (`SdSaveMode`), so isn't duplicated here. Not implemented: print
/// dialogs.
library;

export 'src/eps_export.dart';
export 'src/pdf_export.dart';
export 'src/png_export.dart';
export 'src/tikz_export.dart';
