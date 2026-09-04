import 'dart:convert';

import '../document_tree.dart';
import 'sd_attributes.dart';

/// Typed view over a block instance's `sd:*` attributes (§3: "Dual
/// representation per DSP block"). [blockParams]/[blockPorts] decode their
/// JSON attribute text on every read and re-encode on write. Kept as raw
/// `Map`/`List` JSON here rather than a richer typed model — see the doc
/// comment on `SdAttr` for why (`sd_graph` owns the typed Port/dtype model,
/// in a later phase).
extension SdBlockSemantics on SdElement {
  /// The block's stencil type id (`sd:type`), e.g. `"gain"`, `"delay-z1"`.
  /// `null` if this element carries no block semantics at all.
  String? get blockType => getAttribute(SdAttr.type);
  set blockType(String? value) =>
      setOrRemoveAttribute(this, SdAttr.type, value);

  /// The block instance's stable id (`sd:id`) — the `blockId` half of an
  /// edge's `sd:from`/`sd:to` (§3).
  String? get blockId => getAttribute(SdAttr.id);
  set blockId(String? value) => setOrRemoveAttribute(this, SdAttr.id, value);

  /// The human-visible label (`sd:label`), e.g. `"k"` on a gain triangle.
  String? get blockLabel => getAttribute(SdAttr.label);
  set blockLabel(String? value) =>
      setOrRemoveAttribute(this, SdAttr.label, value);

  /// The block's parameters (`sd:params`), decoded from JSON. Empty if the
  /// attribute is absent or is not a JSON object.
  Map<String, Object?> get blockParams {
    final raw = getAttribute(SdAttr.params);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : const {};
  }

  set blockParams(Map<String, Object?> value) {
    setOrRemoveAttribute(
      this,
      SdAttr.params,
      value.isEmpty ? null : jsonEncode(value),
    );
  }

  /// The block's port list (`sd:ports`), decoded from JSON as a raw list of
  /// `{id, dir, dtype, vlen, rate, x, y, angle}` maps (§3). `sd_graph`
  /// parses these into typed `Port` objects.
  List<Map<String, Object?>> get blockPorts {
    final raw = getAttribute(SdAttr.ports);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, Object?>>().toList();
  }

  set blockPorts(List<Map<String, Object?>> value) {
    setOrRemoveAttribute(
      this,
      SdAttr.ports,
      value.isEmpty ? null : jsonEncode(value),
    );
  }
}
