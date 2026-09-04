/// SVG/PDF/PNG/EPS/TikZ export and printing for SigmaDraw (§11).
///
/// Implemented: TikZ export (`exportToTikz`) — tikz-dsp-style source from
/// the semantic graph, verified to actually `pdflatex`-compile (see
/// `tikz_export_test.dart`; §13's acceptance criterion #5). SVG native/
/// plain export already lives in `sd_document`'s `writeSdDocument`
/// (`SdSaveMode`), so isn't duplicated here. Not implemented: vector PDF,
/// PNG@DPI, EPS/PS, and print dialogs.
library;

export 'src/tikz_export.dart';
