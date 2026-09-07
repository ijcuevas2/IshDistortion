import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_latex/sd_latex.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LatexLabel', () {
    testWidgets('valid TeX renders via Math, not the raw-source fallback', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const LatexLabel(r'\frac{1}{2}')));
      expect(find.byType(Math), findsOneWidget);
      expect(find.text(r'\frac{1}{2}'), findsNothing);
    });

    testWidgets('unsupported/invalid TeX falls back to its own raw source', (
      tester,
    ) async {
      // flutter_math_fork is a KaTeX subset (§11): an unrecognized/invalid
      // command is a parse error, not silently dropped — the label must
      // still show *something* meaningful (the source itself) rather than
      // a bare error icon or a blank space.
      await tester.pumpWidget(_wrap(const LatexLabel(r'\notarealcommand{x}')));
      expect(find.text(r'\notarealcommand{x}'), findsOneWidget);
    });

    testWidgets('exposes the raw source as a semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const LatexLabel(r'a^2 + b^2')));
      expect(find.bySemanticsLabel('a^2 + b^2'), findsOneWidget);
      handle.dispose();
    });
  });
}
