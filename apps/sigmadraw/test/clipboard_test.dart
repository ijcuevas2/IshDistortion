import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_ui/sd_ui.dart';
import 'package:sigmadraw/main.dart';

Future<void> _placeAGain(WidgetTester tester) async {
  final dragHandle = find.text('Gain').first;
  final gesture = await tester.startGesture(tester.getCenter(dragHandle));
  await tester.pump();
  await gesture.moveTo(const Offset(350, 300));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// "Gain" text appears in the palette (always on screen, regardless of
/// which right-side tab is active) *and* once per placed instance in the
/// Elements tab, so a bare `find.text('Gain')` can't tell "how many
/// instances exist" on its own — this scopes the search to just the
/// Elements tab's own tree.
Finder _gainRowsInElementTree() =>
    find.descendant(of: find.byType(ElementTree), matching: find.text('Gain'));

void main() {
  testWidgets('the Delete button removes the selected block, undoably', (
    tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());
    await _placeAGain(tester);

    final deleteButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.delete_outline,
    );
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNotNull);

    await tester.tap(deleteButtonFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNull);
    final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButtonFinder).onPressed, isNotNull);
    await tester.tap(find.text('Elements'));
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsNothing);

    await tester.tap(undoButtonFinder);
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsOneWidget);
    // Undo restores the document (confirmed above) but, like every other
    // undo in this app, doesn't also restore *selection* — that would
    // need SdCommand to expose which elements it affected, which nothing
    // needs yet. So the Delete button correctly reads disabled again
    // here: nothing is selected, even though the block itself is back.
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNull);
  });

  testWidgets('the Delete key does the same as the button', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());
    await _placeAGain(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    final deleteButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.delete_outline,
    );
    expect(
      tester.widget<IconButton>(deleteButtonFinder).onPressed,
      isNull,
      reason: 'nothing is selected any more once it is deleted',
    );
    await tester.tap(find.text('Elements'));
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsNothing);
  });

  testWidgets('Copy then Paste duplicates the selected block, undoably', (
    tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());
    await _placeAGain(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_copy));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elements'));
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsNWidgets(2));

    final undoButtonFinder = find.widgetWithIcon(IconButton, Icons.undo);
    await tester.tap(undoButtonFinder);
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsOneWidget);
  });

  testWidgets('Ctrl+C then Ctrl+V does the same via the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());
    await _placeAGain(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elements'));
    await tester.pumpAndSettle();
    expect(_gainRowsInElementTree(), findsNWidgets(2));
  });
}
