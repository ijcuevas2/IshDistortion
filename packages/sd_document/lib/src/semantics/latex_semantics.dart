import '../document_tree.dart';
import 'sd_attributes.dart';

/// Typed view over an embedded-LaTeX fragment's `sd:latex` attribute (§11).
///
/// `sd_latex` (Phase 9) compiles a LaTeX string to real vector glyph-outline
/// SVG (via the desktop `pdflatex` -> `dvisvgm --no-fonts` pipeline) and
/// splices it into the document as an ordinary `<g>` of `<path>`/`<use>`
/// content — that geometry alone is what every other SVG viewer sees and
/// renders. [latexSource] is the *editable* source behind it, textext-style:
/// present only on the wrapping `<g>`, so re-selecting that group and
/// re-invoking the equation editor can recompile and replace its content in
/// place instead of starting from a blank formula.
extension SdLatexSemantics on SdElement {
  /// The original LaTeX source this element's content was compiled from, or
  /// `null` for an element with no embedded-math semantics at all (the
  /// overwhelmingly common case — plain diagram geometry).
  String? get latexSource => getAttribute(SdAttr.latex);
  set latexSource(String? value) =>
      setOrRemoveAttribute(this, SdAttr.latex, value);
}
