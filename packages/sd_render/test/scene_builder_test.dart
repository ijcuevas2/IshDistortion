import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdDocument _parse(String innerSvg) => parseSdDocument('''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
$innerSvg
</svg>
''');

void main() {
  group('buildScene', () {
    test('a plain rect becomes one leaf node with a fill path', () {
      final doc = _parse(
        '<rect x="0" y="0" width="10" height="20" fill="#ff0000"/>',
      );
      final root = buildScene(doc);
      final rectNode = root.children.single;
      expect(rectNode.fillPath, isNotNull);
      expect(rectNode.localBounds, const Rect.fromLTWH(0, 0, 10, 20));
      expect(rectNode.fillPaint!.color, const Color(0xFFFF0000));
    });

    test(
      'a foreign-namespace element and its subtree are skipped entirely',
      () {
        final doc = _parse(
          '<g><rect width="1" height="1"/>'
          '<foo:bar xmlns:foo="urn:example"><rect width="1" height="1"/></foo:bar></g>',
        );
        final group = buildScene(doc).children.single;
        // Only the plain <rect> should have made it into the scene.
        expect(group.children, hasLength(1));
      },
    );

    test('defs/symbol are invisible in normal flow but not when built as a use target', () {
      final doc = _parse('''
        <defs>
          <symbol id="sym" viewBox="0 0 10 10">
            <rect width="10" height="10" fill="#0000ff"/>
          </symbol>
        </defs>
        <use href="#sym" x="5" y="5" width="20" height="20"/>
      ''');
      final root = buildScene(doc);
      // <defs> itself renders nothing directly...
      final defsNode = root.children.firstWhere(
        (n) => n.element.name.local == 'defs',
      );
      expect(defsNode.children, isEmpty);

      // ...but the <use> instance resolves the symbol's content.
      final useNode = root.children.firstWhere(
        (n) => n.element.name.local == 'use',
      );
      expect(useNode.isSelectionBoundary, isTrue);
      expect(useNode.children, isNotEmpty);
    });

    test('<use> with width/height against a symbol viewBox scales to fit and centers', () {
      final doc = _parse('''
        <defs>
          <symbol id="sym" viewBox="0 0 10 10">
            <rect x="0" y="0" width="10" height="10"/>
          </symbol>
        </defs>
        <use href="#sym" width="20" height="20"/>
      ''');
      final root = buildScene(doc);
      final useNode = root.children.firstWhere(
        (n) => n.element.name.local == 'use',
      );
      // useNode -> symbol wrapper (no own geometry) -> the actual <rect>.
      final symbolNode = useNode.children.single;
      final rectNode = symbolNode.children.single;
      final worldTransform =
          useNode.transform * symbolNode.transform * rectNode.transform;
      final worldBounds = MatrixUtils.transformRect(
        worldTransform,
        rectNode.localBounds,
      );
      // 10x10 viewBox fit into a 20x20 box: scale 2, no centering offset needed.
      expect(worldBounds, const Rect.fromLTWH(0, 0, 20, 20));
    });

    test('a marker-end arrowhead is instantiated at the path end, oriented along it', () {
      final doc = _parse('''
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#000000"/>
          </marker>
        </defs>
        <line x1="0" y1="0" x2="100" y2="0" stroke="#000000" marker-end="url(#arrow)"/>
      ''');
      final lineNode = buildScene(doc).children
          .firstWhere((n) => n.element.name.local == 'line');
      expect(lineNode.children, hasLength(1));
      final markerNode = lineNode.children.single;
      // The marker's own ref point (9,5) — not its local origin, which
      // is offset from ref — must land exactly on the line's end (100,0).
      final refPoint = MatrixUtils.transformPoint(
        markerNode.transform,
        const Offset(9, 5),
      );
      expect(refPoint.dx, closeTo(100, 0.01));
      expect(refPoint.dy, closeTo(0, 0.01));
    });

    test('no marker-end attribute means no marker child is added', () {
      final doc = _parse(
        '<line x1="0" y1="0" x2="10" y2="0" stroke="#000000"/>',
      );
      final lineNode = buildScene(doc).children.single;
      expect(lineNode.children, isEmpty);
    });

    test('a self-referencing <use> cycle does not hang or crash', () {
      final doc = _parse('<g id="a"><use href="#a"/></g>');
      expect(() => buildScene(doc), returnsNormally);
    });

    test('fill inheritance flows from group to child during the build', () {
      final doc = _parse('<g fill="#00ff00"><rect width="1" height="1"/></g>');
      final group = buildScene(doc).children.single;
      final rect = group.children.single;
      expect(rect.fillPaint!.color, const Color(0xFF00FF00));
    });

    test(
      '<text> lays out its concatenated content at its own resolved fill color',
      () {
        final doc = _parse('<text x="5" y="10" fill="#123456">hi</text>');
        final textNode = buildScene(doc).children.single;
        expect(textNode.textPainter, isNotNull);
        expect(textNode.textPainter!.text, isA<TextSpan>());
        final span = textNode.textPainter!.text! as TextSpan;
        expect(span.text, 'hi');
        // Compare via the traditional 8-bit-per-channel int rather than
        // `Color` equality: the color went through a `.withValues(alpha:)`
        // round-trip (see SvgPaintState.fillPaint), whose double-precision
        // components can differ from a `Color(0xAARRGGBB)` literal's in the
        // last bit despite being visually and semantically identical.
        expect(span.style!.color!.toARGB32(), 0xFF123456);
      },
    );
  });
}
