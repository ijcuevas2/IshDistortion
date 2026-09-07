import 'package:sd_graph/sd_graph.dart';

const _real = DataType(ScalarType.real);

Port inPort(String id, {DataType dataType = _real, int vlen = 1}) => Port(
  id: id,
  direction: PortDirection.input,
  dataType: dataType,
  vlen: vlen,
);

Port outPort(String id, {DataType dataType = _real, int vlen = 1}) => Port(
  id: id,
  direction: PortDirection.output,
  dataType: dataType,
  vlen: vlen,
);

Block block(
  String id,
  String type, {
  List<Port> ports = const [],
  Map<String, Object?> params = const {},
  bool directFeedthrough = true,
}) => Block(
  id: id,
  type: type,
  ports: ports,
  params: params,
  directFeedthrough: directFeedthrough,
);

Edge edge(String id, String from, String to) {
  final fromParts = from.split(':');
  final toParts = to.split(':');
  return Edge(
    id: id,
    fromBlockId: fromParts[0],
    fromPortId: fromParts[1],
    toBlockId: toParts[0],
    toPortId: toParts[1],
  );
}

/// A biquad Direct Form II Transposed, wired exactly as a real diagram
/// would be (the same topology as `mason_test.dart`'s §13 acceptance
/// case — see that file for the by-hand derivation of `H(z)` itself),
/// parameterized so callers can choose coefficients with hand-derivable
/// results for whatever they're testing — e.g. `pole_zero_test.dart`
/// picks a denominator/numerator with clean quadratic-formula roots,
/// `frequency_response_test.dart` picks values simple to evaluate by
/// hand directly at DC/Nyquist.
///
/// One caveat worth knowing before picking coefficients: a zero
/// *coefficient* still leaves that term's `z`-power present in the
/// polynomial, but Mason's own gain multiplication collapses a forward
/// path's gain of exactly `0` (e.g. `b2 = 0`) to a bare `ConstExpr(0)`
/// with no trace of its `z^-2` factor at all — genuinely dropping the
/// numerator to degree 1, not degree 2 with a zero leading coefficient.
/// `b1 = 0` doesn't have this problem, since `b2`'s own (nonzero) term
/// still anchors the numerator at degree 2 either way.
SignalGraph buildBiquadGraph({
  required num b0,
  required num b1,
  required num b2,
  required num a1,
  required num a2,
}) {
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
      'b0': gainBlock('b0', b0),
      'b1': gainBlock('b1', b1),
      'b2': gainBlock('b2', b2),
      'na1': gainBlock('na1', a1),
      'na2': gainBlock('na2', a2),
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
