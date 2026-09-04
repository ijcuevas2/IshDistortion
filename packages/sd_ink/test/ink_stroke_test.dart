import 'package:sd_document/sd_document.dart';
import 'package:sd_ink/sd_ink.dart';
import 'package:test/test.dart';

void main() {
  group('InkStroke.build', () {
    test('returns null for an empty sample list', () {
      const ink = InkStroke();
      expect(ink.build(const [], strokeId: 's1'), isNull);
    });

    test('produces a real, non-empty filled path element', () {
      const ink = InkStroke();
      final points = [
        for (var i = 0; i <= 20; i++)
          StrokePoint(
            x: i.toDouble(),
            y: (i % 4).toDouble(),
            pressure: 0.5,
            timestamp: Duration(milliseconds: i * 10),
          ),
      ];
      final element = ink.build(points, strokeId: 'stroke-1')!;

      expect(element.name.local, 'path');
      expect(element.getAttribute(const SdQName('d')), isNotEmpty);
      expect(element.getAttribute(const SdQName('fill')), isNotEmpty);
      expect(element.strokeId, 'stroke-1');
    });

    test(
      'persists an editable centerline correlated with per-point pressure',
      () {
        const ink = InkStroke();
        final points = [
          for (var i = 0; i <= 10; i++)
            StrokePoint(
              x: i.toDouble(),
              y: 0,
              pressure: 0.7,
              timestamp: Duration(milliseconds: i * 5),
            ),
        ];
        final element = ink.build(points, strokeId: 's2')!;

        expect(element.strokeCenterline, isNotEmpty);
        expect(element.strokePressures, isNotEmpty);
        expect(element.strokeCenterline.length, element.strokePressures.length);
        for (final p in element.strokePressures) {
          expect(p, closeTo(0.7, 1e-6));
        }
      },
    );

    test('survives a full native-SVG save/reload round-trip', () {
      const ink = InkStroke();
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 0.3, timestamp: Duration.zero),
        const StrokePoint(
          x: 20,
          y: 10,
          pressure: 0.9,
          timestamp: Duration(milliseconds: 50),
        ),
        const StrokePoint(
          x: 40,
          y: 0,
          pressure: 0.3,
          timestamp: Duration(milliseconds: 100),
        ),
      ];
      final element = ink.build(points, strokeId: 's3')!;

      final doc = createBlankSdDocument();
      doc.root.appendChild(element);
      final saved = writeSdDocument(doc, mode: SdSaveMode.native);
      final reloaded = parseSdDocument(saved);
      final reloadedStroke = reloaded.root.descendantElements.firstWhere(
        (e) => e.strokeId == 's3',
      );

      expect(
        reloadedStroke.getAttribute(const SdQName('d')),
        element.getAttribute(const SdQName('d')),
      );
      expect(reloadedStroke.strokeCenterline, isNotEmpty);
      expect(
        reloadedStroke.strokeCenterline.length,
        reloadedStroke.strokePressures.length,
      );

      // Plain (non-native) export must still show the raw fill geometry —
      // any SVG viewer sees a normal filled path, no semantic knowledge
      // required — while dropping every sd: attribute.
      final plain = writeSdDocument(doc, mode: SdSaveMode.plain);
      expect(plain, isNot(contains('sd:')));
      final plainReloaded = parseSdDocument(plain);
      final plainPath = plainReloaded.root.descendantElements.firstWhere(
        (e) => e.name.local == 'path',
      );
      expect(
        plainPath.getAttribute(const SdQName('d')),
        element.getAttribute(const SdQName('d')),
      );
    });

    test('a lone tap (one sample) still produces a visible dot', () {
      const ink = InkStroke();
      final element = ink.build([
        const StrokePoint(x: 5, y: 5, pressure: 0.8),
      ], strokeId: 'dot')!;
      expect(element.getAttribute(const SdQName('d')), contains('A'));
    });
  });
}
