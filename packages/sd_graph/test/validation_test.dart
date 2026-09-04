import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

bool _hasError(List<ValidationIssue> issues, String substring) => issues.any(
  (i) => i.severity == Severity.error && i.message.contains(substring),
);

void main() {
  test('a fully-connected, type-matched graph has no errors', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block('b', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'a:out1', 'b:in1')],
    );
    final issues = validate(graph);
    expect(issues.where((i) => i.severity == Severity.error), isEmpty);
  });

  test('a dangling edge (missing block) is an error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
      },
      edges: [edge('e1', 'a:out1', 'ghost:in1')],
    );
    expect(_hasError(validate(graph), 'does not exist'), isTrue);
  });

  test('a dangling edge (missing port) is an error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block('b', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'a:out1', 'b:nope')],
    );
    expect(_hasError(validate(graph), 'does not exist'), isTrue);
  });

  test('narrowing complex -> real is a type-mismatch error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block(
          'a',
          'source',
          ports: [
            outPort('out1', dataType: const DataType(ScalarType.complex)),
          ],
        ),
        'b': block('b', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'a:out1', 'b:in1')],
    );
    expect(_hasError(validate(graph), 'Type mismatch'), isTrue);
  });

  test('widening real -> complex is not an error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block(
          'b',
          'sink',
          ports: [inPort('in1', dataType: const DataType(ScalarType.complex))],
        ),
      },
      edges: [edge('e1', 'a:out1', 'b:in1')],
    );
    expect(validate(graph).where((i) => i.severity == Severity.error), isEmpty);
  });

  test('mismatched vlen is an error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1', vlen: 4)]),
        'b': block('b', 'sink', ports: [inPort('in1', vlen: 1)]),
      },
      edges: [edge('e1', 'a:out1', 'b:in1')],
    );
    expect(_hasError(validate(graph), 'vlen mismatch'), isTrue);
  });

  test('two edges into the same input port is an unsupported-arity error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block('b', 'source', ports: [outPort('out1')]),
        'c': block('c', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'a:out1', 'c:in1'), edge('e2', 'b:out1', 'c:in1')],
    );
    expect(_hasError(validate(graph), 'at most one'), isTrue);
  });

  test('an unconnected port is a (non-error) warning', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'sink', ports: [inPort('in1')]),
      },
      edges: [],
    );
    final issues = validate(graph);
    expect(issues.single.severity, Severity.warning);
    expect(issues.single.message, contains('Unconnected'));
  });

  test('a delay-free feedback loop is reported as an error', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'b': block('b', 'gain', ports: [inPort('in1'), outPort('out1')]),
      },
      edges: [edge('e1', 'a:out1', 'b:in1'), edge('e2', 'b:out1', 'a:in1')],
    );
    expect(_hasError(validate(graph), 'Algebraic'), isTrue);
  });

  test('the same loop with a delay in it is not reported', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'b': block(
          'b',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
      },
      edges: [edge('e1', 'a:out1', 'b:in1'), edge('e2', 'b:out1', 'a:in1')],
    );
    expect(_hasError(validate(graph), 'Algebraic'), isFalse);
  });
}
