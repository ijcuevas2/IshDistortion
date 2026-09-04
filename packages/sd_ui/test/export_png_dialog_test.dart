import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_ui/sd_ui.dart';

/// A fake export standing in for real `dart:ui` rendering.
/// `tester.runAsync` (Flutter's fix for testing real `dart:ui`/isolate
/// async calls inside `testWidgets` — see the standalone
/// `isolate-run-testwidgets-hang` memory) does not mix with
/// `tester.tap`/`pump` calls inside its own callback, so a widget test
/// *triggering* the real export via a simulated tap needs this seam
/// instead; the real pipeline is covered directly (a plain call,
/// `runAsync`-wrapped) in `sd_export`'s own `png_export_test.dart`.
Future<void> _fakeExport(SdDocument document, String outputPath) async {}

Future<void> _throwingArgumentExport(
  SdDocument document,
  String outputPath,
) async => throw ArgumentError('no width/height');

Future<void> _throwingFileSystemExport(
  SdDocument document,
  String outputPath,
) async =>
    throw const FileSystemException('No such file or directory', '/bad/dir');

Future<void> _openDialog(
  WidgetTester tester, {
  required SdDocument document,
  String? suggestedPath,
  Future<void> Function(SdDocument, String)? exportPng,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => ExportPngDialog(
                document: document,
                suggestedPath: suggestedPath,
                exportPng: exportPng ?? _fakeExport,
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
  group('ExportPngDialog', () {
    testWidgets('shows a suggested default path', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.png',
      );

      expect(find.text('/tmp/my-diagram.png'), findsOneWidget);
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
        exportPng: (doc, path) async => exportCalled = true,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPngDialog), findsNothing);
      expect(exportCalled, isFalse);
    });

    testWidgets('Export succeeds and pops with the chosen path', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        suggestedPath: '/tmp/my-diagram.png',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPngDialog), findsNothing);
    });

    testWidgets('an ArgumentError (no width/height) shows its message and does '
        'not close', (tester) async {
      final document = createBlankSdDocument();
      await _openDialog(
        tester,
        document: document,
        exportPng: _throwingArgumentExport,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPngDialog), findsOneWidget);
      expect(find.textContaining('no width/height'), findsOneWidget);
    });

    testWidgets(
      'a FileSystemException (bad output path) shows a friendly message '
      'and does not close',
      (tester) async {
        final document = createBlankSdDocument();
        await _openDialog(
          tester,
          document: document,
          exportPng: _throwingFileSystemExport,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Export'));
        await tester.pumpAndSettle();

        expect(find.byType(ExportPngDialog), findsOneWidget);
        expect(
          find.textContaining('Could not write to this path'),
          findsOneWidget,
        );
      },
    );
  });
}
