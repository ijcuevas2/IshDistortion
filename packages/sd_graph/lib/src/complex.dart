import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A minimal complex number — just enough arithmetic for polynomial root
/// finding (§4/§5.11: pole-zero analysis). `dart:math` has no complex type
/// of its own.
@immutable
class Complex {
  const Complex(this.re, [this.im = 0]);

  static const zero = Complex(0);
  static const one = Complex(1);

  final double re;
  final double im;

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);
  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);
  Complex operator -() => Complex(-re, -im);

  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  Complex operator /(Complex other) {
    final denom = other.re * other.re + other.im * other.im;
    return Complex(
      (re * other.re + im * other.im) / denom,
      (im * other.re - re * other.im) / denom,
    );
  }

  double abs() => math.sqrt(re * re + im * im);

  /// Whether this is within [tolerance] of being a real number (a
  /// negligible imaginary part) — DSP coefficients are always real, so a
  /// found root with `im` that's merely floating-point noise around 0
  /// should read as real.
  bool get isEffectivelyReal => im.abs() < 1e-9;

  @override
  bool operator ==(Object other) =>
      other is Complex && other.re == re && other.im == im;
  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() {
    if (im == 0) return _fmt(re);
    final sign = im < 0 ? '-' : '+';
    return '${_fmt(re)} $sign ${_fmt(im.abs())}i';
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(4);
