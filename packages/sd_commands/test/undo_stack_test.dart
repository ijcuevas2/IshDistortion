import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

const _label = SdQName('label', SdNamespace.sd);

void main() {
  group('UndoStack.execute / undo / redo', () {
    test('starts with nothing to undo or redo', () {
      final stack = UndoStack();
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.undoDescription, isNull);
      expect(stack.redoDescription, isNull);
    });

    test('execute applies immediately and becomes undoable', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack();
      stack.execute(SetAttributeCommand(e, _label, 'a', description: 'Set a'));

      expect(e.getAttribute(_label), 'a');
      expect(stack.canUndo, isTrue);
      expect(stack.undoDescription, 'Set a');
    });

    test('undo reverses the most recent command and enables redo', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack()..execute(SetAttributeCommand(e, _label, 'a'));

      stack.undo();
      expect(e.hasAttribute(_label), isFalse);
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isTrue);
    });

    test('redo re-applies an undone command', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack()..execute(SetAttributeCommand(e, _label, 'a'));
      stack.undo();

      stack.redo();
      expect(e.getAttribute(_label), 'a');
      expect(stack.canRedo, isFalse);
      expect(stack.canUndo, isTrue);
    });

    test('multiple undos walk back through history in reverse order', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack()
        ..execute(SetAttributeCommand(e, _label, 'a'))
        ..execute(SetAttributeCommand(e, _label, 'b'))
        ..execute(SetAttributeCommand(e, _label, 'c'));

      expect(e.getAttribute(_label), 'c');
      stack.undo();
      expect(e.getAttribute(_label), 'b');
      stack.undo();
      expect(e.getAttribute(_label), 'a');
      stack.undo();
      expect(e.hasAttribute(_label), isFalse);
      expect(stack.canUndo, isFalse);
    });

    test('executing a new command after an undo clears the redo stack', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack()..execute(SetAttributeCommand(e, _label, 'a'));
      stack.undo();
      expect(stack.canRedo, isTrue);

      stack.execute(SetAttributeCommand(e, _label, 'z'));
      expect(stack.canRedo, isFalse, reason: '"a" is unreachable now');
      expect(e.getAttribute(_label), 'z');
    });

    test('undo/redo on an empty stack is a no-op, not an error', () {
      final stack = UndoStack();
      expect(stack.undo, returnsNormally);
      expect(stack.redo, returnsNormally);
    });

    test('clear() discards all history without un-applying anything', () {
      final e = SdElement(const SdQName('g'));
      final stack = UndoStack()..execute(SetAttributeCommand(e, _label, 'a'));
      stack.clear();

      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(e.getAttribute(_label), 'a', reason: 'clear does not undo');
    });
  });

  group('UndoStack transactions', () {
    test('everything executed inside one transaction undoes as one step', () {
      // The canonical case this exists for: a drag applies many small
      // intermediate edits (one per pointer-move) but the user expects a
      // single "Undo" to jump straight back to the pre-drag state.
      final e = SdElement(const SdQName('g'))..setAttribute(_label, 'start');
      final stack = UndoStack();

      stack.beginTransaction();
      stack.execute(SetAttributeCommand(e, _label, 'mid-drag-1'));
      stack.execute(SetAttributeCommand(e, _label, 'mid-drag-2'));
      stack.execute(SetAttributeCommand(e, _label, 'final-position'));
      expect(
        stack.canUndo,
        isFalse,
        reason: 'nothing is a completed undo step until commit',
      );
      stack.commitTransaction(description: 'Move');

      expect(e.getAttribute(_label), 'final-position');
      expect(stack.canUndo, isTrue);
      expect(stack.undoDescription, 'Move');

      stack.undo();
      expect(
        e.getAttribute(_label),
        'start',
        reason: 'one undo must reach all the way back, not just one frame',
      );
      expect(stack.canUndo, isFalse);

      stack.redo();
      expect(e.getAttribute(_label), 'final-position');
    });

    test(
      'a transaction with exactly one command does not wrap it needlessly',
      () {
        final e = SdElement(const SdQName('g'));
        final stack = UndoStack();
        stack.beginTransaction();
        stack.execute(
          SetAttributeCommand(e, _label, 'x', description: 'Set x'),
        );
        stack.commitTransaction();

        expect(
          stack.undoDescription,
          'Set x',
          reason: 'not wrapped in a generic CompositeCommand label',
        );
      },
    );

    test('committing an empty transaction pushes no undo step at all', () {
      final stack = UndoStack();
      stack.beginTransaction();
      stack.commitTransaction();
      expect(stack.canUndo, isFalse);
    });

    test(
      'rollbackTransaction un-applies everything without pushing an undo step',
      () {
        final e = SdElement(const SdQName('g'))..setAttribute(_label, 'start');
        final stack = UndoStack();

        stack.beginTransaction();
        stack.execute(SetAttributeCommand(e, _label, 'mid'));
        stack.execute(SetAttributeCommand(e, _label, 'end'));
        stack.rollbackTransaction();

        expect(e.getAttribute(_label), 'start');
        expect(stack.canUndo, isFalse);
        expect(stack.hasOpenTransaction, isFalse);
      },
    );

    test('beginTransaction while one is already open throws', () {
      final stack = UndoStack()..beginTransaction();
      expect(
        stack.beginTransaction,
        throwsA(isA<TransactionAlreadyOpenError>()),
      );
    });

    test('commit/rollback with no open transaction throws', () {
      final stack = UndoStack();
      expect(stack.commitTransaction, throwsA(isA<NoTransactionOpenError>()));
      expect(stack.rollbackTransaction, throwsA(isA<NoTransactionOpenError>()));
    });

    test('undo/redo while a transaction is open throws', () {
      final stack = UndoStack()..beginTransaction();
      expect(stack.undo, throwsStateError);
      expect(stack.redo, throwsStateError);
    });

    test('a transaction spanning edits to several different elements undoes them all', () {
      final a = SdElement(const SdQName('g'))..setAttribute(_label, 'a0');
      final b = SdElement(const SdQName('g'))..setAttribute(_label, 'b0');
      final stack = UndoStack();

      stack.beginTransaction();
      stack.execute(SetAttributeCommand(a, _label, 'a1'));
      stack.execute(SetAttributeCommand(b, _label, 'b1'));
      stack.commitTransaction(description: 'Move two blocks');

      stack.undo();
      expect(a.getAttribute(_label), 'a0');
      expect(b.getAttribute(_label), 'b0');
    });
  });
}
