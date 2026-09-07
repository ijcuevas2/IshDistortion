import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

void main() {
  group('Expr.freeSymbols', () {
    test('a constant, z-power, or plain symbol has the expected base case', () {
      expect(const ConstExpr(5).freeSymbols, isEmpty);
      expect(const ZPowExpr(-1).freeSymbols, isEmpty);
      expect(const SymbolExpr('k').freeSymbols, {'k'});
    });

    test('addExpr/mulExpr union every term/factor\'s own free symbols', () {
      final sum = addExpr([
        const SymbolExpr('a'),
        mulExpr([const SymbolExpr('b'), const ZPowExpr(-1)]),
      ]);
      expect(sum.freeSymbols, {'a', 'b'});
    });

    test('divExpr unions numerator and denominator', () {
      final h = divExpr(
        const SymbolExpr('b0'),
        addExpr([
          const ConstExpr(1),
          mulExpr([const SymbolExpr('a1'), const ZPowExpr(-1)]),
        ]),
      );
      expect(h.freeSymbols, {'b0', 'a1'});
    });

    test('the same symbol appearing more than once is not duplicated', () {
      final expr = addExpr([const SymbolExpr('k'), const SymbolExpr('k')]);
      expect(expr.freeSymbols, {'k'});
    });

    test('a fully-concrete expression has no free symbols at all', () {
      final h = divExpr(
        const ConstExpr(1),
        addExpr([
          const ConstExpr(1),
          mulExpr([const ConstExpr(-0.5), const ZPowExpr(-1)]),
        ]),
      );
      expect(h.freeSymbols, isEmpty);
    });
  });
}
