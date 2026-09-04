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
