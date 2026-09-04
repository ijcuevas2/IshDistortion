import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sigmadraw/main.dart';

void main() {
  testWidgets(
    'switching to the Ink tool and dragging draws a real stroke, undoable',
    (tester) async {
      await tester.pumpWidget(const SigmaDrawApp());

      await tester.tap(find.byIcon(Icons.draw));
      await tester.pumpAndSettle();

      final canvasTopLeft = tester.getTopLeft(find.byType(SigmaCanvas));
      final gesture = await tester.startGesture(
        canvasTopLeft + const Offset(30, 30),
      );
      await gesture.moveTo(canvasTopLeft + const Offset(80, 30));
      await tester.pump();
      await gesture.moveTo(canvasTopLeft + const Offset(80, 80));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);

      await tester.tap(undoButtonFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNull);
    },
  );

  testWidgets('switching back to Select restores click-to-select behavior', (
    tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.tap(find.byIcon(Icons.draw));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.near_me));
    await tester.pumpAndSettle();

    // Placing a stencil (Select tool active throughout) still works
    // exactly as it did before the ink tool existed.
    final dragHandle = find.text('Gain').first;
    final canvasTopLeft = tester.getTopLeft(find.byType(SigmaCanvas));
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await tester.pump();
    await gesture.moveTo(canvasTopLeft + const Offset(100, 100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);
  });
}
