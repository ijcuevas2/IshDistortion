import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_ui/sd_ui.dart';

Future<void> _openDialog(WidgetTester tester, {String? suggestedPath}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<SdDocument>(
              context: context,
              builder: (_) => OpenDocumentDialog(suggestedPath: suggestedPath),
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
  group('OpenDocumentDialog', () {
    testWidgets('the Open button is disabled for an empty path', (
      tester,
    ) async {
      await _openDialog(tester);

      final openButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open'),
      );
      expect(openButton.onPressed, isNull);
    });

    testWidgets('Cancel pops with null', (tester) async {
      await _openDialog(tester, suggestedPath: '/some/path.svg');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(OpenDocumentDialog), findsNothing);
    });

    testWidgets(
      'Open reads and parses a real file, popping with the document',
      (tester) async {
        final original = createBlankSdDocument(width: 640, height: 480);
        // Sync, not the async Directory.createTemp/delete — see the
        // comment in save_document_dialog_test.dart's own equivalent
        // setup for why.
        final tempDir = Directory.systemTemp.createTempSync(
          'sigmadraw-open-dialog-test-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final path = '${tempDir.path}/diagram.svg';
        File(path).writeAsStringSync(writeSdDocument(original));

        String? poppedPath;
        SdDocument? poppedDocument;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    poppedDocument = await showDialog<SdDocument>(
                      context: context,
                      builder: (_) => OpenDocumentDialog(suggestedPath: path),
                    );
                    poppedPath = path;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Open'));
        await tester.pumpAndSettle();

        expect(find.byType(OpenDocumentDialog), findsNothing);
        expect(poppedPath, path);
        expect(poppedDocument, isNotNull);
        expect(poppedDocument!.isEquivalentTo(original), isTrue);
      },
    );

    testWidgets(
      'a nonexistent path shows a friendly read error and does not close',
      (tester) async {
        await _openDialog(
          tester,
          suggestedPath: '/definitely/does/not/exist/diagram.svg',
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Open'));
        await tester.pumpAndSettle();

        expect(find.byType(OpenDocumentDialog), findsOneWidget);
        expect(find.textContaining('Could not read'), findsOneWidget);
      },
    );

    testWidgets(
      'malformed content shows a friendly parse error and does not close',
      (tester) async {
        // Sync, not the async Directory.createTemp/delete — see the
        // comment in save_document_dialog_test.dart's own equivalent
        // setup for why.
        final tempDir = Directory.systemTemp.createTempSync(
          'sigmadraw-open-dialog-test-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final path = '${tempDir.path}/not-xml.svg';
        File(path).writeAsStringSync('this is not < xml at all');

        await _openDialog(tester, suggestedPath: path);
        await tester.tap(find.widgetWithText(FilledButton, 'Open'));
        await tester.pumpAndSettle();

        expect(find.byType(OpenDocumentDialog), findsOneWidget);
        expect(find.textContaining('Could not parse'), findsOneWidget);
      },
    );
  });
}
