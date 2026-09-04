import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('SigmaViewport', () {
    test('documentToScreen / screenToDocument are inverses', () {
      const v = SigmaViewport(translation: Offset(50, -20), scale: 2.5);
      const doc = Offset(13, 7);
      expect(v.screenToDocument(v.documentToScreen(doc)), doc);
    });

    test('panBy shifts translation only', () {
      const v = SigmaViewport(translation: Offset(10, 10), scale: 3);
      final panned = v.panBy(const Offset(5, -5));
      expect(panned.translation, const Offset(15, 5));
      expect(panned.scale, 3);
    });

    test('zoomBy keeps the focal point fixed on screen', () {
      const v = SigmaViewport(translation: Offset(20, 20), scale: 1);
      const focal = Offset(100, 150);
      final before = v.screenToDocument(focal);
      final after = v.zoomBy(2.0, focal);
      expect(after.scale, 2.0);
      expect(after.documentToScreen(before).dx, closeTo(focal.dx, 0.0001));
      expect(after.documentToScreen(before).dy, closeTo(focal.dy, 0.0001));
    });

    test('zoomBy clamps to min/max scale', () {
      const v = SigmaViewport();
      expect(v.zoomBy(1e9, Offset.zero).scale, SigmaViewport.maxScale);
      expect(v.zoomBy(1e-9, Offset.zero).scale, SigmaViewport.minScale);
    });

    test(
      'fitting centers and scales content to fill the viewport with margin',
      () {
        const content = Rect.fromLTWH(0, 0, 100, 50);
        final v = SigmaViewport.fitting(
          content,
          const Size(220, 120),
          margin: 10,
        );
        // Width-constrained: (220 - 20) / 100 == 2.0 < (120-20)/50 == 2.0 (tie) -> scale 2.0.
        expect(v.scale, closeTo(2.0, 0.0001));
        // Content center (50,25) should land on the viewport center (110,60).
        final screenCenter = v.documentToScreen(content.center);
        expect(screenCenter.dx, closeTo(110, 0.01));
        expect(screenCenter.dy, closeTo(60, 0.01));
      },
    );

    test('fitting on an empty rect or viewport returns the identity viewport rather than NaN/Inf', () {
      expect(
        SigmaViewport.fitting(Rect.zero, const Size(100, 100)),
        const SigmaViewport(),
      );
      expect(
        SigmaViewport.fitting(const Rect.fromLTWH(0, 0, 10, 10), Size.zero),
        const SigmaViewport(),
      );
    });
  });
}
