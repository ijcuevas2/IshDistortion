import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('nyquistScaleFor', () {
    test('an empty/null list still fits the -1 reference point', () {
      final scale = nyquistScaleFor(const [], const Size(200, 200));
      final minusOnePx = 1 / scale;
      expect(minusOnePx, greaterThan(0));
      expect(minusOnePx, lessThanOrEqualTo(100));
    });

    test('a point far from the origin grows the scale to fit it', () {
      const farPoint = [NyquistPoint(omega: 0, re: 5, im: 0)];
      const nearOrigin = <NyquistPoint>[];
      final scaleFar = nyquistScaleFor(farPoint, const Size(200, 200));
      final scaleNear = nyquistScaleFor(nearOrigin, const Size(200, 200));
      // More units per pixel = more zoomed out = correctly fitting the
      // farther-out point.
      expect(scaleFar, greaterThan(scaleNear));
    });
  });

  group('NyquistPlotPainter', () {
    Widget harness(List<NyquistPoint>? points) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 200,
        height: 200,
        child: CustomPaint(painter: NyquistPlotPainter(points: points)),
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

    testWidgets('renders without error for a populated contour', (
      tester,
    ) async {
      final h = const ZPowExpr(-1) / const ConstExpr(2);
      final points = computeNyquistPlot(h, pointCount: 30);
      await tester.pumpWidget(harness(points));
      expect(tester.takeException(), isNull);
    });
  });
}
