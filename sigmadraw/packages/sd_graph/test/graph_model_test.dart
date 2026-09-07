import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

void main() {
  group('ScalarType.canWidenTo', () {
    test('a type can always widen to itself', () {
      for (final t in ScalarType.values) {
        expect(t.canWidenTo(t), isTrue);
      }
    });

    test('real widens to complex but not the reverse', () {
      expect(ScalarType.real.canWidenTo(ScalarType.complex), isTrue);
      expect(ScalarType.complex.canWidenTo(ScalarType.real), isFalse);
    });

    test('bit is the narrowest type', () {
      for (final t in ScalarType.values) {
        expect(ScalarType.bit.canWidenTo(t), isTrue);
      }
    });
  });

  group('parseDataType', () {
    test('parses scalar, vector-of, and matrix-of forms', () {
      expect(parseDataType('real'), const DataType(ScalarType.real));
      expect(
        parseDataType('vector-of-complex'),
        const DataType(ScalarType.complex, shape: TypeShape.vector),
      );
      expect(
        parseDataType('matrix-of-int'),
        const DataType(ScalarType.integer, shape: TypeShape.matrix),
      );
    });

    test('an unknown scalar name falls back to real rather than throwing', () {
      expect(() => parseDataType('nonsense'), returnsNormally);
      expect(parseDataType('nonsense').scalar, ScalarType.real);
    });
  });

  group('SampleRate', () {
    test('Fs and (2/2)*Fs are compatible', () {
      final a = SampleRate.symbol('Fs');
      const b = SampleRate(numerator: 2, denominator: 2, baseSymbol: 'Fs');
      expect(a.isCompatibleWith(b), isTrue);
    });

    test('different symbols are never compatible even at the same ratio', () {
      expect(
        SampleRate.symbol('Fs').isCompatibleWith(SampleRate.symbol('Fc')),
        isFalse,
      );
    });

    test('scaledBy/dividedBy compose correctly', () {
      final rate = SampleRate.symbol('Fs').scaledBy(2).dividedBy(4);
      expect(
        rate.isCompatibleWith(
          const SampleRate(numerator: 1, denominator: 2, baseSymbol: 'Fs'),
        ),
        isTrue,
      );
    });
  });

  group('SignalGraph.fromDocument', () {
    SdElement block(
      String type,
      String id, {
      List<Map<String, Object?>> ports = const [],
    }) => SdElement(const SdQName('g'))
      ..blockType = type
      ..blockId = id
      ..blockPorts = ports;

    test('extracts blocks with their ports, params, and directFeedthrough', () {
      final doc = createBlankSdDocument();
      doc.root.appendChild(
        block(
          'gain',
          'g1',
          ports: [
            {'id': 'in1', 'dir': 'in', 'dtype': 'real'},
            {'id': 'out1', 'dir': 'out', 'dtype': 'real'},
          ],
        )..blockParams = {'gain': 2.0},
      );
      doc.root.appendChild(
        block('delay', 'd1')..blockDirectFeedthrough = false,
      );

      final graph = SignalGraph.fromDocument(doc);
      expect(graph.blocks.keys, containsAll(['g1', 'd1']));
      expect(graph.block('g1')!.params['gain'], 2.0);
      expect(graph.block('g1')!.ports, hasLength(2));
      expect(graph.block('g1')!.directFeedthrough, isTrue);
      expect(graph.block('d1')!.directFeedthrough, isFalse);
    });

    test('extracts edges from sd:edge/from/to attributes', () {
      final doc = createBlankSdDocument();
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'a:out1'
          ..edgeTo = 'b:in1'
          ..edgeRoute = 'orthogonal',
      );

      final graph = SignalGraph.fromDocument(doc);
      expect(graph.edges, hasLength(1));
      final edge = graph.edges.single;
      expect(edge.fromBlockId, 'a');
      expect(edge.fromPortId, 'out1');
      expect(edge.toBlockId, 'b');
      expect(edge.toPortId, 'in1');
      expect(edge.route, 'orthogonal');
    });

    test('a real document built from sd_stencils primitives round-trips into a graph', () {
      // Kept dependency-free of sd_stencils (a sibling package) by
      // building the block manually in the same shape `instantiate()`
      // produces — the true cross-package pipeline is exercised in
      // sd_ui's/the app's own tests, which already depend on both.
      final doc = createBlankSdDocument();
      doc.root.appendChild(
        block(
          'source',
          'src',
          ports: [
            {'id': 'out1', 'dir': 'out', 'dtype': 'real'},
          ],
        ),
      );
      final graph = SignalGraph.fromDocument(doc);
      expect(graph.block('src')!.outputPorts.map((p) => p.id), ['out1']);
      expect(graph.block('src')!.inputPorts, isEmpty);
    });
  });
}
