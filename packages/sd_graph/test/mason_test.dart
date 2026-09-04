import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  test('a straight source -> gain -> sink path has H = gain', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'g': block(
          'g',
          'gain',
          ports: [inPort('in1'), outPort('out1')],
          params: {'gain': 3.5},
        ),
        'snk': block('snk', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'src:out1', 'g:in1'), edge('e2', 'g:out1', 'snk:in1')],
    );
    final result = computeTransferFunction(graph)!;
    expect(result.h.evaluate({}, z: 1), 3.5);
    expect(result.h.evaluate({}, z: 100), 3.5); // no z-dependence at all
  });

  test('a straight source -> delay -> sink path has H = z^-1', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'd': block(
          'd',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
        'snk': block('snk', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'src:out1', 'd:in1'), edge('e2', 'd:out1', 'snk:in1')],
    );
    final result = computeTransferFunction(graph)!;
    expect(result.h.evaluate({}, z: 2), 0.5);
    expect(result.h.evaluate({}, z: 4), 0.25);
  });

  test('an adder with a "-" sign subtracts that input', () {
    final graph = SignalGraph(
      blocks: {
        'a': block('a', 'source', ports: [outPort('out1')]),
        'b': block('b', 'source', ports: [outPort('out1')]),
        'sum': block(
          'sum',
          'adder',
          ports: [inPort('in1'), inPort('in2'), outPort('out1')],
          params: {
            'signs': ['+', '-'],
          },
        ),
        'snk': block('snk', 'sink', ports: [inPort('in1')]),
      },
      edges: [
        edge('e1', 'a:out1', 'sum:in1'),
        edge('e2', 'b:out1', 'sum:in2'),
        edge('e3', 'sum:out1', 'snk:in1'),
      ],
    );
    // H from 'a' to sink is +1; H from 'b' to sink is -1. Check both by
    // asking for the transfer function with each as the explicit source.
    final fromA = computeTransferFunction(
      graph,
      sourceBlockId: 'a',
      sinkBlockId: 'snk',
    )!;
    final fromB = computeTransferFunction(
      graph,
      sourceBlockId: 'b',
      sinkBlockId: 'snk',
    )!;
    expect(fromA.h.evaluate({}, z: 1), 1);
    expect(fromB.h.evaluate({}, z: 1), -1);
  });

  test('two independent (non-touching) first-order feedback loops multiply in the denominator', () {
    // src -> s1 -(+feedback via ga,d_a)-> s2 -(+feedback via gb,d_b)-> sink.
    // Analytically: H = 1 / ((1 - ga*z^-1)(1 - gb*z^-1))
    //             = 1 / (1 - ga*z^-1 - gb*z^-1 + ga*gb*z^-2).
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        's1': block(
          's1',
          'adder',
          ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        ),
        'ga': block(
          'ga',
          'gain',
          ports: [inPort('in1'), outPort('out1')],
          params: {'gain': 0.5},
        ),
        'd_a': block(
          'd_a',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
        's2': block(
          's2',
          'adder',
          ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        ),
        'gb': block(
          'gb',
          'gain',
          ports: [inPort('in1'), outPort('out1')],
          params: {'gain': 0.25},
        ),
        'd_b': block(
          'd_b',
          'delay',
          ports: [inPort('in1'), outPort('out1')],
          directFeedthrough: false,
        ),
        'snk': block('snk', 'sink', ports: [inPort('in1')]),
      },
      edges: [
        edge('e1', 'src:out1', 's1:in1'),
        edge('e2', 'd_a:out1', 's1:in2'),
        edge('e3', 's1:out1', 'ga:in1'),
        edge('e4', 'ga:out1', 'd_a:in1'),
        edge('e5', 's1:out1', 's2:in1'),
        edge('e6', 'd_b:out1', 's2:in2'),
        edge('e7', 's2:out1', 'gb:in1'),
        edge('e8', 'gb:out1', 'd_b:in1'),
        edge('e9', 's2:out1', 'snk:in1'),
      ],
    );

    final result = computeTransferFunction(graph)!;
    expect(result.loops, hasLength(2));

    num expected(num z) => 1 / ((1 - 0.5 / z) * (1 - 0.25 / z));
    for (final z in [2.0, 5.0, 10.0, -3.0]) {
      expect(result.h.evaluate({}, z: z), closeTo(expected(z), 1e-9));
    }
  });

  test(
    'computeTransferFunction returns null with no identifiable source/sink',
    () {
      final graph = SignalGraph(blocks: {'a': block('a', 'gain')}, edges: []);
      expect(computeTransferFunction(graph), isNull);
    },
  );

  group('biquad Direct Form II Transposed — the §13 acceptance case', () {
    // y[n]  = b0*x[n] + w1[n-1]
    // w1[n] = b1*x[n] + w2[n-1] - a1*y[n]
    // w2[n] = b2*x[n] - a2*y[n]
    // => H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
    // (sign convention fixed by wiring the a1/a2 feedback through a '-'
    // adder input, verified against this same graph by hand in the
    // implementation notes — see mason.dart).
    SignalGraph buildBiquad({
      required num b0,
      required num b1,
      required num b2,
      required num a1,
      required num a2,
    }) {
      Block gainBlock(String id, num gain) => block(
        id,
        'gain',
        ports: [inPort('in1'), outPort('out1')],
        params: {'gain': gain},
      );
      Block delayBlock(String id) => block(
        id,
        'delay',
        ports: [inPort('in1'), outPort('out1')],
        directFeedthrough: false,
      );
      Block adderBlock(String id, List<String> signs) => block(
        id,
        'adder',
        ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        params: {'signs': signs},
      );

      return SignalGraph(
        blocks: {
          'src': block('src', 'source', ports: [outPort('out1')]),
          'snk': block('snk', 'sink', ports: [inPort('in1')]),
          'b0': gainBlock('b0', b0),
          'b1': gainBlock('b1', b1),
          'b2': gainBlock('b2', b2),
          'na1': gainBlock('na1', a1),
          'na2': gainBlock('na2', a2),
          'd1': delayBlock('d1'),
          'd2': delayBlock('d2'),
          'addY': adderBlock('addY', ['+', '+']),
          'addA': adderBlock('addA', ['+', '+']),
          'addB': adderBlock('addB', ['+', '-']),
          'addC': adderBlock('addC', ['+', '-']),
        },
        edges: [
          edge('e1', 'src:out1', 'b0:in1'),
          edge('e2', 'src:out1', 'b1:in1'),
          edge('e3', 'src:out1', 'b2:in1'),
          edge('e4', 'b0:out1', 'addY:in1'),
          edge('e5', 'd1:out1', 'addY:in2'),
          edge('e6', 'addY:out1', 'snk:in1'),
          edge('e7', 'addY:out1', 'na1:in1'),
          edge('e8', 'addY:out1', 'na2:in1'),
          edge('e9', 'b1:out1', 'addA:in1'),
          edge('e10', 'd2:out1', 'addA:in2'),
          edge('e11', 'addA:out1', 'addB:in1'),
          edge('e12', 'na1:out1', 'addB:in2'),
          edge('e13', 'addB:out1', 'd1:in1'),
          edge('e14', 'b2:out1', 'addC:in1'),
          edge('e15', 'na2:out1', 'addC:in2'),
          edge('e16', 'addC:out1', 'd2:in1'),
        ],
      );
    }

    test('validates with no algebraic loop', () {
      final graph = buildBiquad(b0: 1, b1: 0.5, b2: 0.25, a1: -0.3, a2: 0.1);
      expect(detectAlgebraicLoops(graph), isEmpty);
      expect(
        validate(graph).where((i) => i.severity == Severity.error),
        isEmpty,
      );
    });

    test('Mason yields the textbook-correct H(z)', () {
      const b0 = 1.0, b1 = 0.6, b2 = -0.2, a1 = -0.7, a2 = 0.15;
      final graph = buildBiquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2);

      final result = computeTransferFunction(graph)!;
      expect(result.forwardPaths, hasLength(3));

      num expected(num z) {
        final zInv = 1 / z;
        return (b0 + b1 * zInv + b2 * zInv * zInv) /
            (1 + a1 * zInv + a2 * zInv * zInv);
      }

      for (final z in [2.0, 0.5, 10.0, -4.0, 3.3]) {
        expect(result.h.evaluate({}, z: z), closeTo(expected(z), 1e-9));
      }
    });

    test(
      'yields the correct H(z) with symbolic (unbound) coefficients too',
      () {
        // Same structure, but coefficients are named parameters rather than
        // numbers — evaluate() must resolve them via bindings.
        final graph = buildBiquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0);
        // Rebuild with symbolic params for the coefficients that matter.
        final symbolic = SignalGraph(
          blocks: {
            for (final entry in graph.blocks.entries)
              entry.key: entry.value.type == 'gain' && entry.key != 'b0'
                  ? Block(
                      id: entry.value.id,
                      type: entry.value.type,
                      ports: entry.value.ports,
                      params: {'gain': entry.key},
                      directFeedthrough: entry.value.directFeedthrough,
                    )
                  : entry.value,
          },
          edges: graph.edges,
        );

        final result = computeTransferFunction(symbolic)!;
        final bindings = {'b1': 0.6, 'b2': -0.2, 'na1': -0.7, 'na2': 0.15};
        num expected(num z) {
          final zInv = 1 / z;
          return (1 + bindings['b1']! * zInv + bindings['b2']! * zInv * zInv) /
              (1 + bindings['na1']! * zInv + bindings['na2']! * zInv * zInv);
        }

        for (final z in [2.0, 5.0]) {
          expect(result.h.evaluate(bindings, z: z), closeTo(expected(z), 1e-9));
        }
      },
    );
  });
}
