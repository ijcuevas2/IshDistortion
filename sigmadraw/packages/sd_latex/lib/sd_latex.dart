/// Math rendering for SigmaDraw (§11).
///
/// Two independent paths, per the spec's own split:
/// - [LatexLabel]: fast on-screen/tablet rendering via `flutter_math_fork`
///   (a KaTeX subset) — falls back to showing its raw TeX source rather
///   than a bare error when a command it doesn't support is used.
/// - [compileLatexToSvg]/[embedLatex]/[LatexRenderCache]: the desktop
///   `pdflatex`+`dvisvgm` pipeline, producing real vector glyph-outline
///   content to embed natively in the document (not on-screen chrome) —
///   the original LaTeX source is preserved via `sd_document`'s
///   `SdLatexSemantics.latexSource` (`sd:latex`) for later re-editing.
///
/// Not implemented: an equation-editor dialog/launcher (§10's Insert
/// ribbon item), the built-in DSP label helpers (gain-coefficient-on-
/// triangle, `x[n]`/`y[n]`-on-edge, ...) beyond what already exists
/// per-stencil, and the optional experimental WASM-TeX fallback.
library;

export 'src/latex_label.dart';
export 'src/latex_pipeline.dart';
