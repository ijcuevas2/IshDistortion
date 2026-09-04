import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';
import 'package:sigmadraw/main.dart';

/// "Gain"/"Source" text appears in the palette (always on screen) *and*
/// once per placed instance in the Elements tab — this scopes a search
/// to just the Elements tab's own tree, matching clipboard_test.dart's
/// own `_gainRowsInElementTree` helper. A substring match (not exact),
/// since a stencil's display name isn't always just its bare type name
/// (the "source" stencil's is "Source / Constant").
Finder _elementsTreeRowsContaining(String text) => find.descendant(
  of: find.byType(ElementTree),
  matching: find.textContaining(text),
);

/// The stencil palette's own "Search stencils…" field is always on
/// screen too, so a bare `find.byType(TextField)` is ambiguous once a
/// dialog (itself shown as an overlay on top of the existing tree, not
/// replacing it) is open — this scopes to the dialog's own field.
Finder _dialogPathField() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

Future<void> _placeAGain(WidgetTester tester) async {
  final dragHandle = find.text('Gain').first;
  final gesture = await tester.startGesture(tester.getCenter(dragHandle));
  await tester.pump();
  await gesture.moveTo(const Offset(350, 300));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save writes the current document to disk', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'sigmadraw-save-open-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final path = '${tempDir.path}/diagram.svg';

    await tester.pumpWidget(const SigmaDrawApp());
    await _placeAGain(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.save));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogPathField(), path);
    // The dialog's own text-controller listener needs a pump to actually
    // rebuild before the Save button's enabled state reflects the new
    // text — SaveDocumentDialog happens to start non-empty (a suggested
    // default path) so this particular tap would "work" even without
    // this pump, but doing it consistently with the Open test below
    // (where skipping it silently taps a still-disabled button) is the
    // right habit either way.
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saved = parseSdDocument(File(path).readAsStringSync());
    expect(
      saved.root.descendantElements.any((e) => e.blockType == 'gain'),
      isTrue,
    );
  });

  testWidgets(
    'Open replaces the document, clearing undo history and selection',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-save-open-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final path = '${tempDir.path}/other-diagram.svg';
      final other = createBlankSdDocument();
      other.root.appendChild(
        source.instantiate(instanceId: 'src-from-disk', x: 0, y: 0),
      );
      File(path).writeAsStringSync(writeSdDocument(other));

      await tester.pumpWidget(const SigmaDrawApp());
      await _placeAGain(tester);
      await tester.tap(find.text('Elements'));
      await tester.pumpAndSettle();
      expect(_elementsTreeRowsContaining('Gain'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.enterText(_dialogPathField(), path);
      // OpenDocumentDialog starts with an *empty* path (no suggestion),
      // so its Open button is genuinely disabled until this pump
      // processes the text-controller listener's rebuild — tapping it
      // beforehand would silently hit a disabled button and do nothing.
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(OpenDocumentDialog), findsNothing);
      // The old document's content is gone, the new one's is there, and
      // undo history from the old document no longer applies to it.
      expect(_elementsTreeRowsContaining('Gain'), findsNothing);
      expect(_elementsTreeRowsContaining('Source'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull,
      );
    },
  );
}
