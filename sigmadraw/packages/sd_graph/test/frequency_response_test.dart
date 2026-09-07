import 'dart:math' as math;

import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('computeBodePlot', () {
    test('rejects fewer than 2 points', () {
      expect(
        () => computeBodePlot(const ConstExpr(1), pointCount: 1),
        throwsArgumentError,
      );
    });

    test('sweeps omega linearly from 0 to pi inclusive', () {
      final points = computeBodePlot(const ConstExpr(1), pointCount: 5)!;
      expect(points, hasLength(5));
      expect(points.first.omega, 0);
      expect(points.last.omega, closeTo(math.pi, 1e-12));
      // Evenly spaced: each step is pi/4 for 5 points over [0, pi].
      for (var i = 1; i < points.length; i++) {
        expect(
          points[i].omega - points[i - 1].omega,
          closeTo(math.pi / 4, 1e-12),
        );
      }
    });

    test('a pure real gain has flat magnitude and zero phase everywhere', () {
      // H(z) = 4 for all z, so |H(e^jw)| = 4 -> 20*log10(4) ~= 12.04 dB,
      // and arg(H) = 0, at every single frequency — the simplest possible
      // hand-derivable case (no z at all to evaluate).
      final points = computeBodePlot(const ConstExpr(4), pointCount: 50)!;
      final expectedDb = 20 * (math.log(4) / math.ln10);
      for (final p in points) {
        expect(p.magnitudeDb, closeTo(expectedDb, 1e-9));
        expect(p.phaseDegrees, closeTo(0, 1e-9));
      }
    });

    test('a pure unit delay is all-pass (0 dB) with linear phase -omega', () {
      // H(z) = z^-1 => H(e^jw) = e^-jw: magnitude is exactly 1 (0 dB)
      // at every frequency, and phase is exactly -w radians = -w*180/pi
      // degrees — linear, not just "some negative number" — at every
      // frequency from DC (0 deg) to Nyquist (-180 deg).
      final points = computeBodePlot(const ZPowExpr(-1), pointCount: 37)!;
      for (final p in points) {
        expect(p.magnitudeDb, closeTo(0, 1e-9));
        expect(p.phaseDegrees, closeTo(-p.omega * 180 / math.pi, 1e-6));
      }
      expect(points.first.phaseDegrees, closeTo(0, 1e-9));
      expect(points.last.phaseDegrees, closeTo(-180, 1e-6));
    });

    test('a pure double delay (z^-2) has phase -2*omega, twice as steep', () {
      final points = computeBodePlot(const ZPowExpr(-2), pointCount: 19)!;
      for (final p in points) {
        expect(p.magnitudeDb, closeTo(0, 1e-9));
        expect(p.phaseDegrees, closeTo(-2 * p.omega * 180 / math.pi, 1e-6));
      }
    });

    group('biquad Direct Form II Transposed', () {
      // Same buildBiquadGraph fixture pole_zero_test.dart verifies against
      // hand-derived pole/zero locations — reusing it here cross-checks
      // computeBodePlot against that independent result, not just its own
      // internal consistency: a biquad's zeros are Bode-magnitude nulls
      // (-infinity dB) at exactly the zero's frequency, when that zero
      // sits exactly on the unit circle.
      test(
        'magnitude is deeply attenuated at DC and Nyquist when both are '
        'exact zeros (z = +-1, independently confirmed by computePoleZero)',
        () {
          final graph = buildBiquadGraph(
            b0: 1,
            b1: 0,
            b2: -1,
            a1: -0.6,
            a2: 0.25,
          );
          final h = computeTransferFunction(graph)!.h;
          // Sanity: computePoleZero independently agrees the zeros are at
          // exactly +1 (DC, omega=0) and -1 (Nyquist, omega=pi).
          final poleZero = computePoleZero(h)!;
          for (final expected in [const Complex(1), const Complex(-1)]) {
            expect(
              poleZero.zeros.any((z) => (z - expected).abs() < 1e-6),
              isTrue,
            );
          }

          // Not exactly -infinity: Mason's formula's own floating-point
          // arithmetic (a1=-0.6 has no exact binary representation)
          // leaves ~1e-16-scale residue rather than an exact algebraic 0
          // — the same reason computePoleZero's own tests use a 1e-6
          // tolerance instead of exact equality. -200 dB (a factor of
          // 10^-10 in amplitude) is well beyond any real filter's actual
          // stopband and only reachable here by genuine near-cancellation.
          final points = computeBodePlot(h, pointCount: 200)!;
          expect(points.first.magnitudeDb, lessThan(-200));
          expect(points.last.magnitudeDb, lessThan(-200));
        },
      );

      test('DC and Nyquist magnitude match H(1)/H(-1) computed by hand', () {
        // b2 = +1 this time (not -1), so neither endpoint is an exact
        // zero: H(1) = (b0+b1+b2)/(1+a1+a2) = (1+0+1)/(1-0.6+0.25) =
        // 2/0.65; H(-1) = (b0-b1+b2)/(1-a1+a2) = 2/(1+0.6+0.25) = 2/1.85.
        // Both are positive reals, so phase is exactly 0 at both ends.
        final graph = buildBiquadGraph(b0: 1, b1: 0, b2: 1, a1: -0.6, a2: 0.25);
        final h = computeTransferFunction(graph)!.h;
        final points = computeBodePlot(h, pointCount: 100)!;

        double dbOf(double linear) => 20 * (math.log(linear) / math.ln10);
        expect(points.first.magnitudeDb, closeTo(dbOf(2 / 0.65), 1e-6));
        expect(points.first.phaseDegrees, closeTo(0, 1e-6));
        expect(points.last.magnitudeDb, closeTo(dbOf(2 / 1.85), 1e-6));
        expect(points.last.phaseDegrees, closeTo(0, 1e-6));
      });
    });

    test('resolves bound symbols the same way computePoleZero does', () {
      // H(z) = 1 / (1 + k*z^-1), same shape rationalPolynomials's own
      // test uses — at DC (z=1), H(1) = 1/(1+k).
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      expect(computeBodePlot(h), isNull);

      final points = computeBodePlot(h, bindings: {'k': -0.5}, pointCount: 3)!;
      final expectedDcDb = 20 * (math.log(1 / 0.5) / math.ln10);
      expect(points.first.magnitudeDb, closeTo(expectedDcDb, 1e-9));
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeBodePlot(h), isNull);
      },
    );
  });

  group('computeGroupDelay', () {
    test('rejects fewer than 2 points', () {
      expect(
        () => computeGroupDelay(const ConstExpr(1), pointCount: 1),
        throwsArgumentError,
      );
    });

    test('a pure k-sample delay has constant group delay = k, at every '
        'frequency', () {
      for (final k in [1, 2, 3]) {
        final points = computeGroupDelay(ZPowExpr(-k), pointCount: 20)!;
        for (final p in points) {
          expect(p.delaySamples, closeTo(k.toDouble(), 1e-9), reason: 'k=$k');
        }
      }
    });

    test('a pure real gain has zero group delay everywhere', () {
      final points = computeGroupDelay(const ConstExpr(4), pointCount: 20)!;
      for (final p in points) {
        expect(p.delaySamples, closeTo(0, 1e-9));
      }
    });

    test('matches an independently-implemented, fine central-difference '
        'approximation of phase, for a biquad — not re-deriving the same '
        'symbolic formula twice', () {
      final graph = buildBiquadGraph(
        b0: 1,
        b1: 0.5,
        b2: 0.2,
        a1: -0.6,
        a2: 0.15,
      );
      final h = computeTransferFunction(graph)!.h;
      final analytic = computeGroupDelay(h, pointCount: 50)!;
      final rational = rationalPolynomials(h, const {})!;

      // arg(H(e^{j*omega})) at one specific omega, computed directly
      // (no unwrapping needed for a single point) — independent of
      // computeGroupDelay's own exact symbolic derivative.
      double phaseRadiansAt(double omega) {
        num argAt(Map<int, num> poly) {
          var reSum = 0.0, imSum = 0.0;
          for (final entry in poly.entries) {
            final angle = -entry.key * omega;
            reSum += entry.value * math.cos(angle);
            imSum += entry.value * math.sin(angle);
          }
          return math.atan2(imSum, reSum);
        }

        return (argAt(rational.numerator) - argAt(rational.denominator))
            .toDouble();
      }

      const step = 1e-5;
      for (final p in analytic) {
        if (p.omega - step <= 0 || p.omega + step >= math.pi) {
          continue; // skip the very ends: a central difference here
          // would need a point outside [0, pi].
        }
        var delta =
            phaseRadiansAt(p.omega + step) - phaseRadiansAt(p.omega - step);
        while (delta > math.pi) {
          delta -= 2 * math.pi;
        }
        while (delta < -math.pi) {
          delta += 2 * math.pi;
        }
        final finiteDifferenceTau = -delta / (2 * step);

        expect(
          p.delaySamples,
          closeTo(finiteDifferenceTau, 1e-3),
          reason: 'omega=${p.omega}',
        );
      }
    });

    test('resolves bound symbols the same way computePoleZero does', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]),
        ]),
      );
      expect(computeGroupDelay(h), isNull);
      expect(computeGroupDelay(h, bindings: {'k': -0.5}), isNotNull);
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeGroupDelay(h), isNull);
      },
    );
  });
}
