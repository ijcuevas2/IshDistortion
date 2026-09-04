import 'dart:math' as math;

import 'complex.dart';
import 'expression.dart';
import 'pole_zero.dart';

/// One sample of a Bode plot (§5.11's "Analysis Plot — Bode").
class BodePoint {
  const BodePoint({
    required this.omega,
    required this.magnitudeDb,
    required this.phaseDegrees,
  });

  /// Normalized angular frequency, radians/sample, in `[0, pi]` — `pi` is
  /// the Nyquist frequency regardless of any particular sample rate. A
  /// caller that knows a sample rate can convert:
  /// `hz = omega / math.pi * sampleRate / 2`.
  final double omega;

  /// `20 * log10(|H(e^{j*omega})|)`. `-infinity` at an exact zero on the
  /// unit circle (e.g. a notch filter's null) is the mathematically
  /// correct answer, not a bug — a plot of this needs to clamp its own
  /// axis range rather than expect every value to be finite.
  final double magnitudeDb;

  /// `arg(H(e^{j*omega}))` in degrees, unwrapped across the whole sweep
  /// (see [computeBodePlot]) so it reads as a continuous curve instead of
  /// sawtoothing at every +/-180 degree crossing.
  final double phaseDegrees;
}

/// Computes a Bode plot (§5.11) of [h]: magnitude (dB) and unwrapped
/// phase (degrees) of `H(e^{j*omega})` at [pointCount] evenly spaced
/// frequencies from `0` to `pi` radians/sample (DC to Nyquist).
///
/// Unlike a classical continuous-time Bode plot's log-frequency axis
/// (meant to span many decades from near-DC out past a system's corner
/// frequencies), a discrete-time transfer function's meaningful domain is
/// the single finite interval `[0, pi]` — so this sweeps it linearly, the
/// conventional axis for a digital filter's frequency response (e.g.
/// MATLAB's `freqz`), not a continuous-time Bode plot's log axis.
///
/// [bindings] resolves any unbound coefficient symbols, same as
/// [computePoleZero] — a concrete numeric response needs concrete
/// numbers, unlike Mason's formula itself, which stays meaningful fully
/// symbolic. Returns `null` under the same circumstances
/// [computePoleZero] would (an unbound symbol remains, or [h]'s shape
/// isn't a clean ratio of polynomials) — reuses the same
/// [rationalPolynomials] reading of [h] that function does, just
/// evaluated at a point instead of solved for roots.
List<BodePoint>? computeBodePlot(
  Expr h, {
  Map<String, num> bindings = const {},
  int pointCount = 200,
}) {
  if (pointCount < 2) {
    throw ArgumentError.value(pointCount, 'pointCount', 'must be at least 2');
  }
  final rational = rationalPolynomials(h, bindings);
  if (rational == null) return null;

  final points = <BodePoint>[];
  double? previousRawPhase;
  var unwrappedPhase = 0.0;

  for (var i = 0; i < pointCount; i++) {
    final omega = math.pi * i / (pointCount - 1);
    final z = Complex(math.cos(omega), math.sin(omega));
    final response =
        _evaluateZInversePolynomial(rational.numerator, z) /
        _evaluateZInversePolynomial(rational.denominator, z);

    final rawPhase = response.phase;
    if (previousRawPhase == null) {
      unwrappedPhase = rawPhase;
    } else {
      var delta = rawPhase - previousRawPhase;
      while (delta > math.pi) {
        delta -= 2 * math.pi;
      }
      while (delta < -math.pi) {
        delta += 2 * math.pi;
      }
      unwrappedPhase += delta;
    }
    previousRawPhase = rawPhase;

    points.add(
      BodePoint(
        omega: omega,
        magnitudeDb: 20 * _log10(response.abs()),
        phaseDegrees: unwrappedPhase * 180 / math.pi,
      ),
    );
  }
  return points;
}

double _log10(double v) => math.log(v) / math.ln10;

/// Evaluates a `z^-1`-power sparse polynomial — as [rationalPolynomials]
/// produces: a `Map` from power `k` to coefficient, meaning the term
/// `coefficient * z^-k` — at a concrete complex [z].
///
/// Deliberately *not* reusing `pole_zero.dart`'s leading-coefficient-first
/// array form (the one [findPolynomialRoots] needs): that form exists to
/// clear out a common `z^-k` factor first, which matters for *finding
/// roots* (see that function's own doc comment) but not for evaluating at
/// one specific, always-nonzero point — `z = e^{j*omega}` is never `0`,
/// so `1/z^k` is always well-defined and no clearing is needed.
Complex _evaluateZInversePolynomial(Map<int, num> poly, Complex z) {
  final zInverse = Complex.one / z;
  var result = Complex.zero;
  for (final entry in poly.entries) {
    var zInversePower = Complex.one;
    for (var i = 0; i < entry.key; i++) {
      zInversePower = zInversePower * zInverse;
    }
    result = result + Complex(entry.value.toDouble()) * zInversePower;
  }
  return result;
}
