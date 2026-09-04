import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigmadraw/main.dart';

void main() {
  testWidgets('undo/redo app-bar buttons start disabled', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    final undoButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo),
    );
    final redoButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.redo),
    );
    expect(undoButton.onPressed, isNull);
    expect(redoButton.onPressed, isNull);
  });

  testWidgets(
    'placing a stencil enables Undo; the button reverts it; Redo brings it back',
    (tester) async {
      await tester.pumpWidget(const SigmaDrawApp());

      // Drag "Gain" from the palette onto the canvas.
      final dragHandle = find.text('Gain').first;
      final gesture = await tester.startGesture(tester.getCenter(dragHandle));
      await tester.pump();
      await gesture.moveTo(const Offset(350, 300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);

      // The newly-placed block is auto-selected, so the Inspector tab
      // showing its stencil name is a real, structural confirmation that
      // placement actually happened (not just that the button lit up).
      await tester.tap(find.text('Inspector'));
      await tester.pumpAndSettle();
      expect(find.text('Gain'), findsWidgets);

      await tester.tap(undoButtonFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNull);

      final redoButtonFinder = find.widgetWithIcon(IconButton, Icons.redo);
      expect(tester.widget<IconButton>(redoButtonFinder).onPressed, isNotNull);
      await tester.tap(redoButtonFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);
    },
  );

  testWidgets('Ctrl+Z undoes a placement via the keyboard', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    final dragHandle = find.text('Gain').first;
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await tester.pump();
    await gesture.moveTo(const Offset(350, 300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNull);
  });
}
