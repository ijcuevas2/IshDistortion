import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('parseSvgPathData', () {
    test('moveto + lineto, absolute', () {
      final path = parseSvgPathData('M0,0 L10,0 L10,10 Z');
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1));
      expect(path.contains(const Offset(5, 5)), isTrue);
      expect(path.contains(const Offset(20, 20)), isFalse);
    });

    test('relative commands accumulate from the current point', () {
      final abs = parseSvgPathData('M10,10 L20,10 L20,20 Z');
      final rel = parseSvgPathData('M10,10 l10,0 l0,10 z');
      expect(rel.getBounds(), abs.getBounds());
    });

    test('repeated coordinate pairs after M are implicit lineto', () {
      // "M0,0 10,0 10,10" == "M0,0 L10,0 L10,10"
      final implicit = parseSvgPathData('M0,0 10,0 10,10');
      final explicit = parseSvgPathData('M0,0 L10,0 L10,10');
      expect(implicit.getBounds(), explicit.getBounds());
    });

    test('H and V move only one axis', () {
      final path = parseSvgPathData('M5,5 H20 V30');
      expect(path.getBounds(), const Rect.fromLTWH(5, 5, 15, 25));
    });

    test('S reflects the previous C control point', () {
      // A symmetric S-curve: the second cubic's implicit first control
      // point should be the reflection of the first cubic's second one
      // through the shared endpoint, keeping the curve tangent-continuous
      // (and, for this particular symmetric case, keeping it inside a
      // predictable bounding box rather than kinking sharply outward).
      final path = parseSvgPathData('M0,0 C0,10 10,10 10,0 S20,-10 20,0');
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(0, 0.01));
      expect(bounds.right, closeTo(20, 0.01));
    });

    test('S with no preceding C/S uses the current point as its control', () {
      final withPriorCurve = parseSvgPathData('M0,0 S10,10 20,0');
      // No preceding curve command at all: first control == current point.
      expect(() => withPriorCurve.computeMetrics().toList(), returnsNormally);
    });

    test('T reflects the previous Q control point', () {
      final path = parseSvgPathData('M0,0 Q5,10 10,0 T20,0');
      expect(() => path.computeMetrics().toList(), returnsNormally);
      expect(path.getBounds().right, closeTo(20, 0.01));
    });

    test('A (arc) reaches its endpoint', () {
      final path = parseSvgPathData('M0,0 A5,5 0 0 1 10,0');
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(0, 0.01));
      expect(bounds.right, closeTo(10, 0.01));
    });

    test('a zero-radius arc degrades to a straight line', () {
      final path = parseSvgPathData('M0,0 A0,0 0 0 1 10,10');
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 10, 10));
    });

    test('Z closes back to the subpath start, and a subsequent L is fresh', () {
      final path = parseSvgPathData('M0,0 L10,0 L10,10 Z M0,0 L5,5');
      // Two subpaths.
      expect(path.computeMetrics().length, 2);
    });

    test('multiple numbers with no separator between commands still parse', () {
      // A common minifier output style: no space before a negative number.
      final path = parseSvgPathData('M0,0L10,0L10-10Z');
      expect(path.getBounds(), const Rect.fromLTWH(0, -10, 10, 10));
    });

    test('throws SvgPathParseException on malformed data', () {
      expect(
        () => parseSvgPathData('M0,0 Q1'),
        throwsA(isA<SvgPathParseException>()),
      );
      expect(
        () => parseSvgPathData('X0,0'),
        throwsA(isA<SvgPathParseException>()),
      );
    });

    test('arc flags parse even when jammed together with no separator', () {
      // "1150,50" must parse as flags 1,1 then x=50 — not the number 1150.
      final path = parseSvgPathData('M0,0 A5,5,0,1150,50');
      expect(path.getBounds().right, greaterThanOrEqualTo(50));
    });
  });

  group('parseSvgPointList', () {
    test('parses a flat comma/space list pairwise', () {
      expect(parseSvgPointList('0,0 10,0 10,10'), const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
      ]);
    });

    test('rejects an odd number of coordinates', () {
      expect(
        () => parseSvgPointList('0,0 10'),
        throwsA(isA<SvgPathParseException>()),
      );
    });
  });
}
