import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('rootLocusScaleFor', () {
    test('an empty list still fits the unit circle', () {
      final scale = rootLocusScaleFor(const [], const Size(200, 200));
      final onePx = 1 / scale;
      expect(onePx, greaterThan(0));
      expect(onePx, lessThanOrEqualTo(100));
    });

    test('a pole far from the origin, in any sample, grows the scale', () {
      const farSample = [
        RootLocusSample(parameterValue: 0, poles: [Complex(5, 0)], zeros: []),
      ];
      const nearOrigin = <RootLocusSample>[];
      final scaleFar = rootLocusScaleFor(farSample, const Size(200, 200));
      final scaleNear = rootLocusScaleFor(nearOrigin, const Size(200, 200));
      expect(scaleFar, greaterThan(scaleNear));
    });
  });

  group('RootLocusPainter', () {
    Widget harness(List<RootLocusSample>? samples) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 200,
        height: 200,
        child: CustomPaint(painter: RootLocusPainter(samples: samples)),
      ),
    );

    testWidgets('renders without error for null samples', (tester) async {
      await tester.pumpWidget(harness(null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for an empty list', (tester) async {
      await tester.pumpWidget(harness(const []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for a real swept pole', (tester) async {
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
        start: 0.1,
        end: 0.9,
        pointCount: 20,
      );
      await tester.pumpWidget(harness(samples));
      expect(tester.takeException(), isNull);
    });
  });
}
