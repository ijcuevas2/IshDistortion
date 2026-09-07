import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

void main() {
  group('cloneNode', () {
    test('an element clone is structurally equivalent to the original', () {
      final original = SdElement(
        const SdQName('g'),
        attributes: {const SdQName('id'): 'a'},
        children: [
          SdElement(
            const SdQName('rect'),
            attributes: {const SdQName('x'): '5'},
          ),
          SdText('hello'),
        ],
      );
      final clone = cloneNode(original);
      expect(clone.isEquivalentTo(original), isTrue);
    });

    test('the clone starts detached, with no parent', () {
      final parent = SdElement(const SdQName('g'));
      final original = SdElement(const SdQName('rect'));
      parent.appendChild(original);

      final clone = cloneNode(original);
      expect(clone.parent, isNull);
      expect(original.parent, same(parent)); // unaffected by cloning it
    });

    test('mutating the clone does not affect the original', () {
      final original = SdElement(const SdQName('rect'))
        ..setAttribute(const SdQName('x'), '1');
      final clone = cloneNode(original) as SdElement;

      clone.setAttribute(const SdQName('x'), '999');
      expect(original.getAttribute(const SdQName('x')), '1');
    });

    test('mutating the original after cloning does not affect the clone', () {
      final original = SdElement(const SdQName('rect'))
        ..setAttribute(const SdQName('x'), '1');
      final clone = cloneNode(original) as SdElement;

      original.setAttribute(const SdQName('x'), '999');
      expect(clone.getAttribute(const SdQName('x')), '1');
    });

    test('children are cloned recursively, not shared by reference', () {
      final child = SdElement(const SdQName('rect'));
      final original = SdElement(const SdQName('g'), children: [child]);
      final clone = cloneNode(original) as SdElement;

      expect(clone.children.single, isNot(same(child)));
      (clone.children.single as SdElement).setAttribute(
        const SdQName('x'),
        '5',
      );
      expect(child.hasAttribute(const SdQName('x')), isFalse);
    });

    test('namespace declarations are copied, not shared', () {
      final original = SdElement(
        const SdQName('g'),
        namespaceDeclarations: {'sd': SdNamespace.sd},
      );
      final clone = cloneNode(original) as SdElement;
      expect(clone.namespaceDeclarations, original.namespaceDeclarations);
      expect(
        clone.namespaceDeclarations,
        isNot(same(original.namespaceDeclarations)),
      );
    });

    test('every non-element node kind round-trips through cloning', () {
      for (final original in <SdNode>[
        SdText('hi'),
        SdComment('a comment'),
        SdCData('raw <data>'),
        SdProcessingInstruction('xml-stylesheet', 'href="x.css"'),
        SdDoctype('svg', publicId: 'pub', systemId: 'sys'),
      ]) {
        final clone = cloneNode(original);
        expect(clone.runtimeType, original.runtimeType);
        expect(clone.isEquivalentTo(original), isTrue);
      }
    });

    test('a semantic (sd:*) block clones with its typed accessors intact', () {
      final original = SdElement(const SdQName('g'))
        ..blockType = 'gain'
        ..blockId = 'g1'
        ..blockParams = {'gain': 2.0};
      final clone = cloneNode(original) as SdElement;

      expect(clone.blockType, 'gain');
      expect(clone.blockId, 'g1');
      expect(clone.blockParams, {'gain': 2.0});
    });
  });
}
