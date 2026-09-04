import 'dart:io';

import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

Future<bool> _pdflatexAvailable() async {
  try {
    final result = await Process.run('pdflatex', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('Expr.toTex (string content)', () {
    test('a constant renders as a plain number', () {
      expect(const ConstExpr(2.5).toTex(), '2.5');
      expect(const ConstExpr(3).toTex(), '3');
    });

    test('a <letter><digits> symbol renders as a proper subscript', () {
      expect(const SymbolExpr('b0').toTex(), 'b_{0}');
      expect(const SymbolExpr('a12').toTex(), 'a_{12}');
    });

    test('a plain-word symbol renders as-is', () {
      expect(const SymbolExpr('gain').toTex(), 'gain');
    });

    test('a symbol with a LaTeX-special character is escaped', () {
      expect(const SymbolExpr('50%').toTex(), r'50\%');
    });

    test('z powers are always braced (an un-braced z^-1 would mis-render)', () {
      expect(const ZPowExpr(0).toTex(), '1');
      expect(const ZPowExpr(1).toTex(), 'z');
      expect(const ZPowExpr(-1).toTex(), 'z^{-1}');
      expect(const ZPowExpr(-2).toTex(), 'z^{-2}');
      expect(const ZPowExpr(3).toTex(), 'z^{3}');
    });

    test('a sum of a constant and a negative-coefficient z-power term', () {
      final e = addExpr([
        const ConstExpr(1),
        mulExpr([const ConstExpr(-2), const ZPowExpr(-1)]),
      ]);
      expect(e.toTex(), r'1 - 2\,z^{-1}');
    });

    test('multiplication is implicit (no * or \\cdot)', () {
      // mulExpr's smart constructor canonicalizes a ZPowExpr factor before
      // any others, regardless of input order — same convention toString
      // already uses.
      final e = mulExpr([const SymbolExpr('k'), const ZPowExpr(-1)]);
      expect(e.toTex(), r'z^{-1}\,k');
    });

    test('a sum multiplied by something else is parenthesized', () {
      final sum = addExpr([const ConstExpr(1), const SymbolExpr('a1')]);
      final e = mulExpr([sum, const SymbolExpr('k')]);
      expect(e.toTex(), r'(1 + a_{1})\,k');
    });

    test('division renders as \\frac, with a symbolic denominator', () {
      final e = divExpr(
        const ConstExpr(1),
        addExpr([const ConstExpr(1), const SymbolExpr('a1')]),
      );
      expect(e.toTex(), r'\frac{1}{1 + a_{1}}');
    });
  });

  group('Expr.toTex output actually compiles', () {
    // The same biquad Direct Form II Transposed topology as
    // `mason_test.dart`'s §13 acceptance case (see that file for the
    // by-hand derivation) — reused here only to get a realistic,
    // multi-term symbolic H(z) to render, not to re-prove its numeric
    // correctness (already covered there).
    SignalGraph buildBiquad() {
      Block gainBlock(String id, num gain) => block(
        id,
        'gain',
        ports: [inPort('in1'), outPort('out1')],
        params: {'gain': gain},
      );
      Block delayBlock(String id) => block(
        id,
        'delay',
        ports: [inPort('in1'), outPort('out1')],
        directFeedthrough: false,
      );
      Block adderBlock(String id, List<String> signs) => block(
        id,
        'adder',
        ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        params: {'signs': signs},
      );
      return SignalGraph(
        blocks: {
          'src': block('src', 'source', ports: [outPort('out1')]),
          'snk': block('snk', 'sink', ports: [inPort('in1')]),
          'b0': gainBlock('b0', 1),
          'b1': gainBlock('b1', 0.6),
          'b2': gainBlock('b2', -0.2),
          'na1': gainBlock('na1', -0.7),
          'na2': gainBlock('na2', 0.15),
          'd1': delayBlock('d1'),
          'd2': delayBlock('d2'),
          'addY': adderBlock('addY', ['+', '+']),
          'addA': adderBlock('addA', ['+', '+']),
          'addB': adderBlock('addB', ['+', '-']),
          'addC': adderBlock('addC', ['+', '-']),
        },
        edges: [
          edge('e1', 'src:out1', 'b0:in1'),
          edge('e2', 'src:out1', 'b1:in1'),
          edge('e3', 'src:out1', 'b2:in1'),
          edge('e4', 'b0:out1', 'addY:in1'),
          edge('e5', 'd1:out1', 'addY:in2'),
          edge('e6', 'addY:out1', 'snk:in1'),
          edge('e7', 'addY:out1', 'na1:in1'),
          edge('e8', 'addY:out1', 'na2:in1'),
          edge('e9', 'b1:out1', 'addA:in1'),
          edge('e10', 'd2:out1', 'addA:in2'),
          edge('e11', 'addA:out1', 'addB:in1'),
          edge('e12', 'na1:out1', 'addB:in2'),
          edge('e13', 'addB:out1', 'd1:in1'),
          edge('e14', 'b2:out1', 'addC:in1'),
          edge('e15', 'na2:out1', 'addC:in2'),
          edge('e16', 'addC:out1', 'd2:in1'),
        ],
      );
    }

    Future<void> expectCompiles(String mathTex) async {
      final tex =
          '\\documentclass[preview,border=2pt]{standalone}\n'
          '\\usepackage{amsmath}\n'
          '\\begin{document}\n'
          '\$$mathTex\$\n'
          '\\end{document}\n';
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-tex-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      File('${tempDir.path}/eq.tex').writeAsStringSync(tex);
      final result = await Process.run('pdflatex', [
        '-interaction=nonstopmode',
        '-halt-on-error',
        'eq.tex',
      ], workingDirectory: tempDir.path);
      expect(
        result.exitCode,
        0,
        reason:
            'pdflatex failed on:\n$tex\n\n${result.stdout}\n${result.stderr}',
      );
      final pdf = File('${tempDir.path}/eq.pdf');
      expect(pdf.existsSync(), isTrue);
      expect(pdf.lengthSync(), greaterThan(0));
    }

    test('the biquad H(z), with numeric coefficients, compiles', () async {
      if (!await _pdflatexAvailable()) return;
      final result = computeTransferFunction(buildBiquad())!;
      await expectCompiles('H(z) = ${result.h.toTex()}');
    });

    test(
      'the biquad H(z), with unbound symbolic coefficients, compiles',
      () async {
        if (!await _pdflatexAvailable()) return;
        final graph = buildBiquad();
        final symbolic = SignalGraph(
          blocks: graph.blocks.map(
            (id, b) => MapEntry(
              id,
              b.type == 'gain' && id != 'b0'
                  ? Block(
                      id: b.id,
                      type: b.type,
                      ports: b.ports,
                      params: {'gain': id},
                    )
                  : b,
            ),
          ),
          edges: graph.edges,
        );
        final result = computeTransferFunction(symbolic)!;
        await expectCompiles('H(z) = ${result.h.toTex()}');
      },
    );
  });
}
