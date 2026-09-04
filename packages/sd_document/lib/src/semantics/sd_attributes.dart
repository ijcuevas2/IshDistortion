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
