import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('bodeAxisRange', () {
    test('an empty list returns the fallback unchanged', () {
      expect(bodeAxisRange(const [], fallback: (-40, 40)), (-40.0, 40.0));
    });

    test('pads a normal range by about 10% on each side', () {
      final (lo, hi) = bodeAxisRange([0, 10], fallback: (-1, 1));
      expect(lo, lessThan(0));
      expect(hi, greaterThan(10));
      expect(lo, closeTo(-1, 1e-9));
      expect(hi, closeTo(11, 1e-9));
    });

    test('a degenerately flat list still returns a non-zero-width range', () {
      final (lo, hi) = bodeAxisRange([5, 5, 5], fallback: (-1, 1));
      expect(hi, greaterThan(lo));
    });

    test('caps the displayed range at 100 units below the maximum', () {
      // A value 10,000 units below the max (e.g. representing an
      // effectively -infinity notch) must not blow the axis out to
      // -10,000 — the whole point of the cap.
      final (lo, hi) = bodeAxisRange([-10000, 0], fallback: (-1, 1));
      expect(hi, closeTo(0 + (100 * 0.1), 1e-6));
      expect(lo, greaterThan(-200));
    });
  });

  group('BodePlotPainter', () {
    Widget harness(List<BodePoint>? points) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 200,
        child: CustomPaint(painter: BodePlotPainter(points: points)),
      ),
    );

    testWidgets('renders without error for null points', (tester) async {
      await tester.pumpWidget(harness(null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for an empty list', (tester) async {
      await tester.pumpWidget(harness(const []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for a normal sweep', (tester) async {
      final h = const ZPowExpr(-1) / const ConstExpr(2);
      final points = computeBodePlot(h, pointCount: 50);
      await tester.pumpWidget(harness(points));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error when some points are +-infinity/NaN', (
      tester,
    ) async {
      const points = [
        BodePoint(
          omega: 0,
          magnitudeDb: double.negativeInfinity,
          phaseDegrees: 0,
        ),
        BodePoint(omega: 1, magnitudeDb: double.infinity, phaseDegrees: 90),
        BodePoint(omega: 2, magnitudeDb: double.nan, phaseDegrees: double.nan),
        BodePoint(omega: 3.14159, magnitudeDb: -6, phaseDegrees: -45),
      ];
      await tester.pumpWidget(harness(points));
      expect(tester.takeException(), isNull);
    });
  });
}
