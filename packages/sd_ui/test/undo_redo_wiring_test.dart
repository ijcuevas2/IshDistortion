import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  group('InspectorPanel + UndoStack', () {
    testWidgets('editing the label field is undoable', (tester) async {
      final doc = createBlankSdDocument();
      final block = gain.instantiate(instanceId: 'g1', label: 'old');
      doc.root.appendChild(block);
      final selection = SelectionModel()..selectOnly(block);
      final undoStack = UndoStack();

      await tester.pumpWidget(
        _wrap(InspectorPanel(selection: selection, undoStack: undoStack)),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label'),
        'new',
      );
      await tester.pump();

      expect(block.blockLabel, 'new');
      expect(undoStack.canUndo, isTrue);

      undoStack.undo();
      expect(block.blockLabel, 'old');

      undoStack.redo();
      expect(block.blockLabel, 'new');
    });

    testWidgets(
      'with no undoStack, edits still apply directly (unchanged behavior)',
      (tester) async {
        final doc = createBlankSdDocument();
        final block = gain.instantiate(instanceId: 'g1', label: 'old');
        doc.root.appendChild(block);
        final selection = SelectionModel()..selectOnly(block);

        await tester.pumpWidget(_wrap(InspectorPanel(selection: selection)));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Label'),
          'new',
        );
        await tester.pump();

        expect(block.blockLabel, 'new');
      },
    );
  });

  group('StencilCanvasArea + UndoStack', () {
    testWidgets('dropping a palette stencil is undoable', (tester) async {
      final doc = createBlankSdDocument(width: 400, height: 400);
      final undoStack = UndoStack();

      await tester.pumpWidget(
        _wrap(
          Row(
            children: [
              SizedBox(
                width: 150,
                child: StencilPalette(registry: StencilRegistry.builtIn()),
              ),
              Expanded(
                child: StencilCanvasArea(document: doc, undoStack: undoStack),
              ),
            ],
          ),
        ),
      );

      bool hasGain() =>
          doc.root.descendantElements.any((e) => e.blockType == 'gain');
      expect(hasGain(), isFalse);
      expect(undoStack.canUndo, isFalse);

      final dragHandle = find.text('Gain').first;
      final gesture = await tester.startGesture(tester.getCenter(dragHandle));
      await tester.pump();
      await gesture.moveTo(const Offset(300, 200));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(hasGain(), isTrue);
      expect(undoStack.canUndo, isTrue);
      expect(undoStack.undoDescription, contains('Gain'));

      undoStack.undo();
      expect(hasGain(), isFalse);

      undoStack.redo();
      expect(hasGain(), isTrue);
    });
  });
}
