import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('findPolynomialRoots', () {
    void expectHasRootNear(List<Complex> roots, Complex expected) {
      final match = roots.where((r) => (r - expected).abs() < 1e-6);
      expect(
        match,
        isNotEmpty,
        reason: 'expected a root near $expected in $roots',
      );
    }

    test('three known real roots: (z-2)(z-3)(z+1) = z^3 - 4z^2 + z + 6', () {
      final roots = findPolynomialRoots([1, -4, 1, 6]);
      expect(roots, hasLength(3));
      expectHasRootNear(roots, const Complex(2));
      expectHasRootNear(roots, const Complex(3));
      expectHasRootNear(roots, const Complex(-1));
    });

    test('a complex-conjugate pair: z^2 + 1 has roots +-i', () {
      final roots = findPolynomialRoots([1, 0, 1]);
      expect(roots, hasLength(2));
      expectHasRootNear(roots, const Complex(0, 1));
      expectHasRootNear(roots, const Complex(0, -1));
    });

    test('a degree-0 (constant) polynomial has no roots', () {
      expect(findPolynomialRoots([5]), isEmpty);
    });

    test('a non-monic polynomial is handled the same as its monic form', () {
      // 2*(z-2)(z-3) = 2z^2 - 10z + 12
      final roots = findPolynomialRoots([2, -10, 12]);
      expect(roots, hasLength(2));
      expectHasRootNear(roots, const Complex(2));
      expectHasRootNear(roots, const Complex(3));
    });

    test('rejects an empty coefficient list', () {
      expect(() => findPolynomialRoots([]), throwsArgumentError);
    });

    test('rejects a zero leading coefficient', () {
      expect(() => findPolynomialRoots([0, 1, 2]), throwsArgumentError);
    });
  });

  group('rationalPolynomials', () {
    test('a bare constant is numerator {0: v} over denominator {0: 1}', () {
      final result = rationalPolynomials(const ConstExpr(2.5), const {});
      expect(result!.numerator, {0: 2.5});
      expect(result.denominator, {0: 1});
    });

    test('a DivExpr splits into its own numerator/denominator', () {
      // 1 / (1 + a1*z^-1) — the SymbolExpr alone (with no ZPowExpr
      // factor) would just be a plain coefficient at z^-0, not a z^-1
      // term, so the mulExpr wrapping here is what actually puts it at
      // power 1.
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('a1'), const ZPowExpr(-1)]),
        ]),
      );
      final result = rationalPolynomials(h, {'a1': -0.5});
      expect(result!.numerator, {0: 1});
      expect(result.denominator, {0: 1, 1: -0.5});
    });

    test('an unbound symbol makes the result null', () {
      final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
      expect(rationalPolynomials(h, const {}), isNull);
    });
  });

  group('computePoleZero (biquad Direct Form II Transposed)', () {
    // The same topology as mason_test.dart's §13 acceptance case — see
    // that file for the by-hand derivation of H(z) itself. Here the
    // coefficients are chosen so the pole/zero locations are also
    // hand-derivable: denominator z^2 - 0.6z + 0.25 has roots
    // 0.3 +- 0.4i (quadratic formula: (0.6 +- sqrt(0.36-1))/2 =
    // (0.6 +- 0.8i)/2), both with |z| = 0.5 < 1 (a stable filter).
    // Numerator z^2 - 1 (b0=1, b1=0, b2=-1) has roots +-1 — deliberately
    // *not* b1=0.5, b2=0: a zero *coefficient* still leaves that term's
    // z-power present in the polynomial, but Mason's own gain
    // multiplication collapses a forward path's gain of exactly 0 (as
    // b2=0 would be) to a bare ConstExpr(0) with no trace of its z^-2
    // factor at all — genuinely dropping the numerator to degree 1, not
    // degree 2 with a zero leading coefficient. b1=0 doesn't have this
    // problem since b2's own (nonzero) term still anchors the numerator
    // at degree 2 either way; found by a test that assumed the
    // degree-2 shape and got only one root back.
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

    test('poles match the hand-derived quadratic-formula roots', () {
      final graph = buildBiquad(b0: 1, b1: 0, b2: -1, a1: -0.6, a2: 0.25);
      final h = computeTransferFunction(graph)!.h;
      final result = computePoleZero(h)!;

      expect(result.poles, hasLength(2));
      final expectedPoles = [const Complex(0.3, 0.4), const Complex(0.3, -0.4)];
      for (final expected in expectedPoles) {
        expect(
          result.poles.any((p) => (p - expected).abs() < 1e-6),
          isTrue,
          reason: 'expected a pole near $expected in ${result.poles}',
        );
      }
    });

    test('zeros match the hand-derived roots (z = +-1)', () {
      final graph = buildBiquad(b0: 1, b1: 0, b2: -1, a1: -0.6, a2: 0.25);
      final h = computeTransferFunction(graph)!.h;
      final result = computePoleZero(h)!;

      expect(result.zeros, hasLength(2));
      for (final expected in [const Complex(1), const Complex(-1)]) {
        expect(
          result.zeros.any((z) => (z - expected).abs() < 1e-6),
          isTrue,
          reason: 'expected a zero near $expected in ${result.zeros}',
        );
      }
    });

    test(
      'every pole is strictly inside the unit circle for this stable filter',
      () {
        final graph = buildBiquad(b0: 1, b1: 0, b2: -1, a1: -0.6, a2: 0.25);
        final h = computeTransferFunction(graph)!.h;
        final result = computePoleZero(h)!;
        for (final pole in result.poles) {
          expect(pole.abs(), lessThan(1));
        }
      },
    );

    test('returns null when a coefficient is still an unbound symbol', () {
      final graph = buildBiquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0);
      final symbolic = SignalGraph(
        blocks: graph.blocks.map(
          (id, b) => MapEntry(
            id,
            b.type == 'gain' && id == 'na1'
                ? Block(
                    id: b.id,
                    type: b.type,
                    ports: b.ports,
                    params: {'gain': 'k'},
                  )
                : b,
          ),
        ),
        edges: graph.edges,
      );
      final h = computeTransferFunction(symbolic)!.h;
      expect(computePoleZero(h), isNull);
      // But binding that same symbol makes it work again.
      expect(computePoleZero(h, bindings: {'k': -0.6}), isNotNull);
    });

    test('a pure feedforward (gain-only) H(z) has no poles or zeros', () {
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
        edges: [
          edge('e1', 'src:out1', 'g:in1'),
          edge('e2', 'g:out1', 'snk:in1'),
        ],
      );
      final h = computeTransferFunction(graph)!.h;
      final result = computePoleZero(h)!;
      expect(result.poles, isEmpty);
      expect(result.zeros, isEmpty);
    });

    test('a bare z^-1 (source -> delay -> sink) is a single pole at the origin, no zeros', () {
      // H(z) is exactly `ZPowExpr(-1)` here — not wrapped in a DivExpr
      // at all, since divExpr's own smart constructor collapses a
      // denominator of exactly 1 away. Every forward path passing
      // through a delay (there's only one path, and it's entirely a
      // delay) means the numerator has no z^-0 term whatsoever, which
      // is exactly the "gap" case that made an earlier version of
      // _clearedZPolynomial throw ArgumentError instead of returning a
      // real single pole at z=0.
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
        edges: [
          edge('e1', 'src:out1', 'd:in1'),
          edge('e2', 'd:out1', 'snk:in1'),
        ],
      );
      final h = computeTransferFunction(graph)!.h;
      final result = computePoleZero(h)!;
      expect(result.zeros, isEmpty);
      expect(result.poles, hasLength(1));
      expect(result.poles.single.abs(), closeTo(0, 1e-9));
    });
  });
}
