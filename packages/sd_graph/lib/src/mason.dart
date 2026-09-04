import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'block.dart';
import 'edge.dart';
import 'expression.dart';
import 'signal_graph.dart';

@immutable
class ForwardPath {
  const ForwardPath(this.blockIds, this.gain);
  final List<String> blockIds;
  final Expr gain;
}

@immutable
class Loop {
  const Loop(this.blockIds, this.gain);
  final List<String> blockIds;
  final Expr gain;
}

@immutable
class TransferFunctionResult {
  const TransferFunctionResult({
    required this.h,
    required this.forwardPaths,
    required this.loops,
    required this.determinant,
  });

  /// `H(z)` — a symbolic rational function (§4).
  final Expr h;
  final List<ForwardPath> forwardPaths;
  final List<Loop> loops;

  /// `Δ`, the graph determinant.
  final Expr determinant;
}

/// Derives the symbolic transfer function `H = (Σ P_k·Δ_k) / Δ` from
/// [sourceBlockId] to [sinkBlockId] via Mason's gain formula (§4),
/// defaulting to the graph's `source`/`sink` blocks if ids aren't given.
/// Returns `null` if no source/sink can be identified.
///
/// Branch gains are read off block *type*: a `gain` block contributes its
/// `gain` param, a `delay` block contributes `z^-k`, an `adder`'s each
/// input contributes its configured sign, and everything else (source,
/// sink, pickoff node, sampler, up/downsampler) passes through at unity —
/// multirate transfer functions (where a `↑L`/`↓M` genuinely changes the
/// polynomial degree relationship) are not modeled; treating them as
/// unity is exact for every other stencil and a documented simplification
/// for those two. This also assumes every block has at most one output
/// port (true of every stencil §5.1-5.3 ships), so a path/loop can be
/// tracked by block id alone rather than by (block, port) pairs.
TransferFunctionResult? computeTransferFunction(
  SignalGraph graph, {
  String? sourceBlockId,
  String? sinkBlockId,
}) {
  final source =
      sourceBlockId ??
      graph.blocks.values.firstWhereOrNull((b) => b.type == 'source')?.id;
  final sink =
      sinkBlockId ??
      graph.blocks.values.firstWhereOrNull((b) => b.type == 'sink')?.id;
  if (source == null || sink == null) return null;
  if (!graph.blocks.containsKey(source) || !graph.blocks.containsKey(sink)) {
    return null;
  }

  final forwardPaths = [
    for (final nodes in _findSimplePaths(graph, source, sink))
      ForwardPath(nodes, _sequentialGain(graph, nodes)),
  ];
  final loops = [
    for (final nodes in _findSimpleLoops(graph))
      Loop(nodes, _loopGain(graph, nodes)),
  ];

  final determinant = _determinant(loops);

  var numerator = const ConstExpr(0) as Expr;
  for (final path in forwardPaths) {
    final pathNodes = path.blockIds.toSet();
    final nonTouching = loops
        .where((l) => l.blockIds.toSet().intersection(pathNodes).isEmpty)
        .toList();
    numerator = numerator + path.gain * _determinant(nonTouching);
  }

  return TransferFunctionResult(
    h: numerator / determinant,
    forwardPaths: forwardPaths,
    loops: loops,
    determinant: determinant,
  );
}

/// The intrinsic gain a block contributes to every path passing through
/// it, attached once per traversal (see the class-level doc on why this
/// is unambiguous for our current stencil set).
Expr _sourceIntrinsicGain(Block block) {
  switch (block.type) {
    case 'gain':
      return Expr.fromParam(block.params['gain']);
    case 'delay':
      final k = (block.params['k'] as num?)?.toInt() ?? 1;
      return ZPowExpr(-k);
    default:
      return const ConstExpr(1);
  }
}

/// The sign a specific edge contributes when it lands on an `adder`'s
/// input (`+1`/`-1` from that input's configured sign); `1` otherwise.
Expr _destinationFactor(Edge edge, Block toBlock) {
  if (toBlock.type != 'adder') return const ConstExpr(1);
  final signs = (toBlock.params['signs'] as List?)?.cast<String>() ?? const [];
  final inputIds = toBlock.inputPorts.map((p) => p.id).toList();
  final index = inputIds.indexOf(edge.toPortId);
  final sign = (index >= 0 && index < signs.length) ? signs[index] : '+';
  return sign == '-' ? const ConstExpr(-1) : const ConstExpr(1);
}

Expr _edgeGain(SignalGraph graph, String fromId, String toId) {
  final edge = graph
      .edgesFrom(fromId)
      .firstWhereOrNull((e) => e.toBlockId == toId);
  if (edge == null) return const ConstExpr(0);
  return _sourceIntrinsicGain(graph.block(fromId)!) *
      _destinationFactor(edge, graph.block(toId)!);
}

Expr _sequentialGain(SignalGraph graph, List<String> nodes) {
  var gain = const ConstExpr(1) as Expr;
  for (var i = 0; i < nodes.length - 1; i++) {
    gain = gain * _edgeGain(graph, nodes[i], nodes[i + 1]);
  }
  return gain;
}

Expr _loopGain(SignalGraph graph, List<String> nodes) =>
    _sequentialGain(graph, nodes) * _edgeGain(graph, nodes.last, nodes.first);

/// Every simple (no repeated node) path from [from] to [to]. Small-graph
/// DFS with backtracking — more than adequate for the SFG sizes Mason's
/// method is used on in practice (a handful to a few dozen nodes); very
/// large or densely-connected graphs aren't specially guarded against.
List<List<String>> _findSimplePaths(SignalGraph graph, String from, String to) {
  final results = <List<String>>[];
  final visited = <String>{};
  final path = <String>[];

  void dfs(String current) {
    if (visited.contains(current)) return;
    visited.add(current);
    path.add(current);
    if (current == to) {
      results.add(List.of(path));
    } else {
      for (final edge in graph.edgesFrom(current)) {
        dfs(edge.toBlockId);
      }
    }
    path.removeLast();
    visited.remove(current);
  }

  dfs(from);
  return results;
}

/// Every simple cycle, each reported exactly once: canonicalized to start
/// at its lexicographically-smallest block id and only extend to larger
/// ids, so the same cycle isn't found once per rotation/starting point.
List<List<String>> _findSimpleLoops(SignalGraph graph) {
  final loops = <List<String>>[];
  final allIds = graph.blocks.keys.toList()..sort();

  for (final start in allIds) {
    final visited = <String>{start};
    final path = <String>[start];

    void dfs(String current) {
      for (final edge in graph.edgesFrom(current)) {
        final next = edge.toBlockId;
        if (next == start) {
          loops.add(List.of(path));
        } else if (next.compareTo(start) > 0 && !visited.contains(next)) {
          visited.add(next);
          path.add(next);
          dfs(next);
          path.removeLast();
          visited.remove(next);
        }
      }
    }

    dfs(start);
  }
  return loops;
}

/// `Δ = 1 - ΣL_i + Σ(non-touching pairs) - Σ(non-touching triples) + ...`
/// via subset enumeration over [loops], summed with alternating sign only
/// for subsets whose loops are pairwise node-disjoint ("non-touching").
Expr _determinant(List<Loop> loops) {
  final n = loops.length;
  if (n > 24) {
    throw StateError(
      'Mason\'s formula via subset enumeration does not scale past a few '
      'dozen independent loops ($n found); this diagram needs a different '
      'analysis method.',
    );
  }
  var det = const ConstExpr(1) as Expr;
  for (var mask = 1; mask < (1 << n); mask++) {
    final subset = [
      for (var i = 0; i < n; i++)
        if (mask & (1 << i) != 0) loops[i],
    ];
    if (!_mutuallyNonTouching(subset)) continue;
    var product = const ConstExpr(1) as Expr;
    for (final loop in subset) {
      product = product * loop.gain;
    }
    det = subset.length.isOdd ? det - product : det + product;
  }
  return det;
}

bool _mutuallyNonTouching(List<Loop> loops) {
  for (var i = 0; i < loops.length; i++) {
    final a = loops[i].blockIds.toSet();
    for (var j = i + 1; j < loops.length; j++) {
      if (a.intersection(loops[j].blockIds.toSet()).isNotEmpty) return false;
    }
  }
  return true;
}
