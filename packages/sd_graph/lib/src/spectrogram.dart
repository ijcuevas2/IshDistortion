import 'dart:math' as math;

import 'complex.dart';
import 'expression.dart';
import 'pole_zero.dart';

/// Simulates the causal IIR/FIR recursion `H(z)` describes against a real
/// [input] signal, sample by sample, returning the same-length output
/// signal — unlike every other analysis in this library
/// ([computeTransferFunction], [computePoleZero], [computeBodePlot],
/// [computeNyquistPlot]), which only ever *evaluates* `H` symbolically or
/// at specific frequency points, a spectrogram needs an actual time-
/// domain signal to analyze (see [computeSpectrogram]'s own doc comment
/// on why that makes it a fundamentally different kind of feature from
/// the others, not just "one more plot").
///
/// Reads `H(z)` via [rationalPolynomials] (the same `z^-1`-power sparse
/// maps [computeBodePlot]/[computeNyquistPlot] evaluate at points) as
/// `H(z) = B(z^-1) / A(z^-1)`, converts each to a dense, `a[0]`-
/// normalized coefficient array, and runs the standard direct-form
/// recursion:
/// `y[n] = (1/a[0]) * (sum_k b[k]*x[n-k] - sum_{k>=1} a[k]*y[n-k])`
/// (samples before index 0 are treated as zero — the filter starts at
/// rest). [bindings]/return-`null` semantics are otherwise identical to
/// [computePoleZero]: an unbound coefficient symbol, or a shape that
/// isn't a clean ratio of polynomials, means there's nothing concrete to
/// simulate.
///
/// Also returns `null` if `A`'s own `z^-0` coefficient is exactly zero —
/// every block this project's stencils can produce keeps that
/// coefficient at a nonzero (typically `1`) value (a genuine, physically
/// causal/realizable filter always does), so this is a defensive guard
/// against a pathological, not-actually-causal `H(z)` rather than a case
/// expected to occur for a diagram built from real stencils.
List<double>? simulateDifferenceEquation(
  Expr h,
  List<double> input, {
  Map<String, num> bindings = const {},
}) {
  final rational = rationalPolynomials(h, bindings);
  if (rational == null) return null;

  final b = _denseCoefficients(rational.numerator);
  final a = _denseCoefficients(rational.denominator);
  if (a[0] == 0) return null;

  final output = List<double>.filled(input.length, 0);
  for (var n = 0; n < input.length; n++) {
    var acc = 0.0;
    for (var k = 0; k < b.length; k++) {
      if (n - k >= 0) acc += b[k] * input[n - k];
    }
    for (var k = 1; k < a.length; k++) {
      if (n - k >= 0) acc -= a[k] * output[n - k];
    }
    output[n] = acc / a[0];
  }
  return output;
}

/// One sample of an impulse- or step-response plot (§5.11's "Analysis
/// Plot — impulse/step stem" — conventionally drawn as a stem/lollipop
/// plot, one vertical line per sample, rather than a connected curve).
class ImpulseResponseSample {
  const ImpulseResponseSample({required this.n, required this.value});

  /// The sample index.
  final int n;

  final double value;
}

/// Computes [h]'s impulse response (§5.11): its output when driven by a
/// unit impulse (`x[0] = 1`, `x[n] = 0` for `n > 0`) — literally just
/// [simulateDifferenceEquation] fed that one specific signal, since an
/// impulse response *is*, by definition, `H(z)`'s own difference
/// equation's reaction to an impulse. [bindings]/return-`null` semantics
/// are identical to [simulateDifferenceEquation].
List<ImpulseResponseSample>? computeImpulseResponse(
  Expr h, {
  Map<String, num> bindings = const {},
  int sampleCount = 50,
}) {
  if (sampleCount < 1) {
    throw ArgumentError.value(sampleCount, 'sampleCount', 'must be at least 1');
  }
  final impulse = List<double>.generate(sampleCount, (n) => n == 0 ? 1.0 : 0.0);
  final response = simulateDifferenceEquation(h, impulse, bindings: bindings);
  if (response == null) return null;
  return [
    for (var n = 0; n < response.length; n++)
      ImpulseResponseSample(n: n, value: response[n]),
  ];
}

/// Computes [h]'s step response (§5.11): its output when driven by a
/// unit step (`x[n] = 1` for every `n >= 0`) — the same "just feed
/// [simulateDifferenceEquation] a specific signal" shape as
/// [computeImpulseResponse], fed a different one. [bindings]/return-
/// `null` semantics are identical to [simulateDifferenceEquation].
List<ImpulseResponseSample>? computeStepResponse(
  Expr h, {
  Map<String, num> bindings = const {},
  int sampleCount = 50,
}) {
  if (sampleCount < 1) {
    throw ArgumentError.value(sampleCount, 'sampleCount', 'must be at least 1');
  }
  final step = List<double>.filled(sampleCount, 1.0);
  final response = simulateDifferenceEquation(h, step, bindings: bindings);
  if (response == null) return null;
  return [
    for (var n = 0; n < response.length; n++)
      ImpulseResponseSample(n: n, value: response[n]),
  ];
}

/// Converts a `z^-1`-power sparse map (as [rationalPolynomials] produces)
/// into a dense array indexed directly by power (`result[k]` is the
/// coefficient of `z^-k`), zero-filled wherever a power is absent. Unlike
/// `pole_zero.dart`'s `_clearedZPolynomial`, this does *not* shift powers
/// down to clear a common factor — a difference-equation simulation
/// starts indexing at `z^-0` by definition (that's literally "no delay",
/// i.e. the current sample), so there is nothing to clear.
List<double> _denseCoefficients(Map<int, num> sparse) {
  final maxPower = sparse.keys.fold(0, math.max);
  final result = List<double>.filled(maxPower + 1, 0);
  for (final entry in sparse.entries) {
    result[entry.key] = entry.value.toDouble();
  }
  return result;
}

/// Generates a linear chirp (a sinusoid whose instantaneous frequency
/// ramps linearly from `0` to `pi` rad/sample — DC to Nyquist, the same
/// range every other analysis in this library sweeps) over [sampleCount]
/// samples: `x[n] = sin(pi * n^2 / (2 * (sampleCount - 1)))`.
///
/// A chirp, not e.g. a single fixed-frequency tone or white noise, is
/// [computeSpectrogram]'s deliberate choice of default test signal — see
/// that function's own doc comment on why.
List<double> generateChirp(int sampleCount) {
  if (sampleCount < 2) {
    throw ArgumentError.value(sampleCount, 'sampleCount', 'must be at least 2');
  }
  return [
    for (var n = 0; n < sampleCount; n++)
      math.sin(math.pi * n * n / (2 * (sampleCount - 1))),
  ];
}

/// The direct ("naive"), `O(n^2)` discrete Fourier transform of [signal]:
/// `X[k] = sum_n signal[n] * e^{-j*2*pi*k*n/N}` for `k` in
/// `0 .. signal.length - 1`. Deliberately not an FFT — the window sizes
/// [computeSpectrogram] actually uses are small enough (tens to a few
/// hundred samples) that the simpler, directly-verifiable direct sum is
/// plenty fast, and there is no other need for a general FFT elsewhere
/// in this project yet.
List<Complex> dft(List<double> signal) {
  final n = signal.length;
  return [for (var k = 0; k < n; k++) _dftBin(signal, k, n)];
}

Complex _dftBin(List<double> signal, int k, int n) {
  var result = Complex.zero;
  for (var t = 0; t < n; t++) {
    final angle = -2 * math.pi * k * t / n;
    result =
        result + Complex(signal[t]) * Complex(math.cos(angle), math.sin(angle));
  }
  return result;
}

/// One time-frame's worth of frequency-magnitude data, as
/// [computeSpectrogram] returns a `List` of.
class SpectrogramFrame {
  const SpectrogramFrame({required this.time, required this.magnitudesDb});

  /// The sample index at the *center* of this frame's analysis window.
  final int time;

  /// `20*log10(|X[k]|)` for each one-sided frequency bin `k` (index `0`
  /// is DC; the last index is the Nyquist bin) — `-infinity` at an exact
  /// zero, the same honest-not-clamped convention [BodePoint.magnitudeDb]
  /// documents.
  final List<double> magnitudesDb;
}

/// A spectrogram (§5.11's "Analysis Plot — spectrogram): magnitude vs.
/// time *and* frequency, unlike every other §5.11 plot (pole-zero, Bode,
/// Nyquist), which characterize `H(z)` itself and need no actual signal
/// at all. A spectrogram is fundamentally a property of a *signal*, not
/// of a transfer function alone — so this manufactures one: [h]'s
/// response to a linear chirp ([generateChirp], sweeping DC to Nyquist
/// over [sampleCount] samples) via [simulateDifferenceEquation], then a
/// short-time Fourier transform (a Hann-windowed [dft] per frame) of
/// that response.
///
/// A chirp is the deliberate choice of input here, not e.g. white noise
/// or silence: driving *any* LTI filter with a full-spectrum sweep and
/// watching which frequencies survive at which output *times* is a
/// standard way to visualize a filter's own frequency response — for a
/// filter whose passband only covers part of `[0, pi]`, the spectrogram
/// visibly shows the chirp fading in and out as its instantaneous
/// frequency sweeps into and out of that passband, in a way a single
/// static number (a Bode magnitude curve) doesn't make as immediately
/// visible.
///
/// Frames overlap by [windowSize] - [hopSize] samples, each Hann-
/// windowed before its [dft] (reducing the spectral leakage a bare
/// rectangular window would otherwise show at each frame's edges) and
/// reported one-sided (bins `0` through `windowSize ~/ 2`, since the
/// signal itself is real-valued and its spectrum is otherwise
/// conjugate-symmetric — the same reasoning [computeNyquistPlot] uses
/// the *other* direction, to avoid computing a redundant negative-
/// frequency half).
///
/// [bindings]/return-`null` semantics are identical to
/// [simulateDifferenceEquation] (in turn identical to [computePoleZero]).
List<SpectrogramFrame>? computeSpectrogram(
  Expr h, {
  Map<String, num> bindings = const {},
  int sampleCount = 512,
  int windowSize = 64,
  int hopSize = 32,
}) {
  if (windowSize < 2 || windowSize > sampleCount) {
    throw ArgumentError.value(
      windowSize,
      'windowSize',
      'must be at least 2 and at most sampleCount',
    );
  }
  if (hopSize < 1) {
    throw ArgumentError.value(hopSize, 'hopSize', 'must be at least 1');
  }

  final chirp = generateChirp(sampleCount);
  final response = simulateDifferenceEquation(h, chirp, bindings: bindings);
  if (response == null) return null;

  final window = [
    for (var n = 0; n < windowSize; n++)
      0.5 * (1 - math.cos(2 * math.pi * n / (windowSize - 1))),
  ];

  final frames = <SpectrogramFrame>[];
  for (var start = 0; start + windowSize <= response.length; start += hopSize) {
    final windowed = [
      for (var n = 0; n < windowSize; n++) response[start + n] * window[n],
    ];
    final spectrum = dft(windowed);
    final oneSidedCount = windowSize ~/ 2 + 1;
    frames.add(
      SpectrogramFrame(
        time: start + windowSize ~/ 2,
        magnitudesDb: [
          for (var k = 0; k < oneSidedCount; k++)
            20 * (math.log(spectrum[k].abs()) / math.ln10),
        ],
      ),
    );
  }
  return frames;
}
