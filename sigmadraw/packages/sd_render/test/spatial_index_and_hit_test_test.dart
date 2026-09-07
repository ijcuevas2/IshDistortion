import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdDocument _parse(String innerSvg) => parseSdDocument('''
<svg xmlns="http://www.w3.org/2000/svg">
$innerSvg
</svg>
''');

void main() {
  group('SpatialIndex', () {
    test('query finds only entries whose bbox intersects the area', () {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="10" height="10" fill="red"/>'
        '<rect id="b" x="100" y="100" width="10" height="10" fill="blue"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));

      final near = index.query(const Rect.fromLTWH(-5, -5, 20, 20));
      expect(near.map((e) => e.element.getAttribute(const SdQName('id'))), [
        'a',
      ]);

      final both = index.query(const Rect.fromLTWH(-5, -5, 200, 200));
      expect(both, hasLength(2));
    });

    test('query results are in paint (document) order', () {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="10" height="10"/>'
        '<rect id="b" x="0" y="0" width="10" height="10"/>'
        '<rect id="c" x="0" y="0" width="10" height="10"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      final hits = index.query(const Rect.fromLTWH(-1, -1, 20, 20));
      expect(hits.map((e) => e.element.getAttribute(const SdQName('id'))), [
        'a',
        'b',
        'c',
      ]);
    });

    test('splits and still finds every entry correctly once past the split threshold', () {
      final rects = [
        for (var i = 0; i < 40; i++)
          '<rect id="r$i" x="${i * 20}" y="0" width="5" height="5"/>',
      ].join();
      final index = SpatialIndex.build(buildScene(_parse(rects)));

      // A tight query around just one of the later rects should find only it.
      final hit = index.query(const Rect.fromLTWH(20 * 30.0, 0, 5, 5));
      expect(hit, hasLength(1));
      expect(hit.single.element.getAttribute(const SdQName('id')), 'r30');

      // A query covering everything should find all 40.
      expect(
        index.query(const Rect.fromLTWH(-10, -10, 20 * 40.0 + 20, 20)),
        hasLength(40),
      );
    });

    test(
      'worldBoundsFor unions a <use> instance\'s whole resolved subtree',
      () {
        final doc = _parse('''
        <defs>
          <symbol id="sym" viewBox="0 0 10 10">
            <rect x="0" y="0" width="4" height="4"/>
            <rect x="6" y="6" width="4" height="4"/>
          </symbol>
        </defs>
        <use id="inst" href="#sym" width="10" height="10"/>
      ''');
        final index = SpatialIndex.build(buildScene(doc));
        final useElement = doc.root.descendantElements.firstWhere(
          (e) => e.getAttribute(const SdQName('id')) == 'inst',
        );
        expect(
          index.worldBoundsFor(useElement),
          const Rect.fromLTWH(0, 0, 10, 10),
        );
      },
    );
  });

  group('hitTestPoint', () {
    test('finds a point inside a filled shape', () {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="10" height="10" fill="red"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      final hit = hitTestPoint(index, const Offset(5, 5));
      expect(hit?.getAttribute(const SdQName('id')), 'a');
    });

    test('misses a point outside every shape', () {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="10" height="10" fill="red"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      expect(hitTestPoint(index, const Offset(50, 50)), isNull);
    });

    test('the topmost (last-painted) overlapping shape wins', () {
      final doc = _parse(
        '<rect id="bottom" x="0" y="0" width="20" height="20" fill="red"/>'
        '<rect id="top" x="5" y="5" width="20" height="20" fill="blue"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      expect(
        hitTestPoint(
          index,
          const Offset(10, 10),
        )?.getAttribute(const SdQName('id')),
        'top',
      );
    });

    test('a stroke-only (fill:none) shape is hittable near its outline, not far from it', () {
      final doc = _parse(
        '<line id="wire" x1="0" y1="0" x2="100" y2="0" stroke="black" stroke-width="2"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      expect(
        hitTestPoint(
          index,
          const Offset(50, 0.5),
        )?.getAttribute(const SdQName('id')),
        'wire',
      );
      expect(hitTestPoint(index, const Offset(50, 50), tolerance: 3), isNull);
    });

    test('a click on a symbol instance selects the <use> element, not the shared definition', () {
      final doc = _parse('''
        <defs>
          <symbol id="sym" viewBox="0 0 10 10">
            <rect x="0" y="0" width="10" height="10" fill="green"/>
          </symbol>
        </defs>
        <use id="inst" href="#sym" width="10" height="10"/>
      ''');
      final index = SpatialIndex.build(buildScene(doc));
      final hit = hitTestPoint(index, const Offset(5, 5));
      expect(hit?.name.local, 'use');
      expect(hit?.getAttribute(const SdQName('id')), 'inst');
    });
  });

  group('hitTestRect (marquee)', () {
    test('includes every shape whose bbox intersects the marquee', () {
      final doc = _parse(
        '<rect id="a" x="0" y="0" width="10" height="10"/>'
        '<rect id="b" x="50" y="50" width="10" height="10"/>',
      );
      final index = SpatialIndex.build(buildScene(doc));
      final hits = hitTestRect(index, const Rect.fromLTWH(-5, -5, 20, 20));
      expect(hits.map((e) => e.getAttribute(const SdQName('id'))), ['a']);
    });
  });
}
