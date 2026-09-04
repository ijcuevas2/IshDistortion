import 'dart:math' as math;

import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

void main() {
  group('simulateDifferenceEquation', () {
    test('a pure gain scales the input sample by sample', () {
      final output = simulateDifferenceEquation(const ConstExpr(3), [
        1,
        2,
        3,
        4,
      ])!;
      expect(output, [3, 6, 9, 12]);
    });

    test('a pure unit delay shifts the input by one sample', () {
      final output = simulateDifferenceEquation(const ZPowExpr(-1), [
        1,
        2,
        3,
        4,
      ])!;
      expect(output, [0, 1, 2, 3]);
    });

    test('a double delay shifts the input by two samples', () {
      final output = simulateDifferenceEquation(const ZPowExpr(-2), [
        1,
        2,
        3,
        4,
        5,
      ])!;
      expect(output, [0, 0, 1, 2, 3]);
    });

    test('a one-pole IIR (y[n] = x[n] + 0.5*y[n-1]) matches a hand-computed '
        'geometric decay', () {
      // H(z) = 1 / (1 - 0.5*z^-1).
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const ConstExpr(-0.5), const ZPowExpr(-1)]),
        ]),
      );
      final output = simulateDifferenceEquation(h, [1, 0, 0, 0, 0])!;
      expect(output[0], closeTo(1, 1e-9));
      expect(output[1], closeTo(0.5, 1e-9));
      expect(output[2], closeTo(0.25, 1e-9));
      expect(output[3], closeTo(0.125, 1e-9));
      expect(output[4], closeTo(0.0625, 1e-9));
    });

    test('resolves bound symbols the same way computePoleZero does', () {
      const h = SymbolExpr('k');
      expect(simulateDifferenceEquation(h, [1, 2, 3]), isNull);
      expect(simulateDifferenceEquation(h, [1, 2, 3], bindings: {'k': 2})!, [
        2,
        4,
        6,
      ]);
    });

    test('returns null for a non-causal H(z) whose denominator has no '
        'z^-0 term', () {
      // H(z) = 1 / z^-1 = z: an acausal predictor, not a realizable
      // filter — a[0] (the denominator's own constant term) is exactly
      // 0 here since the denominator is bare z^-1.
      final h = divExpr(const ConstExpr(1), const ZPowExpr(-1));
      expect(simulateDifferenceEquation(h, [1, 2, 3]), isNull);
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(simulateDifferenceEquation(h, [1, 2, 3]), isNull);
      },
    );
  });

  group('computeImpulseResponse', () {
    test('rejects a sampleCount less than 1', () {
      expect(
        () => computeImpulseResponse(const ConstExpr(1), sampleCount: 0),
        throwsArgumentError,
      );
    });

    test('a pure gain: c at n=0, zero everywhere after', () {
      final samples = computeImpulseResponse(
        const ConstExpr(3),
        sampleCount: 5,
      )!;
      expect(samples.map((s) => s.value), [3, 0, 0, 0, 0]);
      expect(samples.map((s) => s.n), [0, 1, 2, 3, 4]);
    });

    test('a pure k-sample delay: a single 1 at n=k, zero elsewhere', () {
      for (final k in [1, 2, 3]) {
        final samples = computeImpulseResponse(ZPowExpr(-k), sampleCount: 5)!;
        for (var n = 0; n < samples.length; n++) {
          expect(samples[n].value, n == k ? 1 : 0, reason: 'k=$k n=$n');
        }
      }
    });

    test('a one-pole IIR matches the hand-computed geometric decay '
        '(the same case simulateDifferenceEquation\'s own test uses)', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const ConstExpr(-0.5), const ZPowExpr(-1)]),
        ]),
      );
      final samples = computeImpulseResponse(h, sampleCount: 5)!;
      for (var n = 0; n < samples.length; n++) {
        expect(samples[n].value, closeTo(math.pow(0.5, n).toDouble(), 1e-9));
      }
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeImpulseResponse(h), isNull);
      },
    );
  });

  group('computeStepResponse', () {
    test('rejects a sampleCount less than 1', () {
      expect(
        () => computeStepResponse(const ConstExpr(1), sampleCount: 0),
        throwsArgumentError,
      );
    });

    test('a pure gain: constant c at every sample', () {
      final samples = computeStepResponse(const ConstExpr(3), sampleCount: 4)!;
      expect(samples.map((s) => s.value), [3, 3, 3, 3]);
    });

    test('a one-pole IIR matches the closed-form geometric partial sum '
        'y[n] = (1 - a^(n+1)) / (1 - a)', () {
      const a = 0.5;
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const ConstExpr(-a), const ZPowExpr(-1)]),
        ]),
      );
      final samples = computeStepResponse(h, sampleCount: 6)!;
      for (var n = 0; n < samples.length; n++) {
        final expected = (1 - math.pow(a, n + 1)) / (1 - a);
        expect(samples[n].value, closeTo(expected.toDouble(), 1e-9));
      }
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeStepResponse(h), isNull);
      },
    );
  });

  group('dft', () {
    test('a DC (constant) signal has energy only at bin 0', () {
      final spectrum = dft(List.filled(8, 2.0));
      expect(spectrum[0].abs(), closeTo(16, 1e-9)); // sum of all samples.
      for (var k = 1; k < spectrum.length; k++) {
        expect(spectrum[k].abs(), closeTo(0, 1e-9));
      }
    });

    test('a bin-aligned sinusoid peaks exactly at its own bin', () {
      const n = 16;
      const targetBin = 3;
      final signal = [
        for (var t = 0; t < n; t++) math.sin(2 * math.pi * targetBin * t / n),
      ];
      final spectrum = dft(signal);
      final magnitudes = spectrum.map((c) => c.abs()).toList();

      final peakBin = List.generate(
        n ~/ 2 + 1,
        (i) => i,
      ).reduce((a, b) => magnitudes[a] >= magnitudes[b] ? a : b);
      expect(peakBin, targetBin);
    });
  });

  group('generateChirp', () {
    test('rejects fewer than 2 samples', () {
      expect(() => generateChirp(1), throwsArgumentError);
    });

    test('starts at zero and has the requested length', () {
      final chirp = generateChirp(100);
      expect(chirp, hasLength(100));
      expect(chirp[0], closeTo(0, 1e-9));
    });

    test('its instantaneous frequency actually increases over time, per '
        'the dft of successive windows', () {
      const sampleCount = 400;
      const windowSize = 40;
      final chirp = generateChirp(sampleCount);

      int peakBinOfWindow(int start) {
        final window = chirp.sublist(start, start + windowSize);
        final magnitudes = dft(window).map((c) => c.abs()).toList();
        const half = windowSize ~/ 2;
        return List.generate(
          half,
          (i) => i,
        ).reduce((a, b) => magnitudes[a] >= magnitudes[b] ? a : b);
      }

      final earlyPeak = peakBinOfWindow(0);
      final latePeak = peakBinOfWindow(sampleCount - windowSize);
      expect(latePeak, greaterThan(earlyPeak));
    });
  });

  group('computeSpectrogram', () {
    test('rejects an invalid windowSize', () {
      expect(
        () => computeSpectrogram(const ConstExpr(1), windowSize: 1),
        throwsArgumentError,
      );
      expect(
        () => computeSpectrogram(
          const ConstExpr(1),
          windowSize: 1000,
          sampleCount: 512,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an invalid hopSize', () {
      expect(
        () => computeSpectrogram(const ConstExpr(1), hopSize: 0),
        throwsArgumentError,
      );
    });

    test(
      'returns null for a shape that is not a clean rational polynomial',
      () {
        final h = addExpr([const ConstExpr(1), const SymbolExpr('unbound')]);
        expect(computeSpectrogram(h), isNull);
      },
    );

    test('every frame reports one-sided bins (windowSize/2 + 1 of them)', () {
      final frames = computeSpectrogram(
        const ConstExpr(1),
        sampleCount: 200,
        windowSize: 32,
        hopSize: 16,
      )!;
      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.magnitudesDb, hasLength(32 ~/ 2 + 1));
      }
    });

    test('a pure gain shifts every magnitude by exactly 20*log10(gain) dB, '
        'relative to unity gain', () {
      const gain = 4.0;
      final unity = computeSpectrogram(
        const ConstExpr(1),
        sampleCount: 200,
        windowSize: 32,
        hopSize: 16,
      )!;
      final scaled = computeSpectrogram(
        const ConstExpr(gain),
        sampleCount: 200,
        windowSize: 32,
        hopSize: 16,
      )!;
      final expectedShiftDb = 20 * (math.log(gain) / math.ln10);

      expect(scaled.length, unity.length);
      for (var f = 0; f < unity.length; f++) {
        for (var k = 0; k < unity[f].magnitudesDb.length; k++) {
          final unityDb = unity[f].magnitudesDb[k];
          final scaledDb = scaled[f].magnitudesDb[k];
          if (unityDb.isFinite) {
            expect(scaledDb - unityDb, closeTo(expectedShiftDb, 1e-6));
          }
        }
      }
    });

    test('a strongly low-pass filter shows more energy in early (low chirp '
        'frequency) frames than late (high chirp frequency) frames', () {
      // H(z) = 1 / (1 - 0.9*z^-1): a heavily low-pass-leaning single
      // pole, close to the unit circle.
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const ConstExpr(-0.9), const ZPowExpr(-1)]),
        ]),
      );
      final frames = computeSpectrogram(
        h,
        sampleCount: 800,
        windowSize: 64,
        hopSize: 32,
      )!;

      double peakDb(SpectrogramFrame frame) =>
          frame.magnitudesDb.reduce(math.max);

      final earlyPeak = peakDb(frames.first);
      final latePeak = peakDb(frames.last);
      expect(earlyPeak, greaterThan(latePeak));
    });
  });
}
