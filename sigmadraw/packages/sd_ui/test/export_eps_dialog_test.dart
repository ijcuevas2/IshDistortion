import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';
import 'package:sd_ui/sd_ui.dart';

/// A fake export standing in for the real `pdflatex`+`pdftops`-via-
/// `Isolate.run` pipeline — same reasoning as `export_pdf_dialog_test.dart`'s
/// own fake: `Isolate.run` doesn't reliably complete inside `testWidgets`.
Future<void> _fakeExport(SdDocument document, String outputPath) async {}

Future<void> _throwingCompileExport(
  SdDocument document,
  String outputPath,
) async =>
    throw const PdfExportException('pdflatex could not compile this diagram.');

Future<void> _throwingConvertExport(
  SdDocument document,
  String outputPath,
) async => throw const EpsExportException(
  'pdftops could not convert this diagram to EPS.',
);

Future<void> _throwingFileSystemExport(
  SdDocument document,
  String outputPath,
) async =>
    throw const FileSystemException('No such file or directory', '/bad/dir');

Future<void> _openDialog(
  WidgetTester tester, {
  required SdDocument document,
  String? suggestedPath,
  Future<void> Function(SdDocument, String)? exportEps,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => ExportEpsDialog(
                document: document,
                suggestedPath: suggestedPath,
                exportEps: exportEps ?? _fakeExport,
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
  group('ExportEpsDialog', () {
    testWidgets('shows a suggested default path', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.eps',
      );

      expect(find.text('/tmp/my-diagram.eps'), findsOneWidget);
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

    testWidgets('Cancel closes the dialog without exporting anything', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      var exportCalled = false;
      await _openDialog(
        tester,
        document: document,
        exportEps: (doc, path) async => exportCalled = true,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportEpsDialog), findsNothing);
      expect(exportCalled, isFalse);
    });

    testWidgets('Export succeeds and pops with the chosen path', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.eps',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportEpsDialog), findsNothing);
    });

    testWidgets(
      'a PdfExportException (compile-stage failure) shows its message '
      'and does not close',
      (tester) async {
        final document = createBlankSdDocument();
        await _openDialog(
          tester,
          document: document,
          exportEps: _throwingCompileExport,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportEpsDialog), findsOneWidget);
        expect(
          find.text('pdflatex could not compile this diagram.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an EpsExportException (convert-stage failure) shows its message '
      'and does not close',
      (tester) async {
        final document = createBlankSdDocument();
        await _openDialog(
          tester,
          document: document,
          exportEps: _throwingConvertExport,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportEpsDialog), findsOneWidget);
        expect(
          find.text('pdftops could not convert this diagram to EPS.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a FileSystemException (bad output path) shows a friendly message '
      'and does not close',
      (tester) async {
        final document = createBlankSdDocument();
        await _openDialog(
          tester,
          document: document,
          exportEps: _throwingFileSystemExport,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportEpsDialog), findsOneWidget);
        expect(
          find.textContaining('Could not write to this path'),
          findsOneWidget,
        );
      },
    );
  });
}
