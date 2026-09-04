import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  SignalGraph sampleGraph() => SignalGraph(
    blocks: {
      'src': block('src', 'source', ports: [outPort('out1')]),
      'g': block(
        'g',
        'gain',
        ports: [inPort('in1'), outPort('out1')],
        params: {'gain': 2.0},
      ),
    },
    edges: [edge('e1', 'src:out1', 'g:in1')],
  );

  test('toNetlistMap includes every block and connection', () {
    final map = toNetlistMap(sampleGraph());
    final blocks = map['blocks']! as List;
    expect(blocks, hasLength(2));
    expect(blocks.map((b) => (b as Map)['id']), containsAll(['src', 'g']));
    expect(map['connections'], [
      ['src', 'out1', 'g', 'in1'],
    ]);
  });

  test('toNetlistJson round-trips through jsonDecode to the same shape', () {
    final json = toNetlistJson(sampleGraph());
    expect(json, contains('"blocks"'));
    expect(json, contains('"connections"'));
  });

  test(
    'toNetlistYaml emits a parseable-looking blocks/connections document',
    () {
      final yaml = toNetlistYaml(sampleGraph());
      expect(yaml, contains('blocks:'));
      expect(yaml, contains('- id: src'));
      expect(yaml, contains('type: gain'));
      expect(yaml, contains('connections:'));
      expect(yaml, contains('- [src, out1, g, in1]'));
    },
  );

  test(
    'toDot emits one node statement per block and one edge per connection',
    () {
      final dot = toDot(sampleGraph());
      expect(dot, startsWith('digraph SignalGraph {'));
      expect(dot, contains('"src" [label="source"];'));
      expect(dot, contains('"src" -> "g"'));
    },
  );
}
