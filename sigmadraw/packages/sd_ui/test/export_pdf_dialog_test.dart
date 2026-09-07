import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';
import 'package:sd_ui/sd_ui.dart';

/// A fake export standing in for the real `pdflatex`-via-`Isolate.run`
/// pipeline. `Isolate.run` does not reliably complete when exercised
/// from inside a `testWidgets` test — see `ExportPdfDialog.exportPdf`'s
/// own doc comment — so these tests exercise the dialog's own logic
/// through this seam; `exportToPdf` itself is fully covered for real in
/// `sd_export`'s plain (non-widget) `pdf_export_test.dart`.
Future<void> _fakeExport(SdDocument document, String outputPath) async {}

Future<void> _throwingCompileExport(
  SdDocument document,
  String outputPath,
) async =>
    throw const PdfExportException('pdflatex could not compile this diagram.');

Future<void> _throwingFileSystemExport(
  SdDocument document,
  String outputPath,
) async =>
    throw const FileSystemException('No such file or directory', '/bad/dir');

Future<String?> _openDialog(
  WidgetTester tester, {
  required SdDocument document,
  String? suggestedPath,
  Future<void> Function(SdDocument, String)? exportPdf,
}) async {
  String? poppedWith;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              poppedWith = await showDialog<String>(
                context: context,
                builder: (_) => ExportPdfDialog(
                  document: document,
                  suggestedPath: suggestedPath,
                  exportPdf: exportPdf ?? _fakeExport,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  return poppedWith;
}

void main() {
  group('ExportPdfDialog', () {
    testWidgets('shows a suggested default path', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.pdf',
      );

      expect(find.text('/tmp/my-diagram.pdf'), findsOneWidget);
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

    testWidgets('tapping Cancel pops with null, without exporting', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      var exportCalled = false;
      await _openDialog(
        tester,
        document: document,
        exportPdf: (doc, path) async => exportCalled = true,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPdfDialog), findsNothing);
      expect(exportCalled, isFalse);
    });

    testWidgets('Export succeeds and pops with the chosen path', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.pdf',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPdfDialog), findsNothing);
    });

    testWidgets('a PdfExportException (compile failure) shows its message and '
        'does not close', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        exportPdf: _throwingCompileExport,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPdfDialog), findsOneWidget);
      expect(
        find.text('pdflatex could not compile this diagram.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a FileSystemException (bad output path) shows a friendly message '
      'and does not close',
      (tester) async {
        final document = createBlankSdDocument();
        await _openDialog(
          tester,
          document: document,
          exportPdf: _throwingFileSystemExport,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportPdfDialog), findsOneWidget);
        expect(
          find.textContaining('Could not write to this path'),
          findsOneWidget,
        );
      },
    );
  });
}
