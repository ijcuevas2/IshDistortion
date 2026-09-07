import 'algebraic_loops.dart';
import 'port.dart';
import 'signal_graph.dart';

enum Severity { info, warning, error }

class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.message,
    this.blockId,
    this.edgeId,
    this.portId,
  });

  final Severity severity;
  final String message;
  final String? blockId;
  final String? edgeId;
  final String? portId;

  @override
  String toString() => '[${severity.name}] $message';
}

/// Runs every §4 validation rule against [graph] — the model behind the
/// Problems panel (§10): unconnected required ports, dangling edges, type/
/// vlen/sample-rate mismatches, delay-free (algebraic) loops, and
/// unsupported arity (more than one edge feeding the same input port).
List<ValidationIssue> validate(SignalGraph graph) {
  final issues = <ValidationIssue>[];

  for (final edge in graph.edges) {
    final fromBlock = graph.block(edge.fromBlockId);
    final toBlock = graph.block(edge.toBlockId);
    if (fromBlock == null || toBlock == null) {
      issues.add(
        ValidationIssue(
          severity: Severity.error,
          message: 'Edge ${edge.id} references a block that does not exist.',
          edgeId: edge.id,
        ),
      );
      continue;
    }
    final fromPort = fromBlock.portById(edge.fromPortId);
    final toPort = toBlock.portById(edge.toPortId);
    if (fromPort == null || toPort == null) {
      issues.add(
        ValidationIssue(
          severity: Severity.error,
          message: 'Edge ${edge.id} references a port that does not exist.',
          edgeId: edge.id,
        ),
      );
      continue;
    }

    if (!fromPort.dataType.isCompatibleWith(toPort.dataType)) {
      issues.add(
        ValidationIssue(
          severity: Severity.error,
          message:
              'Type mismatch on ${edge.id}: ${fromPort.dataType} cannot flow into '
              '${toPort.dataType} (narrowing is never implicit).',
          edgeId: edge.id,
        ),
      );
    }
    if (fromPort.vlen != toPort.vlen) {
      issues.add(
        ValidationIssue(
          severity: Severity.error,
          message:
              'vlen mismatch on ${edge.id}: ${fromPort.vlen} != ${toPort.vlen}.',
          edgeId: edge.id,
        ),
      );
    }
    final fromRate = fromPort.sampleRate;
    final toRate = toPort.sampleRate;
    if (fromRate != null &&
        toRate != null &&
        !fromRate.isCompatibleWith(toRate)) {
      issues.add(
        ValidationIssue(
          severity: Severity.warning,
          message: 'Sample-rate mismatch on ${edge.id}: $fromRate != $toRate.',
          edgeId: edge.id,
        ),
      );
    }
  }

  // Unsupported arity: more than one edge feeding the same input port.
  final inboundCounts = <String, int>{};
  for (final edge in graph.edges) {
    inboundCounts.update(
      '${edge.toBlockId}:${edge.toPortId}',
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  for (final entry in inboundCounts.entries) {
    if (entry.value > 1) {
      final parts = entry.key.split(':');
      issues.add(
        ValidationIssue(
          severity: Severity.error,
          message:
              'Port ${entry.key} has ${entry.value} incoming edges; an input port accepts at most one.',
          blockId: parts[0],
          portId: parts[1],
        ),
      );
    }
  }

  // Unconnected (required) ports: every declared port is required, since
  // §4's Port model has no separate "optional" flag yet.
  for (final block in graph.blocks.values) {
    for (final port in block.ports) {
      final connected = port.direction == PortDirection.input
          ? graph.edgesTo(block.id, port.id).isNotEmpty
          : graph.edgesFrom(block.id, port.id).isNotEmpty;
      if (!connected) {
        issues.add(
          ValidationIssue(
            severity: Severity.warning,
            message: 'Unconnected port ${block.id}:${port.id}.',
            blockId: block.id,
            portId: port.id,
          ),
        );
      }
    }
  }

  for (final loop in detectAlgebraicLoops(graph)) {
    issues.add(
      ValidationIssue(
        severity: Severity.error,
        message:
            'Algebraic (delay-free) loop through blocks: ${loop.blockIds.join(' -> ')}.',
        blockId: loop.blockIds.first,
      ),
    );
  }

  return issues;
}
