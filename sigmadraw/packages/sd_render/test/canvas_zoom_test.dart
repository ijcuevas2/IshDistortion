import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdDocument _parse(String innerSvg) => parseSdDocument('''
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">
$innerSvg
</svg>
''');

void main() {
  group('SigmaCanvasState zoom controls', () {
    testWidgets('zoomByFactor(>1) zooms in about the canvas center', (
      tester,
    ) async {
      final doc = _parse('');
      final key = GlobalKey<SigmaCanvasState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SigmaCanvas(key: key, document: doc),
          ),
        ),
      );

      final before = key.currentState!.viewport.scale;
      key.currentState!.zoomByFactor(2);
      await tester.pump();

      expect(key.currentState!.viewport.scale, greaterThan(before));
    });

    testWidgets('zoomByFactor(<1) zooms out', (tester) async {
      final doc = _parse('');
      final key = GlobalKey<SigmaCanvasState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SigmaCanvas(key: key, document: doc),
          ),
        ),
      );

      final before = key.currentState!.viewport.scale;
      key.currentState!.zoomByFactor(0.5);
      await tester.pump();

      expect(key.currentState!.viewport.scale, lessThan(before));
    });

    testWidgets(
      'zoomByFactor keeps the canvas center fixed in document space',
      (tester) async {
        final doc = _parse('');
        final key = GlobalKey<SigmaCanvasState>();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 400,
              height: 300,
              child: SigmaCanvas(key: key, document: doc),
            ),
          ),
        );

        // Flutter's test surface does not actually constrain SigmaCanvas to
        // the wrapping SizedBox's 400x300 (confirmed via
        // tester.getSize/context.size both reporting the default 800x600
        // test-window size instead) — so the true on-screen center must be
        // read back from the tree rather than assumed from the SizedBox's
        // nominal size. zoomByFactor itself derives its center the same
        // way (context.size / 2), so this mirrors the real code path.
        final canvasSize = tester.getSize(find.byType(SigmaCanvas));
        final screenCenter = Offset(
          canvasSize.width / 2,
          canvasSize.height / 2,
        );
        final docPointBefore = key.currentState!.viewport.screenToDocument(
          screenCenter,
        );

        key.currentState!.zoomByFactor(3);
        await tester.pump();

        final docPointAfter = key.currentState!.viewport.screenToDocument(
          screenCenter,
        );
        expect(docPointAfter.dx, closeTo(docPointBefore.dx, 0.5));
        expect(docPointAfter.dy, closeTo(docPointBefore.dy, 0.5));
      },
    );

    testWidgets('fitToContentAuto frames the document without error', (
      tester,
    ) async {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="1000" height="1000"/>',
      );
      final key = GlobalKey<SigmaCanvasState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SigmaCanvas(key: key, document: doc),
          ),
        ),
      );

      key.currentState!.fitToContentAuto();
      await tester.pump();

      // A 1000x1000 document fit into a 400x300 viewport must have
      // zoomed out (scale < 1), not left at the default 1:1 scale.
      expect(key.currentState!.viewport.scale, lessThan(1));
    });

    testWidgets('fitToContentAuto on an empty document is a no-op', (
      tester,
    ) async {
      final doc = _parse('');
      final key = GlobalKey<SigmaCanvasState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SigmaCanvas(key: key, document: doc),
          ),
        ),
      );

      final before = key.currentState!.viewport;
      key.currentState!.fitToContentAuto();
      await tester.pump();

      expect(key.currentState!.viewport, same(before));
    });
  });
}
