import 'package:sd_document/sd_document.dart';

/// Builds one edge's dual-representation element (§3): a plain SVG line
/// (so it renders even without `sd_render`'s knowledge of the two blocks'
/// exact port geometry) decorated with `sd:edge`/`sd:from`/`sd:to`. Used
/// by the composite generators in `filter_templates.dart` to wire up the
/// several blocks they place — real per-port positions get filled in by
/// whichever renderer displays the document (`sd_render`'s scene builder
/// doesn't need this path's `d` to be accurate; only the semantic
/// endpoints matter for analysis).
SdElement buildEdge({
  required String id,
  required String fromBlock,
  required String fromPort,
  required String toBlock,
  required String toPort,
  String? signalLabel,
}) =>
    SdElement(
        const SdQName('path'),
        // Not `const {...}`: a const map's keys must use identity/primitive
        // equality, but SdQName defines its own `==` (by local name + resolved
        // namespace, per the XML Namespaces spec) — see its doc comment.
        attributes: {
          const SdQName('stroke'): '#1a1a1a',
          const SdQName('stroke-width'): '2',
          const SdQName('fill'): 'none',
          const SdQName('vector-effect'): 'non-scaling-stroke',
          // Placeholder geometry — a renderer/layout pass positions real
          // edges; see the doc comment above.
          const SdQName('d'): 'M0,0 L0,0',
        },
      )
      ..edgeId = id
      ..edgeFrom = '$fromBlock:$fromPort'
      ..edgeTo = '$toBlock:$toPort'
      ..edgeSignalLabel = signalLabel;
