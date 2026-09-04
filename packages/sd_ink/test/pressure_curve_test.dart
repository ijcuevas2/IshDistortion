import 'package:sd_ink/sd_ink.dart';
import 'package:test/test.dart';

void main() {
  group('PressureCurve', () {
    test('minimum pressure gives minWidthFraction of the nominal width', () {
      const curve = PressureCurve(minWidthFraction: 0.2, maxWidthFraction: 1.5);
      expect(curve.widthFor(0, 10), closeTo(2.0, 1e-9));
    });

    test('maximum pressure gives maxWidthFraction of the nominal width', () {
      const curve = PressureCurve(minWidthFraction: 0.2, maxWidthFraction: 1.5);
      expect(curve.widthFor(1, 10), closeTo(15.0, 1e-9));
    });

    test(
      'linear (gamma=1, the default) is exactly halfway at pressure 0.5',
      () {
        const curve = PressureCurve(
          minWidthFraction: 0.2,
          maxWidthFraction: 1.2,
        );
        expect(curve.widthFor(0.5, 10), closeTo(7.0, 1e-9)); // (0.2+1.2)/2 * 10
      },
    );

    test('out-of-range pressure is clamped, not extrapolated', () {
      const curve = PressureCurve(minWidthFraction: 0.2, maxWidthFraction: 1.5);
      expect(curve.widthFor(-5, 10), closeTo(curve.widthFor(0, 10), 1e-9));
      expect(curve.widthFor(5, 10), closeTo(curve.widthFor(1, 10), 1e-9));
    });

    test('gamma > 1 biases the ramp toward thin for most of the range', () {
      const linear = PressureCurve(minWidthFraction: 0, maxWidthFraction: 1);
      const gamma2 = PressureCurve(
        minWidthFraction: 0,
        maxWidthFraction: 1,
        gamma: 2,
      );
      // At the midpoint, p^2 < p for p in (0,1), so gamma=2 is thinner.
      expect(gamma2.widthFor(0.5, 10), lessThan(linear.widthFor(0.5, 10)));
      // Both curves still agree exactly at the endpoints.
      expect(gamma2.widthFor(0, 10), closeTo(linear.widthFor(0, 10), 1e-9));
      expect(gamma2.widthFor(1, 10), closeTo(linear.widthFor(1, 10), 1e-9));
    });
  });

  group('inferPressureFromSpeed', () {
    StrokePoint pt(double x, double y, int ms) => StrokePoint(
      x: x,
      y: y,
      timestamp: Duration(milliseconds: ms),
    );

    test('leaves an already-pressured point untouched', () {
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 0.3, timestamp: Duration.zero),
        const StrokePoint(
          x: 1,
          y: 0,
          pressure: 0.3,
          timestamp: Duration(milliseconds: 10),
        ),
      ];
      final result = inferPressureFromSpeed(points);
      expect(result[0].pressure, 0.3);
      expect(result[1].pressure, 0.3);
    });

    test(
      'a slow (deliberate) stroke infers higher pressure than a fast one',
      () {
        final slow = inferPressureFromSpeed([
          pt(0, 0, 0),
          pt(1, 0, 1000), // 1 unit in 1s: very slow
          pt(2, 0, 2000),
        ]);
        final fast = inferPressureFromSpeed([
          pt(0, 0, 0),
          pt(1000, 0, 1), // 1000 units in 1ms: very fast
          pt(2000, 0, 2),
        ]);
        expect(slow[1].pressure!, greaterThan(fast[1].pressure!));
      },
    );

    test('inferred pressure is always within 0..1', () {
      final result = inferPressureFromSpeed([pt(0, 0, 0), pt(100000, 0, 1)]);
      for (final p in result) {
        expect(p.pressure, inInclusiveRange(0.0, 1.0));
      }
    });

    test('a single point (no speed to measure) defaults to full pressure', () {
      final result = inferPressureFromSpeed([pt(5, 5, 0)]);
      expect(result.single.pressure, 1.0);
    });
  });
}
