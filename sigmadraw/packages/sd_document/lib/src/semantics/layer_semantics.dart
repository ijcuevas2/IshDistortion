import '../document_tree.dart';
import '../namespaces.dart';
import '../qname.dart';
import 'sd_attributes.dart';

const SdQName _groupMode = SdQName('groupmode', SdNamespace.inkscape);
const SdQName _inkscapeLabel = SdQName('label', SdNamespace.inkscape);

/// Layer compatibility: a layer is a `<g>` marked
/// `inkscape:groupmode="layer"` — so Inkscape and other compatible tools
/// recognize it as a layer too — plus `sd:layer` for any SigmaDraw-specific
/// layer metadata. See §3.
extension SdLayerSemantics on SdElement {
  bool get isLayer => getAttribute(_groupMode) == 'layer';

  set isLayer(bool value) =>
      setOrRemoveAttribute(this, _groupMode, value ? 'layer' : null);

  /// Layer display name. Stored as `inkscape:label` for cross-tool
  /// compatibility — deliberately not `sd:label`, which is block-specific
  /// (see `SdBlockSemantics.blockLabel`).
  String? get layerName => getAttribute(_inkscapeLabel);
  set layerName(String? value) =>
      setOrRemoveAttribute(this, _inkscapeLabel, value);

  String? get layerId => getAttribute(SdAttr.layer);
  set layerId(String? value) => setOrRemoveAttribute(this, SdAttr.layer, value);
}
