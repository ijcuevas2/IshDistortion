import 'package:sd_document/sd_document.dart';

import 'block.dart';
import 'edge.dart';
import 'port.dart';

/// The semantic signal-flow graph (§4): blocks and edges extracted from a
/// document's `sd:*` attributes. Immutable — build a new one after editing
/// the document (cheap at this project's target scale; see `sd_render`'s
/// `Scene` for the same call on the rendering side).
class SignalGraph {
  SignalGraph({required Map<String, Block> blocks, required this.edges})
    : blocks = Map.unmodifiable(blocks);

  final Map<String, Block> blocks;
  final List<Edge> edges;

  Block? block(String id) => blocks[id];

  Iterable<Edge> edgesFrom(String blockId, [String? portId]) => edges.where(
    (e) =>
        e.fromBlockId == blockId && (portId == null || e.fromPortId == portId),
  );

  Iterable<Edge> edgesTo(String blockId, [String? portId]) => edges.where(
    (e) => e.toBlockId == blockId && (portId == null || e.toPortId == portId),
  );

  /// Extracts the graph from every `sd:type`-bearing element (a block) and
  /// `sd:edge`-bearing element (an edge) anywhere in [document].
  factory SignalGraph.fromDocument(SdDocument document) {
    final blocks = <String, Block>{};
    final edges = <Edge>[];

    for (final element in document.root.descendantElements) {
      final blockType = element.blockType;
      if (blockType != null) {
        final id = element.blockId ?? blockType;
        blocks[id] = Block(
          id: id,
          type: blockType,
          label: element.blockLabel,
          params: element.blockParams,
          directFeedthrough: element.blockDirectFeedthrough,
          ports: [for (final p in element.blockPorts) Port.fromJson(p)],
        );
        continue;
      }

      final edgeId = element.edgeId;
      final from = element.edgeFrom;
      final to = element.edgeTo;
      if (edgeId != null && from != null && to != null) {
        final fromParts = from.split(':');
        final toParts = to.split(':');
        if (fromParts.length == 2 && toParts.length == 2) {
          edges.add(
            Edge(
              id: edgeId,
              fromBlockId: fromParts[0],
              fromPortId: fromParts[1],
              toBlockId: toParts[0],
              toPortId: toParts[1],
              route: element.edgeRoute,
              signalLabel: element.edgeSignalLabel,
            ),
          );
        }
      }
    }

    return SignalGraph(blocks: blocks, edges: edges);
  }
}
