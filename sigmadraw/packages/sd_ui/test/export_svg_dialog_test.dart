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
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => ExportSvgDialog(
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
  group('ExportSvgDialog', () {
    testWidgets('shows a suggested default path', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-plain-diagram.svg',
      );

      expect(find.text('/tmp/my-plain-diagram.svg'), findsOneWidget);
    });

    testWidgets('the Export button is disabled for an empty path', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(tester, document: document);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      final exportButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export'),
      );
      expect(exportButton.onPressed, isNull);
    });

    testWidgets('Cancel pops with null, without writing anything', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      // Sync, not the async Directory.createTemp/delete — see
      // save_document_dialog_test.dart's own identical comment on why.
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-export-svg-dialog-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/diagram-plain.svg';

      await _openDialog(tester, document: document, suggestedPath: outputPath);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportSvgDialog), findsNothing);
      expect(File(outputPath).existsSync(), isFalse);
    });

    testWidgets(
      'Export writes the document\'s sd:*-stripped plain SVG and pops '
      'with the path',
      (tester) async {
        final document = createBlankSdDocument(width: 400, height: 300);
        final tempDir = Directory.systemTemp.createTempSync(
          'sigmadraw-export-svg-dialog-test-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final outputPath = '${tempDir.path}/diagram-plain.svg';

        await _openDialog(
          tester,
          document: document,
          suggestedPath: outputPath,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportSvgDialog), findsNothing);
        final written = File(outputPath).readAsStringSync();
        expect(written, writeSdDocument(document, mode: SdSaveMode.plain));
        // Genuinely stripped, not just "some string came out" — matches
        // SdSaveMode.plain's own already-tested contract (sd_document's
        // svg_round_trip_test.dart et al.), re-confirmed end to end
        // through the dialog's own real file write.
        expect(written.contains('sd:'), isFalse);
      },
    );

    testWidgets('a bad output path shows a friendly error and does not close', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/definitely/does/not/exist/diagram-plain.svg',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportSvgDialog), findsOneWidget);
      expect(find.textContaining('Could not write'), findsOneWidget);
    });
  });
}
