import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('spectrogramMagnitudeRange', () {
    test('an empty list of frames returns the fallback unchanged', () {
      expect(spectrogramMagnitudeRange(const [], fallback: (-40, 40)), (
        -40.0,
        40.0,
      ));
    });

    test('excludes -infinity (an exact-zero bin) from the range', () {
      const frames = [
        SpectrogramFrame(
          time: 0,
          magnitudesDb: [double.negativeInfinity, -6, 0],
        ),
      ];
      final (lo, hi) = spectrogramMagnitudeRange(frames, fallback: (-1, 1));
      // -infinity must not have dragged lo down to -infinity/hugely
      // negative — it was excluded before bodeAxisRange ever saw it.
      expect(lo.isFinite, isTrue);
      expect(lo, greaterThan(-100));
      expect(hi, greaterThan(0));
    });

    test('spans the finite magnitudes across every frame, padded', () {
      const frames = [
        SpectrogramFrame(time: 0, magnitudesDb: [0, 10]),
        SpectrogramFrame(time: 1, magnitudesDb: [-20, 5]),
      ];
      final (lo, hi) = spectrogramMagnitudeRange(frames, fallback: (-1, 1));
      expect(lo, lessThan(-20));
      expect(hi, greaterThan(10));
    });
  });

  group('spectrogramHeatColor', () {
    test('the low end of the range maps to the dark-blue endpoint', () {
      expect(spectrogramHeatColor(-80, -80, 0), const Color(0xFF0D1B4C));
    });

    test('the high end of the range maps to the bright-yellow endpoint', () {
      expect(spectrogramHeatColor(0, -80, 0), const Color(0xFFFFE066));
    });

    test('values outside the range are clamped, not extrapolated', () {
      expect(spectrogramHeatColor(-200, -80, 0), const Color(0xFF0D1B4C));
      expect(spectrogramHeatColor(200, -80, 0), const Color(0xFFFFE066));
    });

    test('a degenerate (lo >= hi) range still returns a color, not a '
        'divide-by-zero crash', () {
      expect(spectrogramHeatColor(5, 5, 5), const Color(0xFF0D1B4C));
    });
  });

  group('SpectrogramPainter', () {
    Widget harness(List<SpectrogramFrame>? frames) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 150,
        child: CustomPaint(painter: SpectrogramPainter(frames: frames)),
      ),
    );

    testWidgets('renders without error for null frames', (tester) async {
      await tester.pumpWidget(harness(null));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for an empty list', (tester) async {
      await tester.pumpWidget(harness(const []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without error for a populated spectrogram', (
      tester,
    ) async {
      final h = const ZPowExpr(-1) / const ConstExpr(2);
      final frames = computeSpectrogram(
        h,
        sampleCount: 128,
        windowSize: 32,
        hopSize: 16,
      );
      await tester.pumpWidget(harness(frames));
      expect(tester.takeException(), isNull);
    });
  });
}
