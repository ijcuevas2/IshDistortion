import '../document_tree.dart';
import '../qname.dart';

/// `sd:*` attribute names — the private-namespace vocabulary from §3.
///
/// These are intentionally just names, not a typed model: `sd_document`
/// stays at the generic XML/round-trip level. The fully-typed Port/Block/
/// Edge domain model (dtype enums, rational sample rates, validation) is
/// `sd_graph`'s job (§4), built on top of the raw string/JSON accessors in
/// this `semantics/` directory.
abstract final class SdAttr {
  // Block dual-representation (§3).
  static final type = SdQName.sd('type');
  static final id = SdQName.sd('id');
  static final label = SdQName.sd('label');
  static final params = SdQName.sd('params');
  static final ports = SdQName.sd('ports');

  /// Whether this block passes signal from input to output within the
  /// same sample instant — omitted (implicitly `true`) unless `false`, so
  /// the overwhelmingly common case stays out of native output. Read by
  /// `sd_graph`'s algebraic-loop detection (§4) — persisted here (not just
  /// held in a stencil's in-memory definition) so a reopened document is
  /// still analyzable without its original stencil registry.
  static final directFeedthrough = SdQName.sd('directFeedthrough');

  // Edge dual-representation (§3) — see the doc comment on
  // `SdEdgeSemantics` for why this is an attribute, not a separate element.
  static final edge = SdQName.sd('edge');
  static final from = SdQName.sd('from');
  static final to = SdQName.sd('to');
  static final route = SdQName.sd('route');
  static final signalLabel = SdQName.sd('signalLabel');

  // Ink strokes (§3, §6).
  static final stroke = SdQName.sd('stroke');
  static final pressure = SdQName.sd('pressure');

  /// The original, editable LaTeX source behind an embedded math fragment
  /// (§11: "Store original LaTeX source in `sd:latex` (textext-style
  /// editable)") — carried on the `<g>` that wraps that fragment's real
  /// vector glyph content, alongside the rendered geometry itself, so
  /// reopening the document lets the equation be re-edited (and
  /// recompiled) rather than only displayed.
  static final latex = SdQName.sd('latex');

  // Document-level (§3).
  static final schema = SdQName.sd('schema');
  static final sampleRate = SdQName.sd('sampleRate');
  static final defaultDtype = SdQName.sd('defaultDtype');
  static final layer = SdQName.sd('layer');
}

/// Sets [name] to [value] on [element], or removes it if [value] is `null`.
/// Shared by every file under `semantics/` so a cleared field disappears
/// from the attribute list entirely rather than round-tripping as `""`.
void setOrRemoveAttribute(SdElement element, SdQName name, String? value) {
  if (value == null) {
    element.removeAttribute(name);
  } else {
    element.setAttribute(name, value);
  }
}
