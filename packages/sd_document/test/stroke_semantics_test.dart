import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

void main() {
  group('SdStrokeSemantics.strokeCenterline', () {
    test('is empty on a plain element', () {
      final e = SdElement(const SdQName('path'));
      expect(e.strokeCenterline, isEmpty);
    });

    test('get/set round-trips in memory', () {
      final e = SdElement(const SdQName('path'));
      e.strokeCenterline = const [(x: 1.0, y: 2.0), (x: 3.5, y: -4.25)];
      expect(e.strokeCenterline, [(x: 1.0, y: 2.0), (x: 3.5, y: -4.25)]);
    });

    test('clearing removes the attribute entirely', () {
      final e = SdElement(const SdQName('path'))
        ..strokeCenterline = const [(x: 1.0, y: 2.0)];
      e.strokeCenterline = const [];
      expect(e.hasAttribute(SdAttr.strokePoints), isFalse);
    });

    test('survives native save/reload, and is stripped on plain save', () {
      final doc = createBlankSdDocument();
      final p = SdElement(const SdQName('path'))
        ..strokeId = 's1'
        ..strokeCenterline = const [(x: 0.0, y: 0.0), (x: 10.0, y: 5.0)]
        ..strokePressures = [0.4, 0.9];
      doc.root.appendChild(p);

      final native = writeSdDocument(doc, mode: SdSaveMode.native);
      final reloaded = parseSdDocument(native);
      final reloadedPath = reloaded.root.descendantElements.firstWhere(
        (e) => e.strokeId == 's1',
      );
      expect(reloadedPath.strokeCenterline, [
        (x: 0.0, y: 0.0),
        (x: 10.0, y: 5.0),
      ]);
      expect(reloadedPath.strokePressures, [0.4, 0.9]);

      final plain = writeSdDocument(doc, mode: SdSaveMode.plain);
      expect(plain, isNot(contains('sd:strokePoints')));
    });
  });
}
