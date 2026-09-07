import 'dart:math' as math;

import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('computeNyquistPlot', () {
    test('rejects fewer than 2 points', () {
      expect(
        () => computeNyquistPlot(const ConstExpr(1), pointCount: 1),
        throwsArgumentError,
      );
    });

    test('a pure real gain is a single point, repeated at every omega', () {
      final points = computeNyquistPlot(const ConstExpr(4), pointCount: 20)!;
      for (final p in points) {
        expect(p.re, closeTo(4, 1e-9));
        expect(p.im, closeTo(0, 1e-9));
      }
    });

    test('a pure unit delay traces the unit circle exactly', () {
      // H(z) = z^-1 => H(e^jw) = e^-jw, magnitude exactly 1 at every
      // frequency — the whole contour lies exactly on the unit circle.
      final points = computeNyquistPlot(const ZPowExpr(-1), pointCount: 37)!;
      for (final p in points) {
        expect(p.re * p.re + p.im * p.im, closeTo(1, 1e-9));
      }
    });

    test('is conjugate-symmetric: H(-w) is the conjugate of H(w)', () {
      final h = const ZPowExpr(-1) / const ConstExpr(2);
      final points = computeNyquistPlot(h, pointCount: 25)!;
      final byOmega = {for (final p in points) p.omega: p};

      for (final p in points) {
        // omega=0 is its own mirror (skip: -0.0 lookup is fragile), and
        // omega=pi deliberately has no -pi entry (see the function's own
        // doc comment — they're the same physical point on the circle).
        if (p.omega <= 0 || p.omega == math.pi) continue;
        final mirror = byOmega[-p.omega];
        expect(
          mirror,
          isNotNull,
          reason: 'expected a mirrored point at omega=${-p.omega}',
        );
        expect(mirror!.re, closeTo(p.re, 1e-9));
        expect(mirror.im, closeTo(-p.im, 1e-9));
      }
    });

    test('sweeps omega continuously and ascending from just past -pi to pi, '
        'without duplicating the +-pi point', () {
      final points = computeNyquistPlot(const ConstExpr(1), pointCount: 10)!;
      expect(points.length, 2 * 10 - 2); // pointCount*2 minus the 2 shared
      for (var i = 1; i < points.length; i++) {
        expect(points[i].omega, greaterThan(points[i - 1].omega));
      }
      expect(points.last.omega, closeTo(math.pi, 1e-9));
      // -pi itself never appears (it's the same physical point as +pi).
      expect(points.any((p) => p.omega <= -math.pi), isFalse);
    });

    group('biquad Direct Form II Transposed', () {
      test('the DC and Nyquist points match H(1)/H(-1) computed by hand', () {
        // Same fixture/hand derivation as
        // frequency_response_test.dart's own Bode DC/Nyquist test:
        // H(1) = (b0+b1+b2)/(1+a1+a2) = 2/0.65;
        // H(-1) = (b0-b1+b2)/(1-a1+a2) = 2/1.85. Both real (zero
        // imaginary part).
        final graph = buildBiquadGraph(b0: 1, b1: 0, b2: 1, a1: -0.6, a2: 0.25);
        final h = computeTransferFunction(graph)!.h;
        final points = computeNyquistPlot(h, pointCount: 50)!;

        final dc = points.firstWhere((p) => p.omega == 0);
        expect(dc.re, closeTo(2 / 0.65, 1e-6));
        expect(dc.im, closeTo(0, 1e-6));

        final nyquist = points.last;
        expect(nyquist.omega, closeTo(math.pi, 1e-9));
        expect(nyquist.re, closeTo(2 / 1.85, 1e-6));
        expect(nyquist.im, closeTo(0, 1e-6));
      });
    });

    test('resolves bound symbols the same way computeBodePlot does', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      expect(computeNyquistPlot(h), isNull);

      final points = computeNyquistPlot(
        h,
        bindings: {'k': -0.5},
        pointCount: 3,
      )!;
      final dc = points.firstWhere((p) => p.omega == 0);
      expect(dc.re, closeTo(1 / 0.5, 1e-9));
      expect(dc.im, closeTo(0, 1e-9));
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeNyquistPlot(h), isNull);
      },
    );
  });
}
