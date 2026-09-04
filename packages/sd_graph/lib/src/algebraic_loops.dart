import 'package:meta/meta.dart';

import 'signal_graph.dart';

/// One delay-free feedback loop found by [detectAlgebraicLoops]: the
/// blocks involved, in cycle order, all of which have
/// `directFeedthrough: true` — meaning the loop has no state anywhere to
/// break the instantaneous dependency (§4).
@immutable
class AlgebraicLoop {
  const AlgebraicLoop(this.blockIds);
  final List<String> blockIds;

  @override
  String toString() => 'AlgebraicLoop(${blockIds.join(' -> ')})';
}

/// Finds every strongly-connected component of [graph] via Tarjan's
/// algorithm, then reports one as an algebraic loop iff its induced
/// subgraph — restricted to blocks with `directFeedthrough: true` — still
/// contains a cycle (§4: "an SCC is an algebraic loop iff a cycle exists
/// where no edge path has a delay AND all blocks have direct
/// feedthrough"). A valid diagram has no feedback loop that doesn't pass
/// through at least one state-holding (delay) block.
List<AlgebraicLoop> detectAlgebraicLoops(SignalGraph graph) {
  final loops = <AlgebraicLoop>[];
  for (final scc in _stronglyConnectedComponents(
    graph,
    graph.blocks.keys.toSet(),
  )) {
    if (scc.length < 2 && !_hasSelfLoop(graph, scc.single)) continue;

    final feedthroughOnly = scc
        .where((id) => graph.block(id)!.directFeedthrough)
        .toSet();
    for (final sub in _stronglyConnectedComponents(graph, feedthroughOnly)) {
      if (sub.length >= 2 ||
          (sub.length == 1 && _hasSelfLoop(graph, sub.single))) {
        loops.add(AlgebraicLoop(sub..sort()));
      }
    }
  }
  return loops;
}

bool _hasSelfLoop(SignalGraph graph, String blockId) =>
    graph.edgesFrom(blockId).any((e) => e.toBlockId == blockId);

/// Tarjan's strongly-connected-components algorithm, restricted to edges
/// between nodes in [nodes] (so it can be re-run on the direct-feedthrough
/// subset of an already-found SCC without re-discovering unrelated ones).
List<List<String>> _stronglyConnectedComponents(
  SignalGraph graph,
  Set<String> nodes,
) {
  var nextIndex = 0;
  final index = <String, int>{};
  final lowlink = <String, int>{};
  final onStack = <String>{};
  final stack = <String>[];
  final result = <List<String>>[];

  void strongConnect(String v) {
    index[v] = nextIndex;
    lowlink[v] = nextIndex;
    nextIndex++;
    stack.add(v);
    onStack.add(v);

    for (final edge in graph.edgesFrom(v)) {
      final w = edge.toBlockId;
      if (!nodes.contains(w)) continue;
      if (!index.containsKey(w)) {
        strongConnect(w);
        lowlink[v] = lowlink[v]!.compareTo(lowlink[w]!) < 0
            ? lowlink[v]!
            : lowlink[w]!;
      } else if (onStack.contains(w)) {
        lowlink[v] = lowlink[v]!.compareTo(index[w]!) < 0
            ? lowlink[v]!
            : index[w]!;
      }
    }

    if (lowlink[v] == index[v]) {
      final component = <String>[];
      while (true) {
        final w = stack.removeLast();
        onStack.remove(w);
        component.add(w);
        if (w == v) break;
      }
      result.add(component);
    }
  }

  for (final v in nodes) {
    if (!index.containsKey(v)) strongConnect(v);
  }
  return result;
}
