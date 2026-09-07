import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

void main() {
  group('SdLatexSemantics', () {
    test('is null on a plain element', () {
      final e = SdElement(const SdQName('g'));
      expect(e.latexSource, isNull);
    });

    test(
      'get/set round-trips in memory, and clearing removes the attribute',
      () {
        final e = SdElement(const SdQName('g'));
        e.latexSource = r'H(z) = \frac{1}{1 + a_{1} z^{-1}}';
        expect(e.latexSource, r'H(z) = \frac{1}{1 + a_{1} z^{-1}}');
        expect(e.hasAttribute(SdAttr.latex), isTrue);

        e.latexSource = null;
        expect(e.latexSource, isNull);
        expect(e.hasAttribute(SdAttr.latex), isFalse);
      },
    );

    test('sd:latex is preserved on native save but stripped on plain save', () {
      final doc = createBlankSdDocument();
      final g = SdElement(const SdQName('g'))..latexSource = r'x^2';
      doc.root.appendChild(g);

      final native = writeSdDocument(doc, mode: SdSaveMode.native);
      expect(native, contains('sd:latex'));
      expect(native, contains(r'x^2'));

      final plain = writeSdDocument(doc, mode: SdSaveMode.plain);
      expect(plain, isNot(contains('sd:latex')));
      expect(plain, isNot(contains(r'x^2')));

      // And the geometry element itself must still survive plain export —
      // only the semantic attribute is stripped, per SdSaveMode.plain's
      // contract (mirrors the generic "plain strips every sd: attribute"
      // case in svg_round_trip_test.dart).
      final reparsed = parseSdDocument(plain);
      expect(
        reparsed.root.descendantElements.where((e) => e.name.local == 'g'),
        isNotEmpty,
      );
    });
  });
}
