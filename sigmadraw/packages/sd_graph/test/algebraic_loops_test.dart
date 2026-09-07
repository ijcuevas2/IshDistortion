import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  test('no edges at all -> no loops', () {
    final graph = SignalGraph(blocks: {'a': block('a', 'gain')}, edges: []);
    expect(detectAlgebraicLoops(graph), isEmpty);
  });

  test('a self-loop with direct feedthrough is algebraic', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'gain', ports: [inPort('in1'), outPort('out1')]),
      },
      edges: [edge('e1', 'a:out1', 'a:in1')],
    );
    final loops = detectAlgebraicLoops(graph);
    expect(loops, hasLength(1));
    expect(loops.single.blockIds, ['a']);
  });

  test('a self-loop through a delay is not algebraic', () {
    final graph = SignalGraph(
      blocks: {
        'a': block(
          'a',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
      },
      edges: [edge('e1', 'a:out1', 'a:in1')],
    );
    expect(detectAlgebraicLoops(graph), isEmpty);
  });

  test('a 3-node feedthrough cycle is algebraic', () {
    final graph = SignalGraph(
      blocks: {
        for (final id in ['a', 'b', 'c'])
          id: block(id, 'gain', ports: [inPort('in1'), outPort('out1')]),
      },
      edges: [
        edge('e1', 'a:out1', 'b:in1'),
        edge('e2', 'b:out1', 'c:in1'),
        edge('e3', 'c:out1', 'a:in1'),
      ],
    );
    final loops = detectAlgebraicLoops(graph);
    expect(loops, hasLength(1));
    expect(loops.single.blockIds.toSet(), {'a', 'b', 'c'});
  });

  test('one delay anywhere in a longer cycle breaks it', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'b': block(
          'b',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
        'c': block('c', 'gain', ports: [inPort('in1'), outPort('out1')]),
      },
      edges: [
        edge('e1', 'a:out1', 'b:in1'),
        edge('e2', 'b:out1', 'c:in1'),
        edge('e3', 'c:out1', 'a:in1'),
      ],
    );
    expect(detectAlgebraicLoops(graph), isEmpty);
  });

  test('a feedforward diamond (no cycle at all) reports no loops', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block('b', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'c': block('c', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'd': block(
          'd',
          'adder',
          ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        ),
      },
      edges: [
        edge('e1', 'a:out1', 'b:in1'),
        edge('e2', 'a:out1', 'c:in1'),
        edge('e3', 'b:out1', 'd:in1'),
        edge('e4', 'c:out1', 'd:in2'),
      ],
    );
    expect(detectAlgebraicLoops(graph), isEmpty);
  });

  test('two independent algebraic loops are both reported', () {
    final graph = SignalGraph(
      blocks: {
        for (final id in ['a', 'b', 'c', 'd'])
          id: block(id, 'gain', ports: [inPort('in1'), outPort('out1')]),
      },
      edges: [
        edge('e1', 'a:out1', 'b:in1'),
        edge('e2', 'b:out1', 'a:in1'),
        edge('e3', 'c:out1', 'd:in1'),
        edge('e4', 'd:out1', 'c:in1'),
      ],
    );
    expect(detectAlgebraicLoops(graph), hasLength(2));
  });
}
