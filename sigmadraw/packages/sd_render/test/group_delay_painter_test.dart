import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('GroupDelayPainter', () {
    Widget harness(List<GroupDelayPoint>? points) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 150,
        child: CustomPaint(painter: GroupDelayPainter(points: points)),
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
      final points = computeGroupDelay(h, pointCount: 50);
      await tester.pumpWidget(harness(points));
      expect(tester.takeException(), isNull);
    });
  });
}
