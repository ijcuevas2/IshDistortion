import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_ui/sd_ui.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required SdDocument document,
  String? suggestedPath,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            // Deliberately not awaited: every test below drives the
            // dialog's own buttons directly and checks outcomes via the
            // widget tree/filesystem, so nothing needs this callback's
            // return value.
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => SaveDocumentDialog(
                document: document,
                suggestedPath: suggestedPath,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  group('SaveDocumentDialog', () {
    testWidgets('shows a suggested default path', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.svg',
      );

      expect(find.text('/tmp/my-diagram.svg'), findsOneWidget);
    });

    testWidgets('the Save button is disabled for an empty path', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(tester, document: document);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Cancel pops with null, without writing anything', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      // Sync, not the async Directory.createTemp/delete: confirmed (the
      // hard way — see the README's Isolate.run/testWidgets note, and
      // this is the same underlying class of pitfall) that certain
      // async dart:io operations don't reliably complete inside a
      // testWidgets test, even with no isolate involved at all.
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-save-dialog-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/diagram.svg';

      await _openDialog(tester, document: document, suggestedPath: outputPath);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SaveDocumentDialog), findsNothing);
      expect(File(outputPath).existsSync(), isFalse);
    });

    testWidgets(
      'Save writes the document\'s native SVG and pops with the path',
      (tester) async {
        final document = createBlankSdDocument(width: 400, height: 300);
        final tempDir = Directory.systemTemp.createTempSync(
          'sigmadraw-save-dialog-test-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final outputPath = '${tempDir.path}/diagram.svg';

        await _openDialog(
          tester,
          document: document,
          suggestedPath: outputPath,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(find.byType(SaveDocumentDialog), findsNothing);
        final written = File(outputPath).readAsStringSync();
        expect(written, writeSdDocument(document));
        // Round-trips back to an equivalent document, not just "some
        // string came out".
        expect(parseSdDocument(written).isEquivalentTo(document), isTrue);
      },
    );

    testWidgets('a bad output path shows a friendly error and does not close', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/definitely/does/not/exist/diagram.svg',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(SaveDocumentDialog), findsOneWidget);
      expect(find.textContaining('Could not write'), findsOneWidget);
    });
  });
}
