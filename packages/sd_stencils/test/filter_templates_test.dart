import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:test/test.dart';

/// Wraps a [FilterStructure] with an explicit source+sink so
/// `computeTransferFunction` has unambiguous endpoints, and returns the
/// resulting document.
SdDocument _wrapWithSourceSink(FilterStructure structure) {
  final doc = createBlankSdDocument();
  doc.root.appendChild(source.instantiate(instanceId: 'src'));
  doc.root.appendChild(sink.instantiate(instanceId: 'snk'));
  for (final element in structure.elements) {
    doc.root.appendChild(element);
  }
  doc.root.appendChild(
    buildEdge(
      id: 'wire-in',
      fromBlock: 'src',
      fromPort: 'out1',
      toBlock: structure.inputBlockId,
      toPort: structure.inputPortId,
    ),
  );
  doc.root.appendChild(
    buildEdge(
      id: 'wire-out',
      fromBlock: structure.outputBlockId,
      fromPort: structure.outputPortId,
      toBlock: 'snk',
      toPort: 'in1',
    ),
  );
  return doc;
}

void main() {
  group('buildFirDirectForm', () {
    test('produces a graph with no algebraic loop (FIR is inherently feedback-free)', () {
      final structure = buildFirDirectForm(
        idPrefix: 'fir',
        coefficients: [1, 0.5, -0.25, 0.1],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('H(z) is exactly the weighted sum of z^-i, for coefficient counts 1 through 5', () {
      for (final coefficients in [
        [3.0],
        [1.0, 0.5],
        [1.0, 0.5, -0.25],
        [0.2, 0.4, 0.4, 0.2],
        [1.0, -2.0, 3.0, -2.0, 1.0],
      ]) {
        final structure = buildFirDirectForm(
          idPrefix: 'fir',
          coefficients: coefficients,
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        num expected(num z) {
          var sum = 0.0;
          for (var i = 0; i < coefficients.length; i++) {
            sum += coefficients[i] * _powInv(z, i);
          }
          return sum;
        }

        for (final z in [2.0, 5.0, -3.0, 0.5]) {
          expect(
            result.h.evaluate({}, z: z),
            closeTo(expected(z), 1e-9),
            reason: 'coefficients=$coefficients z=$z',
          );
        }
      }
    });
  });

  group('buildFirTransposedDirectForm', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildFirTransposedDirectForm(
        idPrefix: 'firt',
        coefficients: [1, 0.5, -0.25, 0.1],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('H(z) is exactly the weighted sum of z^-i, for coefficient counts 1 through 5', () {
      for (final coefficients in [
        [3.0],
        [1.0, 0.5],
        [1.0, 0.5, -0.25],
        [0.2, 0.4, 0.4, 0.2],
        [1.0, -2.0, 3.0, -2.0, 1.0],
      ]) {
        final structure = buildFirTransposedDirectForm(
          idPrefix: 'firt',
          coefficients: coefficients,
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        num expected(num z) {
          var sum = 0.0;
          for (var i = 0; i < coefficients.length; i++) {
            sum += coefficients[i] * _powInv(z, i);
          }
          return sum;
        }

        for (final z in [2.0, 5.0, -3.0, 0.5]) {
          expect(
            result.h.evaluate({}, z: z),
            closeTo(expected(z), 1e-9),
            reason: 'coefficients=$coefficients z=$z',
          );
        }
      }
    });

    test('matches buildFirDirectForm exactly, for the same coefficients '
        '(same H(z), different topology)', () {
      const coefficients = [0.3, -0.6, 0.9, 0.1];
      final transposed = buildFirTransposedDirectForm(
        idPrefix: 'a',
        coefficients: coefficients,
      );
      final direct = buildFirDirectForm(
        idPrefix: 'b',
        coefficients: coefficients,
      );
      final transposedResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(transposed)),
      )!;
      final directResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(direct)),
      )!;

      for (final z in [2.0, -1.5, 4.0]) {
        expect(
          transposedResult.h.evaluate({}, z: z),
          closeTo(directResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test('rejects an empty coefficient list', () {
      expect(
        () => buildFirTransposedDirectForm(idPrefix: 'x', coefficients: []),
        throwsArgumentError,
      );
    });
  });

  group('buildFirLattice', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildFirLattice(
        idPrefix: 'lat',
        reflectionCoefficients: [0.5, -0.3, 0.2],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('a single stage realizes H(z) = 1 + k1*z^-1', () {
      const k1 = 0.4;
      final structure = buildFirLattice(
        idPrefix: 'lat',
        reflectionCoefficients: [k1],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final expected = 1 + k1 * _powInv(z, 1);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('two stages realize H(z) = 1 + k1*(1+k2)*z^-1 + k2*z^-2 '
        '(the textbook direct-form-equivalent of a 2nd-order lattice)', () {
      const k1 = 0.4, k2 = -0.25;
      final structure = buildFirLattice(
        idPrefix: 'lat',
        reflectionCoefficients: [k1, k2],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final zInv = _powInv(z, 1);
        final expected = 1 + k1 * (1 + k2) * zInv + k2 * zInv * zInv;
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test(
      'three stages match the hand-derived cubic direct-form equivalent',
      () {
        const k1 = 0.4, k2 = -0.25, k3 = 0.1;
        final structure = buildFirLattice(
          idPrefix: 'lat',
          reflectionCoefficients: [k1, k2, k3],
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        // Derived independently (via the z-domain recursion a_m = a_{m-1} +
        // k_m*z^-1*b_{m-1}, b_m = k_m*a_{m-1} + z^-1*b_{m-1}, a_0=b_0=1),
        // not by re-running the generator's own stage-by-stage code.
        const c0 = 1.0;
        const c1 = k1 * (1 + k2) + k2 * k3;
        const c2 = k2 + k1 * k3 * (1 + k2);
        const c3 = k3;

        for (final z in [2.0, 5.0, -3.0, 0.5]) {
          final zInv = _powInv(z, 1);
          final expected =
              c0 + c1 * zInv + c2 * zInv * zInv + c3 * zInv * zInv * zInv;
          expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
        }
      },
    );

    test('rejects an empty reflection-coefficient list', () {
      expect(
        () => buildFirLattice(idPrefix: 'x', reflectionCoefficients: []),
        throwsArgumentError,
      );
    });
  });

  group('buildAllPoleLattice', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildAllPoleLattice(
        idPrefix: 'apl',
        reflectionCoefficients: [0.5, -0.3, 0.2],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('a single stage realizes H(z) = 1 / (1 + k1*z^-1) — the '
        'feedback dual of buildFirLattice\'s own single-stage case', () {
      const k1 = 0.4;
      final structure = buildAllPoleLattice(
        idPrefix: 'apl',
        reflectionCoefficients: [k1],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final expected = 1 / (1 + k1 * _powInv(z, 1));
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('two stages realize H(z) = 1 / (1 + k1*(1+k2)*z^-1 + k2*z^-2) — '
        'the reciprocal of buildFirLattice\'s own two-stage H(z)', () {
      const k1 = 0.4, k2 = -0.25;
      final structure = buildAllPoleLattice(
        idPrefix: 'apl',
        reflectionCoefficients: [k1, k2],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final zInv = _powInv(z, 1);
        final expected = 1 / (1 + k1 * (1 + k2) * zInv + k2 * zInv * zInv);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('three stages match the reciprocal of the hand-derived cubic '
        'denominator', () {
      const k1 = 0.4, k2 = -0.25, k3 = 0.1;
      final structure = buildAllPoleLattice(
        idPrefix: 'apl',
        reflectionCoefficients: [k1, k2, k3],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      // Same closed form buildFirLattice's own test independently
      // derives (a_m = a_{m-1} + k_m*z^-1*b_{m-1}, b_m = k_m*a_{m-1} +
      // z^-1*b_{m-1}, a_0=b_0=1) — the all-pole lattice's H(z) is that
      // polynomial's reciprocal, not a second derivation.
      const c0 = 1.0;
      const c1 = k1 * (1 + k2) + k2 * k3;
      const c2 = k2 + k1 * k3 * (1 + k2);
      const c3 = k3;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final zInv = _powInv(z, 1);
        final denominator =
            c0 + c1 * zInv + c2 * zInv * zInv + c3 * zInv * zInv * zInv;
        expect(result.h.evaluate({}, z: z), closeTo(1 / denominator, 1e-9));
      }
    });

    test('rejects an empty reflection-coefficient list', () {
      expect(
        () => buildAllPoleLattice(idPrefix: 'x', reflectionCoefficients: []),
        throwsArgumentError,
      );
    });
  });

  group('buildLatticeLadderFilter', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildLatticeLadderFilter(
        idPrefix: 'll',
        reflectionCoefficients: [0.5, -0.3],
        ladderCoefficients: [0.2, 0.4, -0.1],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('with only c0 nonzero, reduces to exactly buildAllPoleLattice '
        "(y[n] = 1*f_0[n] + 0*(everything else) = f_0[n])", () {
      const k = [0.4, -0.25];
      final ladder = buildLatticeLadderFilter(
        idPrefix: 'll',
        reflectionCoefficients: k,
        ladderCoefficients: [1, 0, 0],
      );
      final allPole = buildAllPoleLattice(
        idPrefix: 'ap',
        reflectionCoefficients: k,
      );
      final ladderResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(ladder)),
      )!;
      final allPoleResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(allPole)),
      )!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        expect(
          ladderResult.h.evaluate({}, z: z),
          closeTo(allPoleResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test('p=1 matches H(z) = ((c0+c1) + c1*k1*z^-1) / (1+k1*z^-1) — '
        'derived fresh via z-domain substitution using '
        "buildAllPoleLattice's own already-verified F0/F1 relationship "
        '(F1=X, F0=X/(1+k1*z^-1)), not a textbook formula taken on '
        'faith', () {
      const k1 = 0.4;
      const c0 = 0.6, c1 = -0.3;
      final structure = buildLatticeLadderFilter(
        idPrefix: 'll',
        reflectionCoefficients: [k1],
        ladderCoefficients: [c0, c1],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, -2.0]) {
        final zInv = _powInv(z, 1);
        final expected = ((c0 + c1) + c1 * k1 * zInv) / (1 + k1 * zInv);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('p=2 matches the fresh z-domain derivation using '
        "buildAllPoleLattice's own already-verified F0/F1/F2 "
        'relationships', () {
      const k1 = 0.4, k2 = -0.25;
      const c0 = 0.6, c1 = -0.3, c2 = 0.2;
      final structure = buildLatticeLadderFilter(
        idPrefix: 'll',
        reflectionCoefficients: [k1, k2],
        ladderCoefficients: [c0, c1, c2],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, 0.5]) {
        final zInv = _powInv(z, 1);
        // F2/X=1, F1/X=(1+k1*z^-1)/a2(z), F0/X=1/a2(z); Y = c0*F0 +
        // c1*F1 + c2*F2 = X*[c0 + c1*(1+k1*z^-1) + c2*a2(z)] / a2(z).
        final a2 = 1 + k1 * (1 + k2) * zInv + k2 * zInv * zInv;
        final numerator = c0 + c1 * (1 + k1 * zInv) + c2 * a2;
        final expected = numerator / a2;
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('rejects a ladderCoefficients length mismatch', () {
      expect(
        () => buildLatticeLadderFilter(
          idPrefix: 'x',
          reflectionCoefficients: [0.5, -0.3],
          ladderCoefficients: [0.2, 0.4],
        ),
        throwsArgumentError,
      );
    });
  });

  group('buildIirDirectFormI', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildIirDirectFormI(
        idPrefix: 'df1',
        b: [1.0, 0.5, 0.2],
        a: [-0.6, 0.1],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('matches the textbook H(z) for a simple 1st-order case', () {
      const b0 = 1.0, b1 = 0.4, a1 = -0.5;
      final structure = buildIirDirectFormI(
        idPrefix: 'df1',
        b: [b0, b1],
        a: [a1],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      // Not 0.5: with a1=-0.5, that's exactly this H(z)'s pole
      // (1 + a1*z^-1 = 0 at z = -a1 = 0.5) — both sides would evaluate
      // to (the same, but closeTo-incomparable) infinity there.
      for (final z in [2.0, 5.0, -3.0, -2.0]) {
        final zInv = _powInv(z, 1);
        final expected = (b0 + b1 * zInv) / (1 + a1 * zInv);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('matches buildBiquadDf2t exactly for the same coefficients '
        '(same H(z), non-minimal-delay topology)', () {
      const b0 = 1.0, b1 = 0.6, b2 = -0.2, a1 = -0.7, a2 = 0.15;
      final df1 = buildIirDirectFormI(
        idPrefix: 'df1',
        b: [b0, b1, b2],
        a: [a1, a2],
      );
      final df2t = buildBiquadDf2t(
        idPrefix: 'df2t',
        b0: b0,
        b1: b1,
        b2: b2,
        a1: a1,
        a2: a2,
      );
      final df1Result = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(df1)),
      )!;
      final df2tResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(df2t)),
      )!;

      for (final z in [2.0, 0.5, 10.0, -4.0]) {
        expect(
          df1Result.h.evaluate({}, z: z),
          closeTo(df2tResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test('rejects an empty b list', () {
      expect(
        () => buildIirDirectFormI(idPrefix: 'x', b: [], a: [0.5]),
        throwsArgumentError,
      );
    });

    test('rejects an empty a list', () {
      expect(
        () => buildIirDirectFormI(idPrefix: 'x', b: [1.0], a: []),
        throwsArgumentError,
      );
    });
  });

  group('buildIirDirectFormII', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildIirDirectFormII(
        idPrefix: 'df2',
        b: [1.0, 0.5, 0.2],
        a: [-0.6, 0.1],
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('matches the textbook H(z) for a simple 1st-order case', () {
      const b0 = 1.0, b1 = 0.4, a1 = -0.5;
      final structure = buildIirDirectFormII(
        idPrefix: 'df2',
        b: [b0, b1],
        a: [a1],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      // Not 0.5: with a1=-0.5, that's exactly this H(z)'s pole
      // (1 + a1*z^-1 = 0 at z = -a1 = 0.5) — both sides would evaluate
      // to (the same, but closeTo-incomparable) infinity there.
      for (final z in [2.0, 5.0, -3.0, -2.0]) {
        final zInv = _powInv(z, 1);
        final expected = (b0 + b1 * zInv) / (1 + a1 * zInv);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('matches buildBiquadDf2t exactly for the same coefficients '
        '(same H(z), minimal-delay topology)', () {
      const b0 = 1.0, b1 = 0.6, b2 = -0.2, a1 = -0.7, a2 = 0.15;
      final df2 = buildIirDirectFormII(
        idPrefix: 'df2',
        b: [b0, b1, b2],
        a: [a1, a2],
      );
      final df2t = buildBiquadDf2t(
        idPrefix: 'df2t',
        b0: b0,
        b1: b1,
        b2: b2,
        a1: a1,
        a2: a2,
      );
      final df2Result = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(df2)),
      )!;
      final df2tResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(df2t)),
      )!;

      for (final z in [2.0, 0.5, 10.0, -4.0]) {
        expect(
          df2Result.h.evaluate({}, z: z),
          closeTo(df2tResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test('rejects an empty a list', () {
      expect(
        () => buildIirDirectFormII(idPrefix: 'x', b: [1.0], a: []),
        throwsArgumentError,
      );
    });

    test('rejects a b/a length mismatch', () {
      expect(
        () => buildIirDirectFormII(idPrefix: 'x', b: [1.0, 0.5], a: [0.1, 0.2]),
        throwsArgumentError,
      );
    });
  });

  group('buildBiquadDf2t', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildBiquadDf2t(
        idPrefix: 'bq',
        b0: 1,
        b1: 0.5,
        b2: 0.2,
        a1: -0.6,
        a2: 0.1,
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('Mason yields the textbook H(z), matching the hand-verified topology in sd_graph', () {
      const b0 = 1.0, b1 = 0.6, b2 = -0.2, a1 = -0.7, a2 = 0.15;
      final structure = buildBiquadDf2t(
        idPrefix: 'bq',
        b0: b0,
        b1: b1,
        b2: b2,
        a1: a1,
        a2: a2,
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      num expected(num z) {
        final zInv = _powInv(z, 1);
        return (b0 + b1 * zInv + b2 * zInv * zInv) /
            (1 + a1 * zInv + a2 * zInv * zInv);
      }

      for (final z in [2.0, 0.5, 10.0, -4.0]) {
        expect(result.h.evaluate({}, z: z), closeTo(expected(z), 1e-9));
      }
    });
  });

  group('buildBiquadCascade', () {
    test('a single-section cascade matches a lone biquad exactly', () {
      const section = (b0: 1.0, b1: 0.3, b2: -0.1, a1: -0.5, a2: 0.2);
      final cascade = buildBiquadCascade(idPrefix: 'casc', sections: [section]);
      final lone = buildBiquadDf2t(
        idPrefix: 'lone',
        b0: section.b0,
        b1: section.b1,
        b2: section.b2,
        a1: section.a1,
        a2: section.a2,
      );

      final cascadeResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(cascade)),
      )!;
      final loneResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(lone)),
      )!;

      for (final z in [2.0, 3.3]) {
        expect(
          cascadeResult.h.evaluate({}, z: z),
          closeTo(loneResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test('a two-section cascade multiplies each section\'s H(z)', () {
      const s1 = (b0: 1.0, b1: 0.2, b2: 0.0, a1: -0.4, a2: 0.0);
      const s2 = (b0: 1.0, b1: -0.3, b2: 0.05, a1: 0.2, a2: -0.1);
      final structure = buildBiquadCascade(
        idPrefix: 'casc',
        sections: [s1, s2],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      num sectionH(Sos s, num z) {
        final zInv = _powInv(z, 1);
        return (s.b0 + s.b1 * zInv + s.b2 * zInv * zInv) /
            (1 + s.a1 * zInv + s.a2 * zInv * zInv);
      }

      for (final z in [2.0, 5.0, -1.5]) {
        final expected = sectionH(s1, z) * sectionH(s2, z);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('rejects an empty section list', () {
      expect(
        () => buildBiquadCascade(idPrefix: 'x', sections: []),
        throwsArgumentError,
      );
    });
  });

  group('buildBiquadParallel', () {
    test('a single-section parallel matches a lone biquad exactly', () {
      const section = (b0: 1.0, b1: 0.3, b2: -0.1, a1: -0.5, a2: 0.2);
      final parallel = buildBiquadParallel(
        idPrefix: 'par',
        sections: [section],
      );
      final lone = buildBiquadDf2t(
        idPrefix: 'lone',
        b0: section.b0,
        b1: section.b1,
        b2: section.b2,
        a1: section.a1,
        a2: section.a2,
      );

      final parallelResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(parallel)),
      )!;
      final loneResult = computeTransferFunction(
        SignalGraph.fromDocument(_wrapWithSourceSink(lone)),
      )!;

      for (final z in [2.0, 3.3]) {
        expect(
          parallelResult.h.evaluate({}, z: z),
          closeTo(loneResult.h.evaluate({}, z: z), 1e-9),
        );
      }
    });

    test("a two-section parallel sums each section's H(z)", () {
      const s1 = (b0: 1.0, b1: 0.2, b2: 0.0, a1: -0.4, a2: 0.0);
      const s2 = (b0: 1.0, b1: -0.3, b2: 0.05, a1: 0.2, a2: -0.1);
      final structure = buildBiquadParallel(
        idPrefix: 'par',
        sections: [s1, s2],
      );
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      num sectionH(Sos s, num z) {
        final zInv = _powInv(z, 1);
        return (s.b0 + s.b1 * zInv + s.b2 * zInv * zInv) /
            (1 + s.a1 * zInv + s.a2 * zInv * zInv);
      }

      for (final z in [2.0, 5.0, -1.5]) {
        final expected = sectionH(s1, z) + sectionH(s2, z);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('rejects an empty section list', () {
      expect(
        () => buildBiquadParallel(idPrefix: 'x', sections: []),
        throwsArgumentError,
      );
    });
  });

  group('buildCombFilter', () {
    test(
      'produces a graph with no algebraic loop, feedforward or feedback',
      () {
        for (final feedback in [false, true]) {
          final structure = buildCombFilter(
            idPrefix: 'comb',
            delaySamples: 4,
            gainCoefficient: 0.5,
            feedback: feedback,
          );
          final doc = _wrapWithSourceSink(structure);
          expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
        }
      },
    );

    test('feedforward form matches H(z) = 1 + gain*z^-delaySamples', () {
      for (final (delaySamples, gain) in [(1, 0.5), (4, -0.3), (8, 1.0)]) {
        final structure = buildCombFilter(
          idPrefix: 'comb',
          delaySamples: delaySamples,
          gainCoefficient: gain,
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        for (final z in [2.0, 5.0, -3.0]) {
          final expected = 1 + gain * _powInv(z, delaySamples);
          expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
        }
      }
    });

    test('feedback form matches H(z) = 1 / (1 - gain*z^-delaySamples)', () {
      for (final (delaySamples, gain) in [(1, 0.5), (4, -0.3), (8, 0.2)]) {
        final structure = buildCombFilter(
          idPrefix: 'comb',
          delaySamples: delaySamples,
          gainCoefficient: gain,
          feedback: true,
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        for (final z in [2.0, 5.0, -3.0]) {
          final expected = 1 / (1 - gain * _powInv(z, delaySamples));
          expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
        }
      }
    });

    test('rejects a delaySamples less than 1', () {
      expect(
        () =>
            buildCombFilter(idPrefix: 'x', delaySamples: 0, gainCoefficient: 1),
        throwsArgumentError,
      );
    });
  });

  group('buildAllpassFilter', () {
    test('produces a graph with no algebraic loop', () {
      final structure = buildAllpassFilter(idPrefix: 'ap', coefficient: 0.4);
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('H(z) matches the textbook (coefficient + z^-1) / '
        '(1 + coefficient*z^-1) formula', () {
      const c = 0.4;
      final structure = buildAllpassFilter(idPrefix: 'ap', coefficient: c);
      final doc = _wrapWithSourceSink(structure);
      final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

      for (final z in [2.0, 5.0, -3.0, -2.0]) {
        final zInv = _powInv(z, 1);
        final expected = (c + zInv) / (1 + c * zInv);
        expect(result.h.evaluate({}, z: z), closeTo(expected, 1e-9));
      }
    });

    test('the magnitude response is exactly 0dB (|H|=1) at every '
        'frequency, for any real coefficient — the defining allpass '
        'property', () {
      for (final c in [0.3, -0.5, 0.9, -0.1]) {
        final structure = buildAllpassFilter(idPrefix: 'ap', coefficient: c);
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;
        final points = computeBodePlot(result.h, pointCount: 50)!;

        for (final p in points) {
          expect(
            p.magnitudeDb,
            closeTo(0, 1e-6),
            reason: 'coefficient=$c omega=${p.omega}',
          );
        }
      }
    });
  });

  group('buildCicFilter', () {
    test('decimation:1 (no downsampler at all) gives the full, meaningful '
        'combined H(z) = ((1-z^-differentialDelay)/(1-z^-1))^stages', () {
      for (final (stages, differentialDelay) in [
        (1, 1),
        (2, 1),
        (1, 2),
        (3, 2),
      ]) {
        final structure = buildCicFilter(
          idPrefix: 'cic',
          stages: stages,
          decimation: 1,
          differentialDelay: differentialDelay,
        );
        final doc = _wrapWithSourceSink(structure);
        final result = computeTransferFunction(SignalGraph.fromDocument(doc))!;

        // Not z=1: that's the integrator's own pole (1-z^-1=0 there).
        for (final z in [2.0, 5.0, -3.0]) {
          final zInv = _powInv(z, 1);
          final combH = 1 - _powInv(z, differentialDelay);
          final integratorH = 1 - zInv;
          num expected = 1;
          for (var s = 0; s < stages; s++) {
            expected *= combH / integratorH;
          }
          expect(
            result.h.evaluate({}, z: z),
            closeTo(expected, 1e-9),
            reason: 'stages=$stages differentialDelay=$differentialDelay z=$z',
          );
        }
      }
    });

    test('a genuinely decimating structure (decimation>1) still validates '
        'as a real, correctly-wired, no-algebraic-loop diagram', () {
      final structure = buildCicFilter(
        idPrefix: 'cic',
        stages: 2,
        decimation: 4,
        differentialDelay: 2,
      );
      final doc = _wrapWithSourceSink(structure);
      expect(detectAlgebraicLoops(SignalGraph.fromDocument(doc)), isEmpty);
    });

    test('rejects invalid stages/decimation/differentialDelay', () {
      expect(
        () => buildCicFilter(idPrefix: 'x', stages: 0, decimation: 1),
        throwsArgumentError,
      );
      expect(
        () => buildCicFilter(idPrefix: 'x', stages: 1, decimation: 0),
        throwsArgumentError,
      );
      expect(
        () => buildCicFilter(
          idPrefix: 'x',
          stages: 1,
          decimation: 1,
          differentialDelay: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  test('buildFirDirectForm rejects an empty coefficient list', () {
    expect(
      () => buildFirDirectForm(idPrefix: 'x', coefficients: []),
      throwsArgumentError,
    );
  });
}

num _powInv(num z, int i) {
  num result = 1;
  for (var k = 0; k < i; k++) {
    result /= z;
  }
  return result;
}
