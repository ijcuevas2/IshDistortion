import 'block.dart';
import 'signal_graph.dart';
import 'types.dart';
import 'validation.dart';

/// Propagates sample rate forward from every graph-theoretic source block
/// (no incoming edges) — §4: "from sources, ×L at upsamplers, /M at
/// downsamplers; flag inconsistencies". `rates[id]` is that block's own
/// *resolved/output* rate (a plain block passes its input rate through
/// unchanged; an upsampler/downsampler transforms it) — so a chain
/// `source -> upsampler(L=2) -> downsampler(M=2)` correctly reports `2*Fs`
/// for the upsampler and back to `Fs` for the downsampler.
///
/// A block only reachable exclusively through a feedback loop (no
/// acyclic path from any source) is left unresolved rather than flagged —
/// a well-formed diagram always has its loop's rate fixed by the adder
/// where the loop rejoins the forward path from an actual source (see the
/// biquad DF2T test in `mason_test.dart`), so this is a deliberately
/// narrow, documented gap rather than a missed case in practice.
({Map<String, SampleRate> rates, List<ValidationIssue> issues}) propagateRates(
  SignalGraph graph, {
  SampleRate baseRate = const SampleRate(baseSymbol: 'Fs'),
}) {
  final rates = <String, SampleRate>{};
  final issues = <ValidationIssue>[];
  final queue = <String>[];

  SampleRate resolvedRate(Block block, SampleRate incoming) =>
      switch (block.type) {
        'upsampler' => incoming.scaledBy((block.params['L'] as num?) ?? 2),
        'downsampler' => incoming.dividedBy((block.params['M'] as num?) ?? 2),
        _ => incoming,
      };

  for (final block in graph.blocks.values) {
    if (graph.edgesTo(block.id).isEmpty) {
      rates[block.id] = resolvedRate(block, baseRate);
      queue.add(block.id);
    }
  }

  while (queue.isNotEmpty) {
    final currentId = queue.removeAt(0);
    final currentOutRate = rates[currentId]!;

    for (final edge in graph.edgesFrom(currentId)) {
      final targetBlock = graph.block(edge.toBlockId)!;
      final candidateRate = resolvedRate(targetBlock, currentOutRate);
      final existing = rates[edge.toBlockId];
      if (existing == null) {
        rates[edge.toBlockId] = candidateRate;
        queue.add(edge.toBlockId);
      } else if (!existing.isCompatibleWith(candidateRate)) {
        issues.add(
          ValidationIssue(
            severity: Severity.error,
            message:
                'Sample-rate conflict at ${edge.toBlockId}: $existing vs $candidateRate.',
            blockId: edge.toBlockId,
          ),
        );
      }
    }
  }

  return (rates: rates, issues: issues);
}
