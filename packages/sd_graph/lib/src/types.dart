import 'package:meta/meta.dart';

/// A port's base scalar element type (§4). Ordered as a widening lattice —
/// see [ScalarType.canWidenTo] — from narrowest to widest.
enum ScalarType {
  bit,
  byte,
  short,
  integer,
  real,
  complex;

  /// Whether a value of `this` type may flow into a port declared `other`
  /// without an explicit conversion — i.e. `other` is `this` or wider.
  /// Narrowing (e.g. complex -> real) is never allowed implicitly (§4:
  /// "define real->complex widening rules", generalized to every pair in
  /// this lattice).
  bool canWidenTo(ScalarType other) => index <= other.index;
}

enum TypeShape { scalar, vector, matrix }

/// A port's full data type: a [scalar] element type plus its [shape]
/// (§4: "dtype (real|complex|int|short|byte|bit + vector-of + matrix)").
@immutable
class DataType {
  const DataType(this.scalar, {this.shape = TypeShape.scalar});

  final ScalarType scalar;
  final TypeShape shape;

  bool isCompatibleWith(DataType other) =>
      shape == other.shape && scalar.canWidenTo(other.scalar);

  @override
  bool operator ==(Object other) =>
      other is DataType && other.scalar == scalar && other.shape == shape;

  @override
  int get hashCode => Object.hash(scalar, shape);

  @override
  String toString() =>
      shape == TypeShape.scalar ? scalar.name : '${shape.name}<${scalar.name}>';
}

/// Fixed-point word length, `Qm.n` (§4, §5.10).
@immutable
class QFormat {
  const QFormat(this.integerBits, this.fractionBits, {this.signed = true});

  final int integerBits;
  final int fractionBits;
  final bool signed;

  int get totalBits => integerBits + fractionBits + (signed ? 1 : 0);

  @override
  bool operator ==(Object other) =>
      other is QFormat &&
      other.integerBits == integerBits &&
      other.fractionBits == fractionBits &&
      other.signed == signed;

  @override
  int get hashCode => Object.hash(integerBits, fractionBits, signed);

  @override
  String toString() => '${signed ? '' : 'U'}Q$integerBits.$fractionBits';
}

/// A sample rate as a rational multiple of an optional symbolic base rate
/// (§4: "sampleRate (rational/symbolic)") — e.g. `Fs`, `Fs/2`, `3*Fs`, or a
/// concrete numeric rate when [baseSymbol] is `null`.
@immutable
class SampleRate {
  const SampleRate({this.numerator = 1, this.denominator = 1, this.baseSymbol});

  factory SampleRate.numeric(num hz) => SampleRate(numerator: hz);

  factory SampleRate.symbol(String symbol) => SampleRate(baseSymbol: symbol);

  final num numerator;
  final num denominator;

  /// `null` means [numerator]/[denominator] is a concrete rate in Hz.
  final String? baseSymbol;

  SampleRate scaledBy(num factor) => SampleRate(
    numerator: numerator * factor,
    denominator: denominator,
    baseSymbol: baseSymbol,
  );

  SampleRate dividedBy(num factor) => SampleRate(
    numerator: numerator,
    denominator: denominator * factor,
    baseSymbol: baseSymbol,
  );

  bool isCompatibleWith(SampleRate other) =>
      baseSymbol == other.baseSymbol &&
      numerator * other.denominator == other.numerator * denominator;

  @override
  bool operator ==(Object other) =>
      other is SampleRate &&
      isCompatibleWith(other) &&
      baseSymbol == other.baseSymbol;

  @override
  int get hashCode => Object.hash(baseSymbol, numerator / denominator);

  @override
  String toString() {
    if (baseSymbol == null) return '${numerator / denominator} Hz';
    if (numerator == denominator) return baseSymbol!;
    if (denominator == 1) return '$numerator*$baseSymbol';
    return '($numerator/$denominator)*$baseSymbol';
  }
}

/// Parses a `dtype` string from `sd:ports` JSON (e.g. `"real"`,
/// `"vector-of-complex"`, `"matrix-of-int"`) into a [DataType]. Unknown
/// scalar names fall back to [ScalarType.real] rather than throwing — a
/// malformed dtype on one port shouldn't take down validation of the
/// whole graph.
DataType parseDataType(String raw) {
  final lower = raw.toLowerCase();
  TypeShape shape = TypeShape.scalar;
  var scalarPart = lower;
  if (lower.startsWith('vector-of-')) {
    shape = TypeShape.vector;
    scalarPart = lower.substring('vector-of-'.length);
  } else if (lower.startsWith('matrix-of-')) {
    shape = TypeShape.matrix;
    scalarPart = lower.substring('matrix-of-'.length);
  }
  final scalar = switch (scalarPart) {
    'bit' => ScalarType.bit,
    'byte' => ScalarType.byte,
    'short' => ScalarType.short,
    'int' || 'integer' => ScalarType.integer,
    'complex' => ScalarType.complex,
    _ => ScalarType.real,
  };
  return DataType(scalar, shape: shape);
}
