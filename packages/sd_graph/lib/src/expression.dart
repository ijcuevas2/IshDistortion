import 'dart:math' as math;

/// A minimal symbolic-algebra expression: just enough to build and display
/// a transfer function from Mason's gain formula (§4) — constants, named
/// parameter symbols, integer powers of `z`, and sums/products/quotients
/// of those. Simplification is "good enough for readable output" (constant
/// folding, dropping `*1`/`+0`, combining like terms in a sum, folding
/// `z^a * z^b`), not a full computer-algebra normal form — correctness is
/// instead verified by [evaluate]-ing at sample points (see
/// `mason_test.dart`), which doesn't require canonical form.
sealed class Expr {
  const Expr();

  Expr operator +(Expr other) => addExpr([this, other]);
  Expr operator -(Expr other) => addExpr([this, -other]);
  Expr operator -() => mulExpr([const ConstExpr(-1), this]);
  Expr operator *(Expr other) => mulExpr([this, other]);
  Expr operator /(Expr other) => divExpr(this, other);

  /// Substitutes every [SymbolExpr] via [bindings] and every [ZPowExpr] at
  /// the given [z], then reduces to a single number. Throws [StateError]
  /// if a symbol has no binding — a missing parameter should surface
  /// loudly, not silently evaluate as zero.
  num evaluate(Map<String, num> bindings, {required num z});

  /// Builds an [Expr] from an `sd:params` value: a [num] becomes a
  /// [ConstExpr]; a numeric [String] also becomes a [ConstExpr]; anything
  /// else becomes a [SymbolExpr] named after its string form (so an
  /// unresolved gain like `"k"` shows up literally as `k` in H(z)).
  factory Expr.fromParam(Object? value) {
    if (value is num) return ConstExpr(value);
    final asString = value?.toString() ?? '1';
    final parsed = num.tryParse(asString);
    return parsed != null ? ConstExpr(parsed) : SymbolExpr(asString);
  }

  /// Renders this expression as LaTeX math-mode source — no surrounding
  /// `$...$`/`\[...\]`, so callers choose the environment (`sd_latex`'s
  /// on-screen `LatexLabel`, or a desktop `pdflatex` embed). Mirrors
  /// [toString]'s structure and precedence handling exactly, substituting
  /// proper TeX for the informal notation `toString` uses: `z^{-1}` (always
  /// braced — an un-braced `z^-1` would only superscript the `-`), `\frac`
  /// for division, and `<letter><digits>`-shaped symbol names (`b0`, `a1`,
  /// as produced by [fromParam] for an unresolved coefficient) rendered as
  /// a proper subscript (`b_{0}`) to match how every DSP text sets these.
  /// Correctness is verified the same way as [evaluate]-based tests: not
  /// by string-matching a "canonical" form, but by actually invoking
  /// `pdflatex` on the generated output (see `expression_tex_test.dart`).
  String toTex();
}

final class ConstExpr extends Expr {
  const ConstExpr(this.value);
  final num value;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) => value;

  @override
  bool operator ==(Object other) => other is ConstExpr && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => _formatNum(value);
  @override
  String toTex() => _formatNum(value);
}

final class SymbolExpr extends Expr {
  const SymbolExpr(this.name);
  final String name;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) {
    final value = bindings[name];
    if (value == null) throw StateError('No binding for symbol "$name".');
    return value;
  }

  @override
  bool operator ==(Object other) => other is SymbolExpr && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
  @override
  String toTex() => _texSymbol(name);
}

/// `z^power` — [power] is negative for a causal delay (`z^-1`), per the
/// usual DSP convention.
final class ZPowExpr extends Expr {
  const ZPowExpr(this.power);
  final int power;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) =>
      math.pow(z, power);

  @override
  bool operator ==(Object other) => other is ZPowExpr && other.power == power;
  @override
  int get hashCode => power.hashCode;
  @override
  String toString() => power == 0 ? '1' : (power == 1 ? 'z' : 'z^$power');
  @override
  String toTex() => power == 0 ? '1' : (power == 1 ? 'z' : 'z^{$power}');
}

final class AddExpr extends Expr {
  const AddExpr(this.terms);
  final List<Expr> terms;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) =>
      terms.fold<num>(0, (sum, t) => sum + t.evaluate(bindings, z: z));

  @override
  String toString() {
    final buffer = StringBuffer(terms.first.toString());
    for (final term in terms.skip(1)) {
      final (negative, text) = _asSignedTerm(term);
      buffer.write(negative ? ' - $text' : ' + $text');
    }
    return buffer.toString();
  }

  @override
  String toTex() {
    final buffer = StringBuffer(terms.first.toTex());
    for (final term in terms.skip(1)) {
      final (negative, text) = _asSignedTermTex(term);
      buffer.write(negative ? ' - $text' : ' + $text');
    }
    return buffer.toString();
  }
}

final class MulExpr extends Expr {
  const MulExpr(this.factors);
  final List<Expr> factors;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) => factors
      .fold<num>(1, (product, f) => product * f.evaluate(bindings, z: z));

  @override
  String toString() =>
      factors.map((f) => f is AddExpr ? '($f)' : '$f').join('*');

  @override
  String toTex() => factors
      .map((f) => f is AddExpr ? '(${f.toTex()})' : f.toTex())
      // Implicit multiplication, as every DSP text sets it — a thin space
      // (not a literal `*`/`\cdot`) between factors.
      .join(r'\,');
}

final class DivExpr extends Expr {
  const DivExpr(this.numerator, this.denominator);
  final Expr numerator;
  final Expr denominator;

  @override
  num evaluate(Map<String, num> bindings, {required num z}) =>
      numerator.evaluate(bindings, z: z) / denominator.evaluate(bindings, z: z);

  @override
  String toString() {
    String wrap(Expr e) => e is AddExpr ? '($e)' : '$e';
    return '${wrap(numerator)} / ${wrap(denominator)}';
  }

  @override
  String toTex() => '\\frac{${numerator.toTex()}}{${denominator.toTex()}}';
}

// --- smart constructors (simplification) ---------------------------------

Expr addExpr(List<Expr> rawTerms) {
  final flat = <Expr>[];
  void flatten(Expr e) {
    if (e is AddExpr) {
      for (final t in e.terms) {
        flatten(t);
      }
    } else {
      flat.add(e);
    }
  }

  for (final t in rawTerms) {
    flatten(t);
  }

  num constSum = 0;
  final coeffOf = <String, num>{};
  final baseOf = <String, Expr>{};
  for (final term in flat) {
    if (term is ConstExpr) {
      constSum += term.value;
      continue;
    }
    final (coeff, base) = _splitCoefficient(term);
    final key = base.toString();
    coeffOf[key] = (coeffOf[key] ?? 0) + coeff;
    baseOf[key] = base;
  }

  final result = <Expr>[if (constSum != 0) ConstExpr(constSum)];
  for (final key in coeffOf.keys) {
    final coeff = coeffOf[key]!;
    if (coeff == 0) continue;
    result.add(
      coeff == 1 ? baseOf[key]! : mulExpr([ConstExpr(coeff), baseOf[key]!]),
    );
  }
  if (result.isEmpty) return const ConstExpr(0);
  if (result.length == 1) return result.single;
  return AddExpr(List.unmodifiable(result));
}

/// Splits a term into `(numeric coefficient, remaining base expression)`,
/// e.g. `2*k*z^-1` -> `(2, k*z^-1)`, so [addExpr] can combine like terms.
(num, Expr) _splitCoefficient(Expr term) {
  if (term is MulExpr) {
    num coeff = 1;
    final rest = <Expr>[];
    for (final f in term.factors) {
      if (f is ConstExpr) {
        coeff *= f.value;
      } else {
        rest.add(f);
      }
    }
    final base = rest.isEmpty
        ? const ConstExpr(1)
        : (rest.length == 1 ? rest.single : MulExpr(List.unmodifiable(rest)));
    return (coeff, base);
  }
  return (1, term);
}

(bool, String) _asSignedTerm(Expr term) {
  final (coeff, base) = _splitCoefficient(term);
  if (coeff < 0) {
    final positive = coeff == -1 ? base : mulExpr([ConstExpr(-coeff), base]);
    return (true, positive.toString());
  }
  return (false, term.toString());
}

(bool, String) _asSignedTermTex(Expr term) {
  final (coeff, base) = _splitCoefficient(term);
  if (coeff < 0) {
    final positive = coeff == -1 ? base : mulExpr([ConstExpr(-coeff), base]);
    return (true, positive.toTex());
  }
  return (false, term.toTex());
}

/// `<letters><digits>` (e.g. `b0`, `a12`, as [Expr.fromParam] names an
/// unresolved coefficient) renders as a proper subscript (`b_{0}`); any
/// other identifier is emitted as-is but with LaTeX's special characters
/// escaped, in case a user-authored parameter name ever contains one.
final RegExp _letterDigitsSymbol = RegExp(r'^([A-Za-z]+)(\d+)$');

String _texSymbol(String name) {
  final match = _letterDigitsSymbol.firstMatch(name);
  if (match == null) return _texEscape(name);
  return '${match.group(1)}_{${match.group(2)}}';
}

String _texEscape(String s) => s
    .replaceAll(r'\', r'\textbackslash ')
    .replaceAll('_', r'\_')
    .replaceAll('&', r'\&')
    .replaceAll('%', r'\%')
    .replaceAll('#', r'\#')
    .replaceAll(r'$', r'\$');

Expr mulExpr(List<Expr> rawFactors) {
  final flat = <Expr>[];
  void flatten(Expr e) {
    if (e is MulExpr) {
      for (final f in e.factors) {
        flatten(f);
      }
    } else {
      flat.add(e);
    }
  }

  for (final f in rawFactors) {
    flatten(f);
  }

  num constProduct = 1;
  var zPower = 0;
  final others = <Expr>[];
  for (final f in flat) {
    switch (f) {
      case ConstExpr():
        constProduct *= f.value;
      case ZPowExpr():
        zPower += f.power;
      default:
        others.add(f);
    }
  }
  if (constProduct == 0) return const ConstExpr(0);

  final result = <Expr>[
    if (constProduct != 1) ConstExpr(constProduct),
    if (zPower != 0) ZPowExpr(zPower),
    ...others,
  ];
  if (result.isEmpty) return const ConstExpr(1);
  if (result.length == 1) return result.single;
  return MulExpr(List.unmodifiable(result));
}

Expr divExpr(Expr numerator, Expr denominator) {
  if (denominator is ConstExpr && denominator.value == 1) return numerator;
  if (numerator is ConstExpr && numerator.value == 0) return const ConstExpr(0);
  if (numerator is ConstExpr && denominator is ConstExpr) {
    return ConstExpr(numerator.value / denominator.value);
  }
  return DivExpr(numerator, denominator);
}

String _formatNum(num v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
