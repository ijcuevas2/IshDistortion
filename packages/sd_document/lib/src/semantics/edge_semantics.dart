import '../document_tree.dart';
import 'sd_attributes.dart';

/// Typed view over an edge instance's `sd:*` attributes.
///
/// Design decision: an edge is an ordinary SVG element (typically a
/// `<path>`) for the visible wire, decorated with `sd:edge` (the edge's own
/// stable id — mirrors how `sd:type` + `sd:id` mark and identify a block)
/// plus `sd:from` / `sd:to` / `sd:route` / `sd:signalLabel`. There is no
/// separate `<sd:edge>` element: this keeps edges in the same "plain SVG
/// geometry plus `sd:` attributes" dual representation as blocks (§3), so
/// [SdSaveMode.plain] leaves behind an ordinary, renderable path.
extension SdEdgeSemantics on SdElement {
  /// The edge's stable id (`sd:edge`). `null` if this element carries no
  /// edge semantics at all.
  String? get edgeId => getAttribute(SdAttr.edge);
  set edgeId(String? value) => setOrRemoveAttribute(this, SdAttr.edge, value);

  /// `"blockId:portId"` — the source endpoint.
  String? get edgeFrom => getAttribute(SdAttr.from);
  set edgeFrom(String? value) => setOrRemoveAttribute(this, SdAttr.from, value);

  /// `"blockId:portId"` — the destination endpoint.
  String? get edgeTo => getAttribute(SdAttr.to);
  set edgeTo(String? value) => setOrRemoveAttribute(this, SdAttr.to, value);

  /// `"orthogonal"` | `"polyline"` | `"curved"` (§9).
  String? get edgeRoute => getAttribute(SdAttr.route);
  set edgeRoute(String? value) =>
      setOrRemoveAttribute(this, SdAttr.route, value);

  /// The signal label drawn along the wire, e.g. `"x[n]"`.
  String? get edgeSignalLabel => getAttribute(SdAttr.signalLabel);
  set edgeSignalLabel(String? value) =>
      setOrRemoveAttribute(this, SdAttr.signalLabel, value);
}
