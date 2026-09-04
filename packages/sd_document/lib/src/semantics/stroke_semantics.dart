import 'dart:convert';

import '../document_tree.dart';
import 'sd_attributes.dart';

/// Typed view over an ink stroke's `sd:*` attributes.
///
/// The *visible* geometry is always a filled-outline `<path>` — never a
/// variable-width stroke (§6) — so it renders correctly in any SVG viewer.
/// [strokeCenterline] (`sd:strokePoints`) and [strokePressures]
/// (`sd:pressure`) together preserve the original, editable control
/// polygon (position *and* pressure/width at each point, correlated by
/// index) so `sd_ink` can re-derive an editable centerline later, rather
/// than trying to reconstruct one from the outline alone — which the
/// outline alone can't give back exactly even in principle once the
/// width varies point-to-point (the two offset rails don't average back
/// to the original centerline). Both are written together and are the
/// same length; a corrupted/hand-edited file where they disagree isn't
/// specially detected — a length mismatch just means [strokeCenterline]
/// or [strokePressures] read back short relative to the other.
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

  /// The stroke's editable centerline control points (`sd:strokePoints`,
  /// `[[x,y], ...]`), in the same order as, and the same length as,
  /// [strokePressures].
  List<({double x, double y})> get strokeCenterline {
    final raw = getAttribute(SdAttr.strokePoints);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final pair in decoded)
        if (pair is List && pair.length == 2)
          (x: (pair[0] as num).toDouble(), y: (pair[1] as num).toDouble()),
    ];
  }

  set strokeCenterline(List<({double x, double y})> value) {
    setOrRemoveAttribute(
      this,
      SdAttr.strokePoints,
      value.isEmpty
          ? null
          : jsonEncode([
              for (final p in value) [p.x, p.y],
            ]),
    );
  }
}
