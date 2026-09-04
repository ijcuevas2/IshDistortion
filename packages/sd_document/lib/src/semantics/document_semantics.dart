import '../document_tree.dart';
import 'sd_attributes.dart';

/// Document-level SigmaDraw metadata, carried as `sd:*` attributes on the
/// root `<svg>` element — see §3.
extension SdDocumentSemantics on SdDocument {
  /// The SigmaDraw schema version this document was authored against
  /// (`sd:schema`); `null` if absent (e.g. a plain-SVG file that was never
  /// a SigmaDraw document).
  String? get schema => root.getAttribute(SdAttr.schema);
  set schema(String? value) => setOrRemoveAttribute(root, SdAttr.schema, value);

  /// The project sample rate (`sd:sampleRate`). Kept as a plain string so
  /// it can hold either a concrete rate (`"48000"`) or a symbolic one
  /// (`"Fs"`); `sd_graph`'s rate-propagation model (§4) owns the typed
  /// interpretation.
  String? get sampleRate => root.getAttribute(SdAttr.sampleRate);
  set sampleRate(String? value) =>
      setOrRemoveAttribute(root, SdAttr.sampleRate, value);

  /// The default port data type for newly created ports (`sd:defaultDtype`).
  String? get defaultDtype => root.getAttribute(SdAttr.defaultDtype);
  set defaultDtype(String? value) =>
      setOrRemoveAttribute(root, SdAttr.defaultDtype, value);
}
