import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

Path? _shape(String tag, Map<String, String> attrs) => svgShapeToPath(
  SdElement(
    SdQName(tag),
    attributes: {for (final e in attrs.entries) SdQName(e.key): e.value},
  ),
);

void main() {
  group('svgShapeToPath', () {
    test('rect', () {
      expect(
        _shape('rect', {
          'x': '1',
          'y': '2',
          'width': '3',
          'height': '4',
        })!.getBounds(),
        const Rect.fromLTWH(1, 2, 3, 4),
      );
    });

    test('rect with zero size is empty, not null', () {
      expect(
        _shape('rect', {'width': '0', 'height': '0'})!.getBounds(),
        Rect.zero,
      );
    });

    test('rounded rect clamps rx/ry to half the box', () {
      final path = _shape('rect', {
        'width': '10',
        'height': '10',
        'rx': '100',
      })!;
      // Clamped to 5 (half of 10): bounds should still be the full box.
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 10, 10));
    });

    test('circle', () {
      expect(
        _shape('circle', {'cx': '5', 'cy': '5', 'r': '5'})!.getBounds(),
        const Rect.fromLTWH(0, 0, 10, 10),
      );
    });

    test('ellipse', () {
      expect(
        _shape('ellipse', {
          'cx': '0',
          'cy': '0',
          'rx': '3',
          'ry': '2',
        })!.getBounds(),
        const Rect.fromLTWH(-3, -2, 6, 4),
      );
    });

    test('line has zero-area bounds along its own direction', () {
      expect(
        _shape('line', {
          'x1': '0',
          'y1': '0',
          'x2': '10',
          'y2': '0',
        })!.getBounds(),
        const Rect.fromLTWH(0, 0, 10, 0),
      );
    });

    test('polygon closes back to its first point', () {
      final path = svgShapeToPath(
        SdElement(
          const SdQName('polygon'),
          attributes: {const SdQName('points'): '0,0 10,0 10,10'},
        ),
      )!;
      expect(path.contains(const Offset(9, 9)), isTrue);
    });

    test('an element with no shape mapping returns null', () {
      expect(svgShapeToPath(SdElement(const SdQName('g'))), isNull);
    });
  });
}
