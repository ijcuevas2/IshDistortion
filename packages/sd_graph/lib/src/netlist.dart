import 'dart:convert';

import 'signal_graph.dart';

/// A GNU-Radio-`.grc`-style netlist as a plain map (§4): a `blocks` list
/// (id/type/label/parameters/ports) and a `connections` list of
/// `[fromBlock, fromPort, toBlock, toPort]` tuples.
Map<String, Object?> toNetlistMap(SignalGraph graph) => {
  'blocks': [
    for (final block in graph.blocks.values)
      {
        'id': block.id,
        'type': block.type,
        if (block.label != null) 'label': block.label,
        'parameters': block.params,
        'ports': [
          for (final port in block.ports)
            {
              'id': port.id,
              'direction': port.direction.name,
              'dtype': port.dataType.toString(),
              'vlen': port.vlen,
            },
        ],
      },
  ],
  'connections': [
    for (final edge in graph.edges)
      [edge.fromBlockId, edge.fromPortId, edge.toBlockId, edge.toPortId],
  ],
};

String toNetlistJson(SignalGraph graph) =>
    const JsonEncoder.withIndent('  ').convert(toNetlistMap(graph));

/// The same netlist, hand-emitted as YAML (no YAML-writer dependency
/// needed for a shape this simple — see [_yamlScalar]).
String toNetlistYaml(SignalGraph graph) {
  final buffer = StringBuffer()..writeln('blocks:');
  for (final block in graph.blocks.values) {
    buffer
      ..writeln('  - id: ${block.id}')
      ..writeln('    type: ${block.type}');
    if (block.label != null) {
      buffer.writeln('    label: ${_yamlScalar(block.label)}');
    }
    if (block.params.isNotEmpty) {
      buffer.writeln('    parameters:');
      for (final entry in block.params.entries) {
        buffer.writeln('      ${entry.key}: ${_yamlScalar(entry.value)}');
      }
    }
  }
  buffer.writeln('connections:');
  for (final edge in graph.edges) {
    buffer.writeln(
      '  - [${edge.fromBlockId}, ${edge.fromPortId}, ${edge.toBlockId}, ${edge.toPortId}]',
    );
  }
  return buffer.toString();
}

String _yamlScalar(Object? value) {
  if (value is String) {
    final needsQuoting =
        value.isEmpty ||
        RegExp(r'''^[\s\-\[\]{}:#&*!|>'"%@`,]''').hasMatch(value) ||
        value.contains(': ');
    return needsQuoting ? '"${value.replaceAll('"', '\\"')}"' : value;
  }
  if (value is List) return '[${value.map(_yamlScalar).join(', ')}]';
  return '$value';
}

/// A Graphviz DOT rendering of [graph] — §4's optional netlist companion.
String toDot(SignalGraph graph) {
  final buffer = StringBuffer('digraph SignalGraph {\n');
  for (final block in graph.blocks.values) {
    final label = block.label != null
        ? '${block.type}\\n"${block.label}"'
        : block.type;
    buffer.writeln('  "${block.id}" [label="$label"];');
  }
  for (final edge in graph.edges) {
    buffer.writeln(
      '  "${edge.fromBlockId}" -> "${edge.toBlockId}" [label="${edge.fromPortId}->${edge.toPortId}"];',
    );
  }
  buffer.writeln('}');
  return buffer.toString();
}
