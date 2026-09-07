import 'package:flutter_test/flutter_test.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdElement _block(String id) => SdElement(const SdQName('g'))
  ..blockType = 'gain'
  ..blockId = id
  ..blockPorts = [
    {'id': 'in1', 'dir': 'in', 'x': 0.0, 'y': 0.0},
    {'id': 'out1', 'dir': 'out', 'x': 10.0, 'y': 0.0},
  ];

SdElement _edge(String id, String from, String to) =>
    SdElement(const SdQName('path'))
      ..edgeId = id
      ..edgeFrom = from
      ..edgeTo = to;

void main() {
  group('deleteSelection', () {
    test('deletes the selected elements and clears the selection', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);

      deleteSelection(selection, doc);

      expect(a.parent, isNull);
      expect(selection.isEmpty, isTrue);
    });

    test('is a no-op when nothing is selected', () {
      final doc = createBlankSdDocument();
      final selection = SelectionModel();
      expect(() => deleteSelection(selection, doc), returnsNormally);
    });

    test('deleting a block cascades to delete edges attached to it', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      final b = _block('b');
      final e1 = _edge('e1', 'a:out1', 'b:in1');
      doc.root.appendChild(a);
      doc.root.appendChild(b);
      doc.root.appendChild(e1);
      final selection = SelectionModel()..selectOnly(a);

      deleteSelection(selection, doc);

      expect(a.parent, isNull);
      expect(e1.parent, isNull, reason: 'the edge touching a must go too');
      expect(b.parent, isNotNull, reason: 'b itself was not selected');
    });

    test('does not delete an edge unrelated to the deleted block', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      final b = _block('b');
      final c = _block('c');
      final unrelated = _edge('e2', 'b:out1', 'c:in1');
      doc.root.appendChild(a);
      doc.root.appendChild(b);
      doc.root.appendChild(c);
      doc.root.appendChild(unrelated);
      final selection = SelectionModel()..selectOnly(a);

      deleteSelection(selection, doc);

      expect(unrelated.parent, isNotNull);
    });

    test('undoes the block and its cascaded edges in a single step', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      final b = _block('b');
      final e1 = _edge('e1', 'a:out1', 'b:in1');
      doc.root.appendChild(a);
      doc.root.appendChild(b);
      doc.root.appendChild(e1);
      final selection = SelectionModel()..selectOnly(a);
      final undoStack = UndoStack();

      deleteSelection(selection, doc, undoStack: undoStack);
      expect(a.parent, isNull);
      expect(e1.parent, isNull);
      expect(undoStack.canUndo, isTrue);

      undoStack.undo();
      expect(a.parent, isNotNull);
      expect(e1.parent, isNotNull);
      expect(undoStack.canUndo, isFalse, reason: 'exactly one undo step');
    });

    test('works without an undoStack (direct mutation)', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);

      deleteSelection(selection, doc);
      expect(a.parent, isNull);
    });
  });

  group('SdClipboard / copySelectionToClipboard / pasteFromClipboard', () {
    test('paste creates a new element with a different id but same params', () {
      final doc = createBlankSdDocument();
      final a = _block('a')..blockParams = {'gain': 2.0};
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);
      final clipboard = SdClipboard();

      copySelectionToClipboard(clipboard, selection);
      pasteFromClipboard(clipboard, doc, selection);

      final pasted = doc.root.descendantElements
          .where((e) => e.blockType == 'gain' && e.blockId != 'a')
          .single;
      expect(pasted, isNot(same(a)));
      expect(pasted.blockId, isNot('a'));
      expect(pasted.blockParams, {'gain': 2.0});
    });

    test('the pasted element is offset from the original', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);
      final clipboard = SdClipboard();

      copySelectionToClipboard(clipboard, selection);
      final pasted = clipboard.pasteInto(doc, dx: 30, dy: 40).single;

      expect(pasted.getAttribute(const SdQName('transform')), contains('30'));
    });

    test('pasting twice produces two independent, non-colliding ids', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);
      final clipboard = SdClipboard();
      copySelectionToClipboard(clipboard, selection);

      pasteFromClipboard(clipboard, doc, selection);
      pasteFromClipboard(clipboard, doc, selection);

      final ids = doc.root.descendantElements
          .map((e) => e.blockId)
          .whereType<String>()
          .toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate ids');
      expect(ids, hasLength(3)); // original + 2 pastes
    });

    test('paste is undoable', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);
      final clipboard = SdClipboard();
      final undoStack = UndoStack();
      copySelectionToClipboard(clipboard, selection);

      pasteFromClipboard(clipboard, doc, selection, undoStack: undoStack);
      expect(doc.root.descendantElements.length, 2);
      expect(undoStack.canUndo, isTrue);

      undoStack.undo();
      expect(doc.root.descendantElements.length, 1);
    });

    test('paste selects the newly-pasted element', () {
      final doc = createBlankSdDocument();
      final a = _block('a');
      doc.root.appendChild(a);
      final selection = SelectionModel()..selectOnly(a);
      final clipboard = SdClipboard();
      copySelectionToClipboard(clipboard, selection);

      pasteFromClipboard(clipboard, doc, selection);

      expect(selection.selected.single, isNot(same(a)));
      expect(selection.isSelected(a), isFalse);
    });

    test(
      'copying with nothing selected does not clear an existing clipboard',
      () {
        final doc = createBlankSdDocument();
        final a = _block('a');
        doc.root.appendChild(a);
        final selection = SelectionModel()..selectOnly(a);
        final clipboard = SdClipboard();
        copySelectionToClipboard(clipboard, selection);
        expect(clipboard.isEmpty, isFalse);

        selection.clear();
        copySelectionToClipboard(clipboard, selection); // nothing selected now
        expect(clipboard.isEmpty, isFalse, reason: 'must still hold "a"');
      },
    );

    test('pasting an empty clipboard is a no-op', () {
      final doc = createBlankSdDocument();
      final selection = SelectionModel();
      final clipboard = SdClipboard();
      pasteFromClipboard(clipboard, doc, selection);
      expect(doc.root.descendantElements, isEmpty);
    });
  });
}
