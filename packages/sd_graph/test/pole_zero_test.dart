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
    // buildBiquadGraph (test_helpers.dart) is the same topology as
    // mason_test.dart's §13 acceptance case — see that file for the
    // by-hand derivation of H(z) itself. Here the coefficients are
    // chosen so the pole/zero locations are also hand-derivable:
    // denominator z^2 - 0.6z + 0.25 has roots 0.3 +- 0.4i (quadratic
    // formula: (0.6 +- sqrt(0.36-1))/2 = (0.6 +- 0.8i)/2), both with
    // |z| = 0.5 < 1 (a stable filter). Numerator z^2 - 1 (b0=1, b1=0,
    // b2=-1) has roots +-1 — deliberately *not* b1=0.5, b2=0: see
    // buildBiquadGraph's own doc comment on why a zero *coefficient*
    // isn't safe to use for anchoring a polynomial's degree here; found
    // by a test that assumed the degree-2 shape and got only one root
    // back.
    test('poles match the hand-derived quadratic-formula roots', () {
      final graph = buildBiquadGraph(b0: 1, b1: 0, b2: -1, a1: -0.6, a2: 0.25);
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
      final graph = buildBiquadGraph(b0: 1, b1: 0, b2: -1, a1: -0.6, a2: 0.25);
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
        final graph = buildBiquadGraph(
          b0: 1,
          b1: 0,
          b2: -1,
          a1: -0.6,
          a2: 0.25,
        );
        final h = computeTransferFunction(graph)!.h;
        final result = computePoleZero(h)!;
        for (final pole in result.poles) {
          expect(pole.abs(), lessThan(1));
        }
      },
    );

    test('returns null when a coefficient is still an unbound symbol', () {
      final graph = buildBiquadGraph(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0);
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

    test('returns null (not a thrown ArgumentError) when a bound gain '
        'makes H(z) identically zero', () {
      // Found via RootLocusPanel's own test sweeping a gain from 0 to 2:
      // at exactly k=0, H(z)=k becomes the single-term "polynomial" {0:
      // 0} — its own "leading" coefficient is 0, which
      // findPolynomialRoots correctly refuses to treat as a genuine
      // degree-0 polynomial. A finite pole/zero list isn't a meaningful
      // answer for H(z)=0 everywhere anyway, so null (the same outcome
      // an unbound symbol produces) is the right answer, not a crash.
      final graph = SignalGraph(
        blocks: {
          'src': block('src', 'source', ports: [outPort('out1')]),
          'g': block(
            'g',
            'gain',
            ports: [inPort('in1'), outPort('out1')],
            params: {'gain': 'k'},
          ),
          'snk': block('snk', 'sink', ports: [inPort('in1')]),
        },
        edges: [
          edge('e1', 'src:out1', 'g:in1'),
          edge('e2', 'g:out1', 'snk:in1'),
        ],
      );
      final h = computeTransferFunction(graph)!.h;
      expect(computePoleZero(h, bindings: {'k': 0}), isNull);
      // A nonzero binding still works normally.
      expect(computePoleZero(h, bindings: {'k': 3.5}), isNotNull);
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

  group('computeRootLocus', () {
    test('rejects fewer than 2 points', () {
      expect(
        () => computeRootLocus(
          const ConstExpr(1),
          parameter: 'k',
          start: 0,
          end: 1,
          pointCount: 1,
        ),
        throwsArgumentError,
      );
    });

    test('a single real pole migrates exactly along the sweep, for '
        'H(z) = 1 / (1 + k*z^-1) -> pole at z = -k', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      final samples = computeRootLocus(
        h,
        parameter: 'k',
        start: 0.2,
        end: 0.8,
        pointCount: 4,
      )!;
      expect(samples, hasLength(4));
      for (final s in samples) {
        expect(s.poles, hasLength(1));
        expect(s.poles.single.re, closeTo(-s.parameterValue, 1e-9));
        expect(s.poles.single.im, closeTo(0, 1e-9));
      }
      expect(samples.first.parameterValue, closeTo(0.2, 1e-12));
      expect(samples.last.parameterValue, closeTo(0.8, 1e-12));
    });

    test('sweeps evenly from start to end, inclusive', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      final samples = computeRootLocus(
        h,
        parameter: 'k',
        start: -1,
        end: 1,
        pointCount: 5,
      )!;
      expect(samples.map((s) => s.parameterValue), [-1, -0.5, 0, 0.5, 1]);
    });

    test('resolves other, already-bound symbols too, alongside the '
        'swept one', () {
      // H(z) = g / (1 + k*z^-1): g is bound directly, k is swept.
      final h = divExpr(
        const SymbolExpr('g'),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      final samples = computeRootLocus(
        h,
        parameter: 'k',
        start: 0.1,
        end: 0.3,
        bindings: {'g': 5},
        pointCount: 3,
      )!;
      for (final s in samples) {
        expect(s.zeros, isEmpty); // constant numerator -> no zeros.
        expect(s.poles.single.re, closeTo(-s.parameterValue, 1e-9));
      }
    });

    test('returns null if a different, still-unbound symbol remains', () {
      final h = divExpr(
        const SymbolExpr('g'), // left unbound, unlike the test above.
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      expect(computeRootLocus(h, parameter: 'k', start: 0, end: 1), isNull);
    });

    test('skips one individually-degenerate swept value rather than '
        'blanking out the whole sweep — H(z) = k is identically zero '
        'only at exactly k=0', () {
      const h = SymbolExpr('k');
      final samples = computeRootLocus(
        h,
        parameter: 'k',
        start: -1,
        end: 1,
        pointCount: 5, // values: -1, -0.5, 0, 0.5, 1.
      )!;
      // 4 of the 5 swept values survive; only k=0 (H(z)=0 there) is
      // skipped — not all 5, and not none.
      expect(samples, hasLength(4));
      expect(samples.map((s) => s.parameterValue), isNot(contains(0)));
      expect(
        samples.map((s) => s.parameterValue),
        containsAll([-1, -0.5, 0.5, 1]),
      );
    });

    test('returns null (not an empty list) when every single swept value '
        'is individually degenerate', () {
      // H(z) = k * 0 = 0 for every k -- there is no value of k at all
      // that gives a non-degenerate H(z) here (deliberately, to
      // distinguish "returns null" from "returns an empty list" as the
      // right answer when literally nothing in the sweep worked).
      final h = mulExpr([const SymbolExpr('k'), const ConstExpr(0)]);
      expect(computeRootLocus(h, parameter: 'k', start: -1, end: 1), isNull);
    });
  });
}
