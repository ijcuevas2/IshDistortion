import 'dart:convert';

import '../document_tree.dart';
import 'sd_attributes.dart';

/// Typed view over an ink stroke's `sd:*` attributes.
///
/// The *visible* geometry is always a filled-outline `<path>` — never a
/// variable-width stroke (§6) — so it renders correctly in any SVG viewer.
/// `sd:pressure` separately preserves the original per-point pressure/width
/// samples so `sd_ink` can re-derive an editable centerline later, rather
/// than trying to reconstruct one from the outline alone.
extension SdStrokeSemantics on SdElement {
  /// The stroke's stable id (`sd:stroke`). `null` if this element carries
  /// no stroke semantics at all.
  String? get strokeId => getAttribute(SdAttr.stroke);
  set strokeId(String? value) =>
      setOrRemoveAttribute(this, SdAttr.stroke, value);

  /// Per-point pressure/width samples (`sd:pressure`), JSON-encoded in
  /// stroke-point order.
  List<double> get strokePressures {
    final raw = getAttribute(SdAttr.pressure);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.map((e) => (e as num).toDouble()).toList();
  }

  set strokePressures(List<double> value) {
    setOrRemoveAttribute(
      this,
      SdAttr.pressure,
      value.isEmpty ? null : jsonEncode(value),
    );
  }
}
