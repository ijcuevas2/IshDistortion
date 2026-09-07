import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('complexToCanvas', () {
    test('the origin maps to the center of the canvas', () {
      final p = complexToCanvas(const Complex(0, 0), const Size(200, 100), 1);
      expect(p, const Offset(100, 50));
    });

    test(
      'a positive real part moves right; a positive imaginary part moves up',
      () {
        final p = complexToCanvas(const Complex(1, 1), const Size(200, 100), 1);
        expect(p.dx, greaterThan(100));
        expect(p.dy, lessThan(50)); // "up" on screen is a smaller y.
      },
    );

    test('unitsPerPixel scales distances', () {
      final near = complexToCanvas(
        const Complex(1, 0),
        const Size(200, 100),
        1,
      );
      final far = complexToCanvas(const Complex(1, 0), const Size(200, 100), 2);
      // At a coarser scale (more units per pixel), the same complex-plane
      // point sits closer to the center on screen.
      expect((far.dx - 100).abs(), lessThan((near.dx - 100).abs()));
    });
  });

  group('scaleFor', () {
    test(
      'an empty result still fits the unit circle, not a zero-size plot',
      () {
        const result = PoleZeroResult(poles: [], zeros: []);
        final scale = scaleFor(result, const Size(200, 200));
        // At this scale, the unit circle's radius in pixels must be
        // positive and no larger than the available half-size.
        final unitRadiusPx = 1 / scale;
        expect(unitRadiusPx, greaterThan(0));
        expect(unitRadiusPx, lessThanOrEqualTo(100));
      },
    );

    test('a pole outside the unit circle grows the scale to fit it', () {
      const withFarPole = PoleZeroResult(poles: [Complex(3, 0)], zeros: []);
      const unitOnly = PoleZeroResult(poles: [], zeros: []);
      final scaleWithFarPole = scaleFor(withFarPole, const Size(200, 200));
      final scaleUnitOnly = scaleFor(unitOnly, const Size(200, 200));
      // More units per pixel = more zoomed out = correctly fitting the
      // farther-out pole.
      expect(scaleWithFarPole, greaterThan(scaleUnitOnly));

      final polePx = complexToCanvas(
        const Complex(3, 0),
        const Size(200, 200),
        scaleWithFarPole,
      );
      // The far pole must actually land within the canvas now.
      expect(polePx.dx, lessThanOrEqualTo(200));
    });
  });

  group('PoleZeroPlotPainter', () {
    Widget harness(PoleZeroResult? result) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 200,
        height: 200,
        child: CustomPaint(painter: PoleZeroPlotPainter(result: result)),
      ),
    );

    testWidgets('renders without error for a null result', (tester) async {
      await tester.pumpWidget(harness(null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for an empty result', (tester) async {
      await tester.pumpWidget(
        harness(const PoleZeroResult(poles: [], zeros: [])),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for a populated result', (tester) async {
      await tester.pumpWidget(
        harness(
          const PoleZeroResult(
            poles: [Complex(0.3, 0.4), Complex(0.3, -0.4)],
            zeros: [Complex(1), Complex(-1)],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
