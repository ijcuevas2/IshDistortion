import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('ImpulseStepPainter', () {
    Widget harness(
      List<ImpulseResponseSample>? impulse,
      List<ImpulseResponseSample>? step,
    ) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 200,
        child: CustomPaint(
          painter: ImpulseStepPainter(impulse: impulse, step: step),
        ),
      ),
    );

    testWidgets('renders without error for null data', (tester) async {
      await tester.pumpWidget(harness(null, null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for empty lists', (tester) async {
      await tester.pumpWidget(harness(const [], const []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for a normal one-pole response', (
      tester,
    ) async {
      final h = const ZPowExpr(-1) / const ConstExpr(2);
      final impulse = computeImpulseResponse(h, sampleCount: 20);
      final step = computeStepResponse(h, sampleCount: 20);
      await tester.pumpWidget(harness(impulse, step));
      expect(tester.takeException(), isNull);
    });
  });
}
