import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdDocument _parse(String innerSvg) => parseSdDocument('''
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">
$innerSvg
</svg>
''');

Widget _harness(
  SdDocument doc,
  SelectionModel selection,
  UndoStack undoStack,
) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 400,
    height: 300,
    child: SigmaCanvas(
      document: doc,
      selection: selection,
      undoStack: undoStack,
    ),
  ),
);

void main() {
  testWidgets(
    'a whole move drag undoes as one step, back to the pre-drag position',
    (tester) async {
      final doc = _parse('<rect id="a" x="10" y="10" width="20" height="20"/>');
      final rect = doc.root.descendantElements.firstWhere(
        (e) => e.name.local == 'rect',
      );
      final selection = SelectionModel();
      final undoStack = UndoStack();
      await tester.pumpWidget(_harness(doc, selection, undoStack));

      expect(undoStack.canUndo, isFalse);

      final gesture = await tester.startGesture(const Offset(15, 15));
      // Several intermediate moves — each one is its own SetAttributeCommand
      // under the hood, but they must all collapse into a single undo step.
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(rect.getAttribute(const SdQName('transform')), isNotNull);
      final movedScene = Scene(doc);
      final movedBounds = movedScene.spatialIndex.worldBoundsFor(rect)!;
      expect(movedBounds.left, closeTo(40, 0.5)); // 10 + 30
      movedScene.dispose();

      expect(undoStack.canUndo, isTrue);
      expect(undoStack.hasOpenTransaction, isFalse);

      undoStack.undo();
      expect(
        rect.hasAttribute(const SdQName('transform')),
        isFalse,
        reason: 'one undo must reach the pre-drag state, not just one frame',
      );
      expect(undoStack.canUndo, isFalse);
      expect(undoStack.canRedo, isTrue);

      undoStack.redo();
      final redoneScene = Scene(doc);
      final redoneBounds = redoneScene.spatialIndex.worldBoundsFor(rect)!;
      expect(redoneBounds.left, closeTo(40, 0.5));
      redoneScene.dispose();
    },
  );

  testWidgets('a click that never actually drags leaves nothing to undo', (
    tester,
  ) async {
    final doc = _parse('<rect id="a" x="10" y="10" width="20" height="20"/>');
    final selection = SelectionModel();
    final undoStack = UndoStack();
    await tester.pumpWidget(_harness(doc, selection, undoStack));

    final gesture = await tester.startGesture(const Offset(15, 15));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(undoStack.canUndo, isFalse);
    expect(undoStack.hasOpenTransaction, isFalse);
  });

  testWidgets('a whole scale drag also undoes as one step', (tester) async {
    final doc = _parse('<rect id="a" x="0" y="0" width="10" height="10"/>');
    final rect = doc.root.descendantElements.firstWhere(
      (e) => e.name.local == 'rect',
    );
    final selection = SelectionModel()..selectOnly(rect);
    final undoStack = UndoStack();
    await tester.pumpWidget(_harness(doc, selection, undoStack));
    await tester.pump();

    // Drag the bottom-right handle (document (10,10)) out to (30,30).
    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.moveTo(const Offset(20, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final scaledScene = Scene(doc);
    final scaledBounds = scaledScene.spatialIndex.worldBoundsFor(rect)!;
    expect(scaledBounds.width, closeTo(30, 0.5));
    scaledScene.dispose();

    expect(undoStack.canUndo, isTrue);
    undoStack.undo();
    final revertedScene = Scene(doc);
    final revertedBounds = revertedScene.spatialIndex.worldBoundsFor(rect)!;
    expect(revertedBounds.width, closeTo(10, 0.5));
    revertedScene.dispose();
  });

  testWidgets('connector creation is undoable and removes the edge on undo', (
    tester,
  ) async {
    SdElement block(String id, {required List<Map<String, Object?>> ports}) =>
        SdElement(const SdQName('g'))
          ..blockType = 'test'
          ..blockId = id
          ..blockPorts = ports;

    final doc = createBlankSdDocument(width: 400, height: 400);
    doc.root.appendChild(
      block(
        'a',
        ports: [
          {'id': 'out1', 'dir': 'out', 'x': 40.0, 'y': 20.0},
        ],
      ),
    );
    doc.root.appendChild(
      block(
        'b',
        ports: [
          {'id': 'in1', 'dir': 'in', 'x': 100.0, 'y': 20.0},
        ],
      ),
    );
    final undoStack = UndoStack();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 400,
          child: SigmaCanvas(document: doc, undoStack: undoStack),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(40, 20)); // a:out1
    await gesture.moveTo(const Offset(100, 20)); // b:in1
    await tester.pump();
    await gesture.up();
    await tester.pump();

    bool hasEdge() => doc.root.descendantElements.any((e) => e.edgeId != null);
    expect(hasEdge(), isTrue);
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    expect(hasEdge(), isFalse);

    undoStack.redo();
    expect(hasEdge(), isTrue);
  });
}
