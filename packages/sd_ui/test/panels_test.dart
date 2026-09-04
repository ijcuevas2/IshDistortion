import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

SdDocument _docWithOneGain() {
  final doc = createBlankSdDocument();
  doc.root.appendChild(gain.instantiate(instanceId: 'g1', x: 0, y: 0));
  return doc;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 400, child: child)),
);

void main() {
  group('ElementTree', () {
    testWidgets('shows a row per element, using the registry display name', (
      tester,
    ) async {
      final doc = _docWithOneGain();
      final selection = SelectionModel();
      await tester.pumpWidget(
        _wrap(
          ElementTree(
            document: doc,
            selection: selection,
            registry: StencilRegistry.builtIn(),
          ),
        ),
      );

      expect(find.textContaining('Gain'), findsOneWidget);
    });

    testWidgets('tapping a row selects that element', (tester) async {
      final doc = _docWithOneGain();
      final selection = SelectionModel();
      await tester.pumpWidget(
        _wrap(
          ElementTree(
            document: doc,
            selection: selection,
            registry: StencilRegistry.builtIn(),
          ),
        ),
      );

      expect(selection.isEmpty, isTrue);
      await tester.tap(find.textContaining('Gain'));
      await tester.pump();

      final block = doc.root.descendantElements.firstWhere(
        (e) => e.blockId == 'g1',
      );
      expect(selection.selected.single, same(block));
    });

    testWidgets(
      'falls back to a humanized id when the registry lacks the type',
      (tester) async {
        final doc = createBlankSdDocument();
        doc.root.appendChild(
          SdElement(const SdQName('g'))
            ..blockType = 'custom-widget'
            ..blockId = 'c1',
        );
        await tester.pumpWidget(
          _wrap(ElementTree(document: doc, selection: SelectionModel())),
        );
        expect(find.text('Custom Widget'), findsOneWidget);
      },
    );
  });

  group('InspectorPanel', () {
    testWidgets('shows a placeholder when nothing is selected', (tester) async {
      await tester.pumpWidget(
        _wrap(InspectorPanel(selection: SelectionModel())),
      );
      expect(find.text('Nothing selected'), findsOneWidget);
    });

    testWidgets('editing the label field updates blockLabel', (tester) async {
      final doc = _docWithOneGain();
      final block = doc.root.descendantElements.firstWhere(
        (e) => e.blockId == 'g1',
      );
      final selection = SelectionModel()..selectOnly(block);

      await tester.pumpWidget(
        _wrap(
          InspectorPanel(
            selection: selection,
            registry: StencilRegistry.builtIn(),
          ),
        ),
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'k');
      await tester.pump();

      expect(block.blockLabel, 'k');
    });

    testWidgets(
      'editing a numeric param preserves its double-ness and updates blockParams',
      (tester) async {
        final doc = _docWithOneGain();
        final block = doc.root.descendantElements.firstWhere(
          (e) => e.blockId == 'g1',
        );
        final selection = SelectionModel()..selectOnly(block);

        await tester.pumpWidget(
          _wrap(
            InspectorPanel(
              selection: selection,
              registry: StencilRegistry.builtIn(),
            ),
          ),
        );

        await tester.enterText(
          find.widgetWithText(TextFormField, 'gain'),
          '2.5',
        );
        await tester.pump();

        expect(block.blockParams['gain'], 2.5);
      },
    );
  });

  group('StencilCanvasArea', () {
    testWidgets(
      'dropping a palette stencil places a new instance at the drop point',
      (tester) async {
        final doc = createBlankSdDocument(width: 400, height: 400);
        await tester.pumpWidget(
          _wrap(
            Row(
              children: [
                SizedBox(
                  width: 150,
                  child: StencilPalette(registry: StencilRegistry.builtIn()),
                ),
                Expanded(child: StencilCanvasArea(document: doc)),
              ],
            ),
          ),
        );

        final dragHandle = find.text('Gain').first;
        final gesture = await tester.startGesture(tester.getCenter(dragHandle));
        await tester.pump();
        await gesture.moveTo(const Offset(300, 200));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final placed = doc.root.descendantElements.where(
          (e) => e.blockType == 'gain',
        );
        expect(placed, hasLength(1));
      },
    );
  });
}
