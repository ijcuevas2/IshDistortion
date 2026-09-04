import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

const _label = SdQName('label', SdNamespace.sd);

void main() {
  group('SetAttributeCommand', () {
    test('apply sets the new value; unapply restores the old one', () {
      final e = SdElement(const SdQName('g'))..setAttribute(_label, 'old');
      final command = SetAttributeCommand(e, _label, 'new');
      expect(e.getAttribute(_label), 'old', reason: 'not applied yet');

      command.apply();
      expect(e.getAttribute(_label), 'new');

      command.unapply();
      expect(e.getAttribute(_label), 'old');
    });

    test('captures "absent" as the old value, and can remove on apply', () {
      final e = SdElement(const SdQName('g'));
      final setIt = SetAttributeCommand(e, _label, 'new');
      setIt.apply();
      expect(e.getAttribute(_label), 'new');
      setIt.unapply();
      expect(e.hasAttribute(_label), isFalse);

      e.setAttribute(_label, 'x');
      final removeIt = SetAttributeCommand(e, _label, null);
      removeIt.apply();
      expect(e.hasAttribute(_label), isFalse);
      removeIt.unapply();
      expect(e.getAttribute(_label), 'x');
    });
  });

  group('InsertChildCommand / RemoveChildCommand', () {
    test('insert defaults to appending at the end', () {
      final parent = SdElement(const SdQName('g'));
      final a = SdElement(const SdQName('rect'));
      final b = SdElement(const SdQName('circle'));
      parent.appendChild(a);

      final command = InsertChildCommand(parent, b);
      command.apply();
      expect(parent.children, [a, b]);

      command.unapply();
      expect(parent.children, [a]);
    });

    test('insert at an explicit index splices in place, not at the end', () {
      final parent = SdElement(const SdQName('g'));
      final a = SdElement(const SdQName('rect'));
      final c = SdElement(const SdQName('circle'));
      parent.appendChild(a);
      parent.appendChild(c);
      final b = SdElement(const SdQName('ellipse'));

      InsertChildCommand(parent, b, index: 1).apply();
      expect(parent.children, [a, b, c]);
    });

    test('remove captures the child\'s position and restores it there', () {
      final parent = SdElement(const SdQName('g'));
      final a = SdElement(const SdQName('rect'));
      final b = SdElement(const SdQName('circle'));
      final c = SdElement(const SdQName('ellipse'));
      parent.appendChild(a);
      parent.appendChild(b);
      parent.appendChild(c);

      final command = RemoveChildCommand(b);
      command.apply();
      expect(parent.children, [a, c]);

      command.unapply();
      expect(parent.children, [
        a,
        b,
        c,
      ], reason: 'must land back in the middle, not at the end');
    });

    test('remove throws for a node with no parent', () {
      final orphan = SdElement(const SdQName('rect'));
      expect(() => RemoveChildCommand(orphan), throwsArgumentError);
    });

    test('insert and remove are exact inverses under isEquivalentTo', () {
      final doc = createBlankSdDocument();
      final child = SdElement(const SdQName('rect'))
        ..setAttribute(const SdQName('x'), '5');
      final before = createBlankSdDocument();

      InsertChildCommand(doc.root, child).apply();
      RemoveChildCommand(child).apply();

      expect(doc.isEquivalentTo(before), isTrue);
    });
  });

  group('CallbackCommand', () {
    test('apply/unapply run the given closures', () {
      final e = SdElement(const SdQName('g'));
      final oldValue = e.blockLabel;
      final command = CallbackCommand(
        apply: () => e.blockLabel = 'new',
        unapply: () => e.blockLabel = oldValue,
        description: 'Change label',
      );

      command.apply();
      expect(e.blockLabel, 'new');
      expect(command.description, 'Change label');

      command.unapply();
      expect(e.blockLabel, oldValue);
    });

    test('works through an UndoStack transaction like any other command', () {
      final e = SdElement(const SdQName('g'))..blockLabel = 'start';
      final stack = UndoStack();

      final before = e.blockLabel;
      stack.execute(
        CallbackCommand(
          apply: () => e.blockLabel = 'end',
          unapply: () => e.blockLabel = before,
        ),
      );
      expect(e.blockLabel, 'end');

      stack.undo();
      expect(e.blockLabel, 'start');
    });
  });

  group('CompositeCommand', () {
    test('apply runs sub-commands in order; unapply reverses them', () {
      final log = <String>[];
      SdCommand logging(String tag) => _LoggingCommand(log, tag);
      final composite = CompositeCommand([
        logging('a'),
        logging('b'),
        logging('c'),
      ]);

      composite.apply();
      expect(log, ['apply a', 'apply b', 'apply c']);

      log.clear();
      composite.unapply();
      expect(log, [
        'unapply c',
        'unapply b',
        'unapply a',
      ], reason: 'must unwind in reverse order for dependent edits');
    });

    test('correctly reverses a later edit that depended on an earlier one', () {
      // Insert a node, then set an attribute on it — unapply must clear the
      // attribute (harmless either way) and then remove the node, in that
      // order; doing it the other way around would set an attribute on an
      // already-detached node, which still "works" but is the wrong order
      // to generalize from, so this pins the real dependency case: undoing
      // a remove-then-reinsert-elsewhere style composite.
      final parent = SdElement(const SdQName('g'));
      final child = SdElement(const SdQName('rect'));
      final composite = CompositeCommand([
        InsertChildCommand(parent, child),
        SetAttributeCommand(child, _label, 'new'),
      ]);

      composite.apply();
      expect(parent.children, [child]);
      expect(child.getAttribute(_label), 'new');

      composite.unapply();
      expect(parent.children, isEmpty);
      expect(child.hasAttribute(_label), isFalse);
    });
  });
}

class _LoggingCommand implements SdCommand {
  _LoggingCommand(this.log, this.tag);
  final List<String> log;
  final String tag;

  @override
  String get description => tag;

  @override
  void apply() => log.add('apply $tag');

  @override
  void unapply() => log.add('unapply $tag');
}
