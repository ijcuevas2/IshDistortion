import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdDocument _parse(String innerSvg) => parseSdDocument('''
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">
$innerSvg
</svg>
''');

Widget _harness(SdDocument doc, SelectionModel selection) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 400,
    height: 300,
    child: SigmaCanvas(document: doc, selection: selection),
  ),
);

void main() {
  testWidgets('tapping a shape selects it', (tester) async {
    final doc = _parse(
      '<rect id="a" x="10" y="10" width="50" height="50" fill="red"/>',
    );
    final selection = SelectionModel();
    await tester.pumpWidget(_harness(doc, selection));

    expect(selection.isEmpty, isTrue);
    await tester.tapAt(const Offset(30, 30)); // inside the rect
    await tester.pump();
    expect(selection.selected.single.getAttribute(const SdQName('id')), 'a');
  });

  testWidgets('tapping empty space clears the selection', (tester) async {
    final doc = _parse(
      '<rect id="a" x="10" y="10" width="50" height="50" fill="red"/>',
    );
    final selection = SelectionModel();
    await tester.pumpWidget(_harness(doc, selection));

    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(selection.isEmpty, isFalse);

    await tester.tapAt(const Offset(350, 280)); // empty space
    await tester.pump();
    expect(selection.isEmpty, isTrue);
  });

  testWidgets('dragging over empty space marquee-selects shapes inside it', (
    tester,
  ) async {
    final doc = _parse(
      '<rect id="a" x="10" y="10" width="20" height="20"/>'
      '<rect id="b" x="200" y="200" width="20" height="20"/>',
    );
    final selection = SelectionModel();
    await tester.pumpWidget(_harness(doc, selection));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selection.selected.map((e) => e.getAttribute(const SdQName('id'))), [
      'a',
    ]);
  });

  testWidgets('dragging a selected shape moves it in document space', (
    tester,
  ) async {
    final doc = _parse('<rect id="a" x="10" y="10" width="20" height="20"/>');
    final rect = doc.root.descendantElements.firstWhere(
      (e) => e.name.local == 'rect',
    );
    final selection = SelectionModel();
    await tester.pumpWidget(_harness(doc, selection));

    final gesture = await tester.startGesture(
      const Offset(15, 15),
    ); // inside the rect
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(rect.getAttribute(const SdQName('transform')), isNotNull);
    final scene = Scene(doc);
    final bounds = scene.spatialIndex.worldBoundsFor(rect)!;
    expect(bounds.left, closeTo(40, 0.5)); // original x=10, dragged +30
    expect(bounds.top, closeTo(10, 0.5)); // unchanged
    scene.dispose();
  });

  testWidgets(
    'dragging a corner handle scales the selection about the opposite corner',
    (tester) async {
      final doc = _parse('<rect id="a" x="0" y="0" width="10" height="10"/>');
      final rect = doc.root.descendantElements.firstWhere(
        (e) => e.name.local == 'rect',
      );
      final selection = SelectionModel();
      await tester.pumpWidget(_harness(doc, selection));

      selection.selectOnly(rect);
      await tester.pump();

      // Drag the bottom-right handle (at document (10,10)) out to (30,30):
      // the opposite corner (0,0) should stay fixed.
      final gesture = await tester.startGesture(const Offset(10, 10));
      await gesture.moveTo(const Offset(30, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final scene = Scene(doc);
      final bounds = scene.spatialIndex.worldBoundsFor(rect)!;
      expect(bounds.topLeft, within(distance: 0.5, from: Offset.zero));
      expect(bounds.width, closeTo(30, 0.5));
      expect(bounds.height, closeTo(30, 0.5));
      scene.dispose();
    },
  );
}
