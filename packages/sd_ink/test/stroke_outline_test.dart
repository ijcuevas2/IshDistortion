import 'package:sd_ink/sd_ink.dart';
import 'package:test/test.dart';

/// Extracts every `x,y` pair following an `M` or `L` command, in order —
/// enough to fully recover the vertex list of a straight-segment polygon
/// path, which is all [buildStrokeOutlinePath] ever emits for a 2+-point
/// centerline (its `A` commands only ever appear in the single-point "dot"
/// case, checked separately below without this helper).
List<(double, double)> vertices(String path) {
  final matches = RegExp(r'[ML]\s*(-?[\d.]+),(-?[\d.]+)').allMatches(path);
  return [
    for (final m in matches)
      (double.parse(m.group(1)!), double.parse(m.group(2)!)),
  ];
}

void expectVertex((double, double) actual, double x, double y) {
  expect(actual.$1, closeTo(x, 1e-6));
  expect(actual.$2, closeTo(y, 1e-6));
}

void main() {
  group('buildStrokeOutlinePath', () {
    const curve = PressureCurve(minWidthFraction: 0.2, maxWidthFraction: 1.35);

    test('empty centerline produces an empty path', () {
      expect(
        buildStrokeOutlinePath([], pressureCurve: curve, nominalWidth: 10),
        isEmpty,
      );
    });

    test('a single point produces a filled circle of the right radius', () {
      final path = buildStrokeOutlinePath(
        [const StrokePoint(x: 5, y: 5, pressure: 1)],
        pressureCurve: curve,
        nominalWidth: 10,
      );
      final r = curve.widthFor(1, 10) / 2; // 6.75
      expect(path, startsWith('M'));
      expect(path, contains('A'));
      expect(path, contains('${5 - r},5')); // leftmost point of the circle
      expect(path, contains('${5 + r},5')); // rightmost point
    });

    test(
      'a straight, constant-pressure horizontal stroke is exactly a rectangle',
      () {
        // Hand-derived: 3 collinear points along +x, pressure 1 throughout
        // -> width = maxWidthFraction * nominalWidth = 1.35*10 = 13.5,
        // half-width 6.75. Tangent is (1,0) everywhere on a straight line,
        // so the perpendicular offset is purely vertical.
        final centerline = [
          const StrokePoint(x: 0, y: 0, pressure: 1),
          const StrokePoint(x: 10, y: 0, pressure: 1),
          const StrokePoint(x: 20, y: 0, pressure: 1),
        ];
        final path = buildStrokeOutlinePath(
          centerline,
          pressureCurve: curve,
          nominalWidth: 10,
        );
        expect(path, endsWith('Z'));

        const halfWidth = 6.75;
        final vs = vertices(path);
        expect(vs, hasLength(6)); // 3 left rail + 3 right rail

        // Left rail: forward along the top edge.
        expectVertex(vs[0], 0, halfWidth);
        expectVertex(vs[1], 10, halfWidth);
        expectVertex(vs[2], 20, halfWidth);
        // Right rail: backward along the bottom edge.
        expectVertex(vs[3], 20, -halfWidth);
        expectVertex(vs[4], 10, -halfWidth);
        expectVertex(vs[5], 0, -halfWidth);
      },
    );

    test('a thin-pressure midpoint pinches the outline in at that point', () {
      final centerline = [
        const StrokePoint(x: 0, y: 0, pressure: 1),
        const StrokePoint(x: 10, y: 0, pressure: 0), // thinnest allowed
        const StrokePoint(x: 20, y: 0, pressure: 1),
      ];
      final path = buildStrokeOutlinePath(
        centerline,
        pressureCurve: curve,
        nominalWidth: 10,
      );
      final vs = vertices(path);
      final endHalfWidth = curve.widthFor(1, 10) / 2;
      final midHalfWidth = curve.widthFor(0, 10) / 2;
      expect(midHalfWidth, lessThan(endHalfWidth));

      // vs[1] is the left-rail sample at the pinched midpoint.
      expect(vs[1].$2, closeTo(midHalfWidth, 1e-6));
      expect(vs[0].$2, closeTo(endHalfWidth, 1e-6));
    });
  });
}
