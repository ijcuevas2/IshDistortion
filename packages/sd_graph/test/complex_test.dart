import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

void main() {
  group('Complex', () {
    test('addition and subtraction', () {
      expect(const Complex(1, 2) + const Complex(3, 4), const Complex(4, 6));
      expect(const Complex(3, 4) - const Complex(1, 2), const Complex(2, 2));
    });

    test('negation', () {
      expect(-const Complex(1, -2), const Complex(-1, 2));
    });

    test('multiplication: (2+3i)(4-5i) = 23+2i', () {
      // (2*4 - 3*-5) + (2*-5 + 3*4)i = (8+15) + (-10+12)i = 23 + 2i
      expect(const Complex(2, 3) * const Complex(4, -5), const Complex(23, 2));
    });

    test('i * i = -1', () {
      const i = Complex(0, 1);
      expect(i * i, const Complex(-1, 0));
    });

    test('division: (4+2i)/(1+1i) = 3-1i', () {
      final result = const Complex(4, 2) / const Complex(1, 1);
      expect(result.re, closeTo(3, 1e-9));
      expect(result.im, closeTo(-1, 1e-9));
    });

    test('abs of 3+4i is 5', () {
      expect(const Complex(3, 4).abs(), closeTo(5, 1e-9));
    });

    test('isEffectivelyReal is true for a negligible imaginary part', () {
      expect(const Complex(5, 0).isEffectivelyReal, isTrue);
      expect(const Complex(5, 1e-12).isEffectivelyReal, isTrue);
      expect(const Complex(5, 0.01).isEffectivelyReal, isFalse);
    });

    test('equality and hashCode are structural', () {
      expect(const Complex(1, 2), const Complex(1, 2));
      expect(const Complex(1, 2).hashCode, const Complex(1, 2).hashCode);
      expect(const Complex(1, 2), isNot(const Complex(1, 3)));
    });
  });
}
