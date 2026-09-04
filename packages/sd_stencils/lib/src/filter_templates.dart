import 'package:sd_document/sd_document.dart';

import 'edge_builder.dart';
import 'geometry.dart';
import 'primitives.dart';

/// One placed filter structure (§5.5): the elements to append to a
/// document, plus the single external input/output port a caller wires
/// the rest of their diagram to. Every generator here fans an external
/// input into however many internal taps it needs via a [pickoffNode]
/// (§3/§4: fan-out from one port needs no special modeling), so this is
/// always exactly one port in, one port out, however many blocks it
/// contains internally.
class FilterStructure {
  const FilterStructure({
    required this.elements,
    required this.inputBlockId,
    required this.inputPortId,
    required this.outputBlockId,
    required this.outputPortId,
  });

  final List<SdElement> elements;
  final String inputBlockId;
  final String inputPortId;
  final String outputBlockId;
  final String outputPortId;
}

const _stageDx = StencilMetrics.squareBlock * 1.6;
const _stageDy = StencilMetrics.squareBlock * 1.4;

/// §5.5: FIR, direct form — `H(z) = Σ coefficients[i] · z^-i`.
///
/// One [gain] tap per coefficient, the first reading the undelayed input
/// and each subsequent one reading one more [delay] down a tapped-delay
/// line, all summed through a chain of 2-input [adder]s (§5.2's "tapped-
/// delay-line macro" is exactly this delay chain, generated rather than a
/// standalone stencil since its length is the whole point of a parameter).
FilterStructure buildFirDirectForm({
  required String idPrefix,
  required List<num> coefficients,
  double x = 0,
  double y = 0,
}) {
  if (coefficients.isEmpty) {
    throw ArgumentError.value(
      coefficients,
      'coefficients',
      'must not be empty',
    );
  }
  final elements = <SdElement>[];
  var seq = 0;
  String nextId(String kind) => '$idPrefix-$kind${seq++}';
  void wire(String from, String fromPort, String to, String toPort) =>
      elements.add(
        buildEdge(
          id: nextId('e'),
          fromBlock: from,
          fromPort: fromPort,
          toBlock: to,
          toPort: toPort,
        ),
      );

  final tapId = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + _stageDy),
  );

  final tapOutputs = <String>[
    tapId,
  ]; // tapOutputs[i] is the source for coefficient i.
  for (var i = 1; i < coefficients.length; i++) {
    final id = nextId('d');
    elements.add(
      delay.instantiate(instanceId: id, x: x + i * _stageDx, y: y + _stageDy),
    );
    wire(tapOutputs.last, 'out1', id, 'in1');
    tapOutputs.add(id);
  }

  final gainIds = <String>[];
  for (var i = 0; i < coefficients.length; i++) {
    final id = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: id,
        x: x + i * _stageDx,
        y: y,
        params: {'gain': coefficients[i]},
        label: 'c$i',
      ),
    );
    wire(tapOutputs[i], 'out1', id, 'in1');
    gainIds.add(id);
  }

  var accId = gainIds[0];
  var accPort = 'out1';
  for (var i = 1; i < gainIds.length; i++) {
    final addId = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: addId,
        x: x + i * _stageDx,
        y: y + 2 * _stageDy,
      ),
    );
    wire(accId, accPort, addId, 'in1');
    wire(gainIds[i], 'out1', addId, 'in2');
    accId = addId;
    accPort = 'out1';
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: tapId,
    inputPortId: 'in1',
    outputBlockId: accId,
    outputPortId: accPort,
  );
}

/// §5.5: IIR, Direct Form II Transposed biquad — the exact topology
/// verified against Mason's gain formula in `sd_graph`'s test suite
/// (`mason_test.dart`'s biquad case):
/// `H(z) = (b0 + b1·z⁻¹ + b2·z⁻²) / (1 + a1·z⁻¹ + a2·z⁻²)`.
FilterStructure buildBiquadDf2t({
  required String idPrefix,
  required num b0,
  required num b1,
  required num b2,
  required num a1,
  required num a2,
  double x = 0,
  double y = 0,
}) {
  final elements = <SdElement>[];
  var seq = 0;
  String nextId(String kind) => '$idPrefix-$kind${seq++}';
  void wire(String from, String fromPort, String to, String toPort) =>
      elements.add(
        buildEdge(
          id: nextId('e'),
          fromBlock: from,
          fromPort: fromPort,
          toBlock: to,
          toPort: toPort,
        ),
      );

  SdElement gainAt(String id, num g, String label, double gx, double gy) =>
      gain.instantiate(
        instanceId: id,
        x: gx,
        y: gy,
        params: {'gain': g},
        label: label,
      );

  final tapId = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + _stageDy),
  );

  final gB0 = nextId('g');
  elements.add(gainAt(gB0, b0, 'b0', x + _stageDx, y));
  final gB1 = nextId('g');
  elements.add(gainAt(gB1, b1, 'b1', x + _stageDx, y + _stageDy));
  final gB2 = nextId('g');
  elements.add(gainAt(gB2, b2, 'b2', x + _stageDx, y + 2 * _stageDy));
  final gA1 = nextId('g');
  elements.add(gainAt(gA1, a1, 'a1', x + 4 * _stageDx, y + _stageDy));
  final gA2 = nextId('g');
  elements.add(gainAt(gA2, a2, 'a2', x + 4 * _stageDx, y + 2 * _stageDy));

  final d1 = nextId('d');
  elements.add(
    delay.instantiate(instanceId: d1, x: x + 3 * _stageDx, y: y + _stageDy),
  );
  final d2 = nextId('d');
  elements.add(
    delay.instantiate(instanceId: d2, x: x + 3 * _stageDx, y: y + 2 * _stageDy),
  );

  final addY = nextId('add');
  elements.add(
    adder.instantiate(instanceId: addY, x: x + 2 * _stageDx, y: y, label: 'y'),
  );
  final addA = nextId('add');
  elements.add(
    adder.instantiate(instanceId: addA, x: x + 2 * _stageDx, y: y + _stageDy),
  );
  final addB = nextId('add');
  elements.add(
    adder.instantiate(
      instanceId: addB,
      x: x + 3 * _stageDx,
      y: y,
      params: {
        'signs': ['+', '-'],
      },
    ),
  );
  final addC = nextId('add');
  elements.add(
    adder.instantiate(
      instanceId: addC,
      x: x + 2 * _stageDx,
      y: y + 2 * _stageDy,
      params: {
        'signs': ['+', '-'],
      },
    ),
  );

  wire(tapId, 'out1', gB0, 'in1');
  wire(tapId, 'out1', gB1, 'in1');
  wire(tapId, 'out1', gB2, 'in1');
  wire(gB0, 'out1', addY, 'in1');
  wire(d1, 'out1', addY, 'in2');
  wire(gB1, 'out1', addA, 'in1');
  wire(d2, 'out1', addA, 'in2');
  wire(addA, 'out1', addB, 'in1');
  wire(gA1, 'out1', addB, 'in2');
  wire(addB, 'out1', d1, 'in1');
  wire(gB2, 'out1', addC, 'in1');
  wire(gA2, 'out1', addC, 'in2');
  wire(addC, 'out1', d2, 'in1');
  wire(addY, 'out1', gA1, 'in1');
  wire(addY, 'out1', gA2, 'in1');

  return FilterStructure(
    elements: elements,
    inputBlockId: tapId,
    inputPortId: 'in1',
    outputBlockId: addY,
    outputPortId: 'out1',
  );
}

/// One second-order section's coefficients, for [buildBiquadCascade].
typedef Sos = ({num b0, num b1, num b2, num a1, num a2});

/// §5.5: cascade of biquads (SOS form) — chains [buildBiquadDf2t] stages
/// output-to-input, so the overall `H(z)` is the product of each stage's.
FilterStructure buildBiquadCascade({
  required String idPrefix,
  required List<Sos> sections,
  double x = 0,
  double y = 0,
}) {
  if (sections.isEmpty) {
    throw ArgumentError.value(sections, 'sections', 'must not be empty');
  }
  final elements = <SdElement>[];
  const stageWidth = _stageDx * 6;
  FilterStructure? previous;
  late final String firstInputBlock;
  late final String firstInputPort;

  for (var i = 0; i < sections.length; i++) {
    final s = sections[i];
    final stage = buildBiquadDf2t(
      idPrefix: '$idPrefix-s$i',
      b0: s.b0,
      b1: s.b1,
      b2: s.b2,
      a1: s.a1,
      a2: s.a2,
      x: x + i * stageWidth,
      y: y,
    );
    elements.addAll(stage.elements);
    if (previous == null) {
      firstInputBlock = stage.inputBlockId;
      firstInputPort = stage.inputPortId;
    } else {
      elements.add(
        buildEdge(
          id: '$idPrefix-ce$i',
          fromBlock: previous.outputBlockId,
          fromPort: previous.outputPortId,
          toBlock: stage.inputBlockId,
          toPort: stage.inputPortId,
        ),
      );
    }
    previous = stage;
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: firstInputBlock,
    inputPortId: firstInputPort,
    outputBlockId: previous!.outputBlockId,
    outputPortId: previous.outputPortId,
  );
}
