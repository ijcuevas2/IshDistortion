import 'dart:math' as math;

import 'complex.dart';
import 'expression.dart';

/// The poles and zeros of a transfer function (§5.11's "Analysis Plot —
/// pole-zero"). A causal, stable IIR filter has every pole strictly
/// *inside* the unit circle — [poles] is what a pole-zero plot draws
/// relative to that circle to make stability visually obvious.
class PoleZeroResult {
  const PoleZeroResult({required this.poles, required this.zeros});

  final List<Complex> poles;
  final List<Complex> zeros;
}

/// Computes the poles and zeros of [h] (a transfer function from
/// `computeTransferFunction`, or any [Expr]) by reading it as a ratio of
/// polynomials in `z` and finding each polynomial's roots. [bindings]
/// resolves any unbound coefficient symbols (e.g. an unresolved gain) —
/// pole/zero *locations* need concrete numbers, unlike Mason's formula
/// itself, which stays meaningful fully symbolic.
///
/// Returns `null` if [h]'s shape doesn't reduce to a clean rational
/// polynomial once [bindings] is substituted (an unbound symbol remains,
/// or the expression has some other non-polynomial structure) — this can
/// happen for a graph Mason's formula still handles fine (an unresolved
/// parameter is normal there), so this is a real "can't do this
/// specific analysis on this specific H(z)" outcome, not a bug.
PoleZeroResult? computePoleZero(
  Expr h, {
  Map<String, num> bindings = const {},
}) {
  final rational = rationalPolynomials(h, bindings);
  if (rational == null) return null;

  final (numeratorCoeffs, numeratorZOrigin) = _clearedZPolynomial(
    rational.numerator,
  );
  final (denominatorCoeffs, denominatorZOrigin) = _clearedZPolynomial(
    rational.denominator,
  );
  // A numerator/denominator with no z^-0 (constant) term at all — every
  // path from source to sink passes through at least one delay, e.g. a
  // bare `H(z) = z^-1` (source -> delay -> sink: found by exactly this
  // case throwing before this existed) — has an implicit common factor
  // of z^-k that [_clearedZPolynomial] strips out rather than leaving as
  // spurious zero *leading* coefficients (which would both make
  // findPolynomialRoots reject the array outright, and, even padded
  // around, overstate the polynomial's true degree, so wrongly claim
  // extra roots that don't exist "at infinity"). That stripped factor is
  // `k` extra roots at the origin — for a numerator, `1/z^k` is `k`
  // extra *poles* at 0; for a denominator, symmetrically, `k` extra
  // *zeros* at 0.
  return PoleZeroResult(
    poles: [
      ...findPolynomialRoots(denominatorCoeffs),
      for (var i = 0; i < numeratorZOrigin; i++) Complex.zero,
    ],
    zeros: [
      ...findPolynomialRoots(numeratorCoeffs),
      for (var i = 0; i < denominatorZOrigin; i++) Complex.zero,
    ],
  );
}

/// Splits [expr] into numerator/denominator polynomials in `z^-1` (a
/// sparse power->coefficient map each) — a bare, non-[DivExpr] is treated
/// as numerator over an implicit denominator of `1` (exactly the shape
/// [divExpr]'s own smart constructor collapses a `.../1` transfer
/// function to). `null` if either half doesn't reduce to a clean
/// polynomial — see [computePoleZero]'s doc comment.
({Map<int, num> numerator, Map<int, num> denominator})? rationalPolynomials(
  Expr expr,
  Map<String, num> bindings,
) {
  if (expr is DivExpr) {
    final numerator = _asPolynomial(expr.numerator, bindings);
    final denominator = _asPolynomial(expr.denominator, bindings);
    if (numerator == null || denominator == null) return null;
    return (numerator: numerator, denominator: denominator);
  }
  final numerator = _asPolynomial(expr, bindings);
  if (numerator == null) return null;
  return (numerator: numerator, denominator: {0: 1});
}

/// Reads [expr] as a polynomial in `z^-1` — a sparse map from power `k`
/// (i.e. the term `z^-k`) to its coefficient, substituting [bindings] for
/// every symbol. `null` if [expr] contains an unbound symbol or a nested
/// [DivExpr] (a ratio of polynomials isn't itself one).
///
/// An exhaustive `switch` over the sealed [Expr] hierarchy rather than a
/// method on each subtype: unlike [Expr.evaluate]/[Expr.toTex], which
/// every variant answers the same way, [DivExpr] has no sensible answer
/// here at all (see [rationalPolynomials], the actual num/den entry
/// point) — the exhaustiveness check still guarantees this gets revisited
/// if a new [Expr] variant is ever added.
Map<int, num>? _asPolynomial(Expr expr, Map<String, num> bindings) {
  switch (expr) {
    case ConstExpr(value: final v):
      return {0: v};
    case SymbolExpr(name: final name):
      final bound = bindings[name];
      return bound == null ? null : {0: bound};
    case ZPowExpr(power: final power):
      // power is negative for z^-1 (a delay) — see ZPowExpr's own doc
      // comment — so the z^-1-power this term contributes is -power.
      return {-power: 1};
    case AddExpr(terms: final terms):
      final result = <int, num>{};
      for (final term in terms) {
        final poly = _asPolynomial(term, bindings);
        if (poly == null) return null;
        for (final entry in poly.entries) {
          result[entry.key] = (result[entry.key] ?? 0) + entry.value;
        }
      }
      return result;
    case MulExpr(factors: final factors):
      var result = <int, num>{0: 1};
      for (final factor in factors) {
        final poly = _asPolynomial(factor, bindings);
        if (poly == null) return null;
        result = _polyMul(result, poly);
      }
      return result;
    case DivExpr():
      return null;
  }
}

Map<int, num> _polyMul(Map<int, num> a, Map<int, num> b) {
  final result = <int, num>{};
  for (final ea in a.entries) {
    for (final eb in b.entries) {
      final power = ea.key + eb.key;
      result[power] = (result[power] ?? 0) + ea.value * eb.value;
    }
  }
  return result;
}

/// Converts a `z^-1`-power map (as [_asPolynomial] produces; every key is
/// `>= 0` since every stencil only ever contributes non-positive powers
/// of `z`) into the *smallest* equivalent plain, leading-coefficient-first
/// polynomial *in* `z` (`coeffs[0]` is the leading coefficient, `coeffs[
/// last]` the constant term) — what [findPolynomialRoots] expects — along
/// with how many powers of `z^-1` were factored out to get there (see
/// [computePoleZero]'s doc comment for what the caller does with that
/// count).
///
/// "Smallest equivalent" matters, not just "*a* polynomial that matches
/// after scaling by `z^maxPower`": if [zInversePoly]'s smallest key is
/// `> 0` (no constant/`z^-0` term at all — e.g. a bare `z^-1`, which has
/// *only* a `k=1` entry), naively sizing the array to `maxPower+1` and
/// copying `coeffs[k] = zInversePoly[k]` leaves the leading slots at
/// their default zero — which [findPolynomialRoots] rejects outright
/// (correctly: a claimed-degree-`n` polynomial whose degree-`n`
/// coefficient is 0 isn't actually degree `n`), and even a root finder
/// that tolerated it would report a spurious extra root that doesn't
/// exist. Instead, this shifts every key down by the *smallest* key
/// present, so the returned polynomial's own leading coefficient is
/// always genuinely nonzero (found via the bare-`z^-1` case throwing
/// before this shift existed).
///
/// The shift itself is a direct index-for-power copy once re-based,
/// `coeffs[k - minPower] = zInversePoly[k]` — which looks surprising at
/// first (multiplying through by `z^(maxPower-minPower)` turns the
/// `z^-k` term into `z^(maxPower-k)`, so it's tempting to write
/// `coeffs[maxPower - k]` instead — an earlier version of this function
/// did exactly that, sized to `maxPower` with no shift at all, and a
/// hand-derived pole-location test caught it producing the reversed
/// polynomial). The two reversals cancel: turning power `-k` into power
/// `maxPower-k` is one reversal, and the leading-first array *storing*
/// power `p` at index `(maxPower-minPower)-(p-minPower)` is a second
/// one; composing them simplifies straight back to "index = k -
/// minPower".
(List<num>, int) _clearedZPolynomial(Map<int, num> zInversePoly) {
  if (zInversePoly.isEmpty) return (const [1], 0); // the constant "1".
  final minPower = zInversePoly.keys.reduce(math.min);
  final maxPower = zInversePoly.keys.reduce(math.max);
  final coeffs = List<num>.filled(maxPower - minPower + 1, 0);
  for (final entry in zInversePoly.entries) {
    coeffs[entry.key - minPower] = entry.value;
  }
  return (coeffs, minPower);
}

/// Finds every root of the polynomial `coefficients[0]*z^n + ... +
/// coefficients[n]` (leading coefficient first, matching [_clearedZPolynomial]'s
/// convention) via the Durand-Kerner (Weierstrass) method: simultaneous
/// fixed-point iteration on every root at once, starting from points
/// spread around a circle guaranteed to enclose them all (Cauchy's
/// bound). Converges reliably for the modest-degree, well-conditioned
/// polynomials a DSP transfer function's numerator/denominator actually
/// produces — this is not a general-purpose, numerical-analysis-grade
/// root finder (no special handling for very high degree, repeated
/// roots, or ill-conditioned coefficients).
///
/// Returns an empty list for a degree-0 (constant) polynomial — "no
/// roots" is the correct answer there, not an error. Throws
/// [ArgumentError] if [coefficients] is empty or its leading coefficient
/// is exactly zero (so it isn't actually degree `coefficients.length - 1`
/// as claimed).
List<Complex> findPolynomialRoots(
  List<num> coefficients, {
  int maxIterations = 200,
  double tolerance = 1e-10,
}) {
  if (coefficients.isEmpty) {
    throw ArgumentError.value(
      coefficients,
      'coefficients',
      'must not be empty',
    );
  }
  if (coefficients.first == 0) {
    throw ArgumentError.value(
      coefficients,
      'coefficients',
      'leading coefficient must not be zero',
    );
  }
  final degree = coefficients.length - 1;
  if (degree == 0) return const [];

  // Normalize to monic (leading coefficient 1) — doesn't change the
  // roots, and keeps the iteration numerically well-scaled.
  final leading = coefficients.first.toDouble();
  final c = [for (final v in coefficients) v.toDouble() / leading];

  Complex evaluate(Complex z) {
    var result = Complex(c[0]);
    for (var i = 1; i < c.length; i++) {
      result = result * z + Complex(c[i]);
    }
    return result;
  }

  // Cauchy's bound: every root's magnitude is < 1 + max(|c_1|..|c_n|)
  // for a monic polynomial. Each initial guess is nudged off the real
  // axis (the `+ 0.5` radian offset) so a real-coefficient polynomial's
  // conjugate-symmetric roots don't start from coincident guesses.
  final bound = 1 + c.skip(1).map((v) => v.abs()).fold(0.0, math.max);
  var roots = [
    for (var k = 0; k < degree; k++)
      Complex(
        bound * math.cos(2 * math.pi * k / degree + 0.5),
        bound * math.sin(2 * math.pi * k / degree + 0.5),
      ),
  ];

  for (var iter = 0; iter < maxIterations; iter++) {
    var maxDelta = 0.0;
    final next = <Complex>[];
    for (var i = 0; i < degree; i++) {
      var denom = Complex.one;
      for (var j = 0; j < degree; j++) {
        if (j != i) denom = denom * (roots[i] - roots[j]);
      }
      final delta = evaluate(roots[i]) / denom;
      next.add(roots[i] - delta);
      maxDelta = math.max(maxDelta, delta.abs());
    }
    roots = next;
    if (maxDelta < tolerance) break;
  }
  return roots;
}
