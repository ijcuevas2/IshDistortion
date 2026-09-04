import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_latex/sd_latex.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_ui/sd_ui.dart';

/// A fake compiler standing in for the real `pdflatex`/`dvisvgm`
/// toolchain — the same injectable-compiler seam `LatexRenderCache`
/// itself is designed around (see its doc comment), so this dialog's
/// tests don't each have to shell out to a real LaTeX install.
Future<LatexEmbed> _fakeCompiler(String source) async => LatexEmbed(
  sourceTex: source,
  defs: const [],
  content: SdElement(const SdQName('g'))..latexSource = source,
  widthPt: 10,
  heightPt: 10,
);

Future<LatexEmbed> _throwingCompiler(String source) async =>
    throw const LatexCompileException('pdflatex could not compile this.');

Future<void> _openDialog(
  WidgetTester tester, {
  required SdDocument document,
  UndoStack? undoStack,
  SelectionModel? selection,
  Future<LatexEmbed> Function(String)? compiler,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => InsertLatexDialog(
                document: document,
                undoStack: undoStack,
                selection: selection,
                renderCache: LatexRenderCache(
                  compiler: compiler ?? _fakeCompiler,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('InsertLatexDialog', () {
    testWidgets('shows a live preview of the current source as LatexLabel', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(tester, document: document);

      // The dialog seeds a non-empty default source, so a preview exists
      // immediately without needing to type anything first.
      final preview = tester.widget<LatexLabel>(find.byType(LatexLabel));
      expect(preview.tex, isNotEmpty);

      await tester.enterText(find.byType(TextField), r'x[n]');
      await tester.pump();

      expect(tester.widget<LatexLabel>(find.byType(LatexLabel)).tex, 'x[n]');
    });

    testWidgets('the Insert button is disabled for empty source', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      await _openDialog(tester, document: document);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      final insertButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Insert'),
      );
      expect(insertButton.onPressed, isNull);
    });

    testWidgets(
      'Insert compiles via the injected cache and appends the result, '
      'undoably',
      (tester) async {
        final document = createBlankSdDocument();
        final undoStack = UndoStack();
        final childCountBefore = document.root.children.length;

        await _openDialog(tester, document: document, undoStack: undoStack);
        await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
        await tester.pumpAndSettle();

        // The dialog closes itself on a successful insert.
        expect(find.byType(InsertLatexDialog), findsNothing);
        // +2, not +1: a blank document has no <defs> yet, so
        // positionLatexEmbed creates and inserts one directly (see its doc
        // comment — that bookkeeping is deliberately *not* part of the
        // undo boundary) in addition to the visible content element that
        // *is* the InsertChildCommand.
        expect(document.root.children.length, childCountBefore + 2);
        expect(
          document.root.childElements.last.latexSource,
          _InsertLatexDialogTestDefaults.source,
        );

        expect(undoStack.canUndo, isTrue);
        undoStack.undo();
        // Only the visible content is undone; the (inert, unreferenced)
        // <defs> element the compile created stays behind.
        expect(document.root.children.length, childCountBefore + 1);
      },
    );

    testWidgets('falls back to direct mutation when no undoStack is given', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      final childCountBefore = document.root.children.length;

      await _openDialog(tester, document: document);
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();

      // +2 for the same reason as the undoable case above: a fresh <defs>
      // plus the visible content, both inserted directly this time.
      expect(document.root.children.length, childCountBefore + 2);
    });

    testWidgets('selects the inserted equation when a selection is given', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      final selection = SelectionModel();
      addTearDown(selection.dispose);

      await _openDialog(tester, document: document, selection: selection);
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();

      expect(selection.isEmpty, isFalse);
      expect(selection.selected.single, same(document.root.childElements.last));
    });

    testWidgets('a compile failure shows the error and does not insert', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      final childCountBefore = document.root.children.length;

      await _openDialog(
        tester,
        document: document,
        compiler: _throwingCompiler,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();

      expect(find.byType(InsertLatexDialog), findsOneWidget);
      expect(find.text('pdflatex could not compile this.'), findsOneWidget);
      expect(document.root.children.length, childCountBefore);
    });

    testWidgets('Cancel closes the dialog without inserting anything', (
      tester,
    ) async {
      final document = createBlankSdDocument();
      final childCountBefore = document.root.children.length;

      await _openDialog(tester, document: document);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(InsertLatexDialog), findsNothing);
      expect(document.root.children.length, childCountBefore);
    });
  });
}

/// Mirrors the dialog's own private default-source constant so this test
/// file can assert against it without duplicating the literal by hand.
abstract final class _InsertLatexDialogTestDefaults {
  static const source = r'H(z) = \frac{1}{1 - z^{-1}}';
}
