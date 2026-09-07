import 'package:sd_ink/sd_ink.dart';
import 'package:test/test.dart';

StrokePoint pt(double x, double y, {double? pressure}) =>
    StrokePoint(x: x, y: y, pressure: pressure);

void main() {
  group('movingAverageSmooth', () {
    test('leaves the first and last points exactly as sampled', () {
      final points = [pt(0, 0), pt(1, 5), pt(2, -5), pt(3, 5), pt(4, 0)];
      final result = movingAverageSmooth(points, windowSize: 3);
      expect(result.first.x, points.first.x);
      expect(result.first.y, points.first.y);
      expect(result.last.x, points.last.x);
      expect(result.last.y, points.last.y);
    });

    test('a collinear run of points is unchanged by smoothing', () {
      final points = [for (var i = 0; i <= 5; i++) pt(i.toDouble(), 0)];
      final result = movingAverageSmooth(points, windowSize: 3);
      for (var i = 0; i < points.length; i++) {
        expect(result[i].x, closeTo(points[i].x, 1e-9));
        expect(result[i].y, closeTo(0, 1e-9));
      }
    });

    test('pulls a single spike toward its neighbors', () {
      final points = [pt(0, 0), pt(1, 0), pt(2, 100), pt(3, 0), pt(4, 0)];
      final result = movingAverageSmooth(points, windowSize: 3);
      expect(result[2].y, lessThan(100));
      expect(result[2].y, greaterThan(0));
    });

    test('fewer than 3 points is returned unchanged', () {
      final points = [pt(0, 0), pt(1, 1)];
      expect(movingAverageSmooth(points), points);
    });
  });

  group('simplifyRdp', () {
    test('removes exactly-collinear interior points', () {
      final points = [pt(0, 0), pt(1, 0), pt(2, 0), pt(3, 0)];
      final result = simplifyRdp(points, epsilon: 0.01);
      expect(result, [points.first, points.last]);
    });

    test('keeps a real corner beyond epsilon', () {
      final points = [pt(0, 0), pt(5, 5), pt(10, 0)];
      final result = simplifyRdp(points, epsilon: 0.5);
      expect(
        result,
        points,
      ); // the corner at (5,5) is far from the (0,0)-(10,0) line
    });

    test('a corner within epsilon is still simplified away', () {
      final points = [pt(0, 0), pt(5, 0.01), pt(10, 0)];
      final result = simplifyRdp(points, epsilon: 1.0);
      expect(result, [points.first, points.last]);
    });

    test('always keeps both endpoints, even for a degenerate loop', () {
      final points = [pt(0, 0), pt(5, 5), pt(0, 0)];
      final result = simplifyRdp(points, epsilon: 100);
      expect(result.first, points.first);
      expect(result.last, points.last);
    });
  });

  group('fitCatmullRom', () {
    test('passes through every original point exactly at span boundaries', () {
      final points = [pt(0, 0), pt(10, 5), pt(20, -5), pt(30, 0)];
      final result = fitCatmullRom(points, samplesPerSpan: 4);
      // Span boundaries land at indices 0, 4, 8, 12 for 3 spans * 4 samples.
      for (var i = 0; i < points.length; i++) {
        final boundary = result[i * 4];
        expect(boundary.x, closeTo(points[i].x, 1e-9));
        expect(boundary.y, closeTo(points[i].y, 1e-9));
      }
    });

    test('produces (n-1)*samplesPerSpan + 1 points', () {
      final points = [pt(0, 0), pt(1, 1), pt(2, 0), pt(3, 1), pt(4, 0)];
      final result = fitCatmullRom(points, samplesPerSpan: 6);
      expect(result, hasLength((points.length - 1) * 6 + 1));
    });

    test('interpolated pressure stays within the sampled range', () {
      final points = [
        pt(0, 0, pressure: 0.2),
        pt(1, 0, pressure: 0.8),
        pt(2, 0, pressure: 0.2),
      ];
      final result = fitCatmullRom(points, samplesPerSpan: 10);
      for (final p in result) {
        expect(p.pressure, inInclusiveRange(0.0, 1.0));
      }
    });

    test('fewer than 3 points is returned unchanged (no span to fit)', () {
      final points = [pt(0, 0), pt(1, 1)];
      expect(fitCatmullRom(points), points);
    });
  });
}
