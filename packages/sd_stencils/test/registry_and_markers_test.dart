import 'package:sd_document/sd_document.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:test/test.dart';

void main() {
  group('StencilRegistry', () {
    test('builtIn contains every core primitive', () {
      final registry = StencilRegistry.builtIn();
      for (final s in corePrimitiveStencils) {
        expect(registry.byId(s.id), same(s));
      }
    });

    test('byCategory filters correctly', () {
      final registry = StencilRegistry.builtIn();
      final delayShift = registry.byCategory(StencilCategory.delayShift);
      expect(
        delayShift.map((s) => s.id),
        containsAll(['delay', 'continuous-delay']),
      );
      expect(
        delayShift.every((s) => s.category == StencilCategory.delayShift),
        isTrue,
      );
    });

    test('search matches id or display name, case-insensitively', () {
      final registry = StencilRegistry.builtIn();
      expect(registry.search('GAIN').map((s) => s.id), contains('gain'));
      expect(
        registry.search('sampl').map((s) => s.id),
        containsAll(['downsampler', 'upsampler', 'sampler']),
      );
      expect(registry.search('nonexistent-xyz'), isEmpty);
    });

    test('an empty search returns everything', () {
      final registry = StencilRegistry.builtIn();
      expect(registry.search('').length, registry.all.length);
    });
  });

  group('ensureArrowMarker', () {
    test('creates a marker in defs and is idempotent', () {
      final doc = createBlankSdDocument();
      final id1 = ensureArrowMarker(doc);
      final id2 = ensureArrowMarker(doc);
      expect(id1, id2);

      final markers = doc.root.descendantElements.where(
        (e) => e.name.local == 'marker',
      );
      expect(markers, hasLength(1));
    });

    test('reuses an existing <defs> rather than adding a second one', () {
      final doc = createBlankSdDocument();
      doc.root.appendChild(SdElement(const SdQName('defs')));
      ensureArrowMarker(doc);

      final defsElements = doc.root.childElements.where(
        (e) => e.name.local == 'defs',
      );
      expect(defsElements, hasLength(1));
    });
  });
}
