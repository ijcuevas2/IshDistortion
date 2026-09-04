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

/// §5.5: FIR, transposed direct form — the same `H(z)` as
/// [buildFirDirectForm] (`H(z) = Σ coefficients[i] · z^-i`), realized
/// with the network-transposition theorem's dual topology instead: the
/// direct form's input-side tapped-delay-line + pickoff becomes a
/// single pickoff (no delay chain on the input at all — every gain
/// reads the *undelayed* input directly) feeding an accumulation chain
/// built from the *last* coefficient down to the first, with a delay
/// on each running-sum edge instead of on the input:
/// `w[p-1] = c[p-1]·x[n]`; `w[i] = c[i]·x[n] + z^-1{w[i+1]}` for
/// `i = p-2 .. 0`; `y[n] = w[0]`. Transposing a direct-form network
/// swaps the roles of its pickoffs and summing junctions and reverses
/// its signal flow — see this function's own test for the by-hand
/// derivation confirming this produces the identical `H(z)`.
FilterStructure buildFirTransposedDirectForm({
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

  final n = coefficients.length;
  final tapId = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + _stageDy),
  );

  final gainIds = <String>[];
  for (var i = 0; i < n; i++) {
    final id = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: id,
        x: x + _stageDx,
        y: y + i * _stageDy,
        params: {'gain': coefficients[i]},
        label: 'c$i',
      ),
    );
    wire(tapId, 'out1', id, 'in1');
    gainIds.add(id);
  }

  var accId = gainIds[n - 1];
  var accPort = 'out1';
  for (var i = n - 2; i >= 0; i--) {
    final delayId = nextId('d');
    elements.add(
      delay.instantiate(
        instanceId: delayId,
        x: x + (n - i) * _stageDx,
        y: y + (n - 1) * _stageDy,
      ),
    );
    wire(accId, accPort, delayId, 'in1');

    final addId = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: addId,
        x: x + (n - i + 1) * _stageDx,
        y: y + i * _stageDy,
      ),
    );
    wire(gainIds[i], 'out1', addId, 'in1');
    wire(delayId, 'out1', addId, 'in2');

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

/// §5.5: FIR, (two-multiplier) lattice — parameterized by
/// [reflectionCoefficients] (`k_1..k_p`), the lattice structure's own
/// native parameters, unlike [buildFirDirectForm]/
/// [buildFirTransposedDirectForm]'s direct `b_i` coefficients (though a
/// order-`p` lattice still realizes a degree-`p` FIR `H(z)` — see this
/// function's own test for the closed-form relationship for small `p`).
///
/// Each stage `m` (`1..p`) carries a forward signal `f` and backward
/// signal `g`, with `f_0[n] = g_0[n] = x[n]`:
/// `f_m[n] = f_{m-1}[n] + k_m·g_{m-1}[n-1]`
/// `g_m[n] = k_m·f_{m-1}[n] + g_{m-1}[n-1]`
/// `y[n] = f_p[n]` — the final stage's own `g_p[n]` output is left
/// unwired: a real lattice's "backward" output, just one this project's
/// H(z)-only analysis has no use for (an unwired output port is not a
/// validation error, only a Problems-panel-level warning, and doesn't
/// affect Mason's gain formula since it isn't part of any source-to-
/// sink path).
FilterStructure buildFirLattice({
  required String idPrefix,
  required List<num> reflectionCoefficients,
  double x = 0,
  double y = 0,
}) {
  if (reflectionCoefficients.isEmpty) {
    throw ArgumentError.value(
      reflectionCoefficients,
      'reflectionCoefficients',
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
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + 1.5 * _stageDy),
  );

  var fBlock = tapId, fPort = 'out1';
  var gBlock = tapId, gPort = 'out1';

  for (var m = 0; m < reflectionCoefficients.length; m++) {
    final k = reflectionCoefficients[m];
    final label = 'k${m + 1}';
    final stageX = x + (m + 1) * _stageDx;

    final dg = nextId('d');
    elements.add(
      delay.instantiate(instanceId: dg, x: stageX, y: y + 3 * _stageDy),
    );
    wire(gBlock, gPort, dg, 'in1');

    // k_m applied to the delayed backward signal, feeding f_m.
    final kf = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: kf,
        x: stageX,
        y: y,
        params: {'gain': k},
        label: label,
      ),
    );
    wire(dg, 'out1', kf, 'in1');

    // k_m applied to the (undelayed) forward signal, feeding g_m.
    final kg = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: kg,
        x: stageX,
        y: y + 4 * _stageDy,
        params: {'gain': k},
        label: label,
      ),
    );
    wire(fBlock, fPort, kg, 'in1');

    final addF = nextId('add');
    elements.add(
      adder.instantiate(instanceId: addF, x: stageX + _stageDx, y: y),
    );
    wire(fBlock, fPort, addF, 'in1');
    wire(kf, 'out1', addF, 'in2');

    final addG = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: addG,
        x: stageX + _stageDx,
        y: y + 4 * _stageDy,
      ),
    );
    wire(kg, 'out1', addG, 'in1');
    wire(dg, 'out1', addG, 'in2');

    fBlock = addF;
    fPort = 'out1';
    gBlock = addG;
    gPort = 'out1';
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: tapId,
    inputPortId: 'in1',
    outputBlockId: fBlock,
    outputPortId: fPort,
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

/// §5.5: IIR, Direct Form I, generalized to arbitrary order —
/// `H(z) = (b[0] + b[1]·z⁻¹ + ... + b[M]·z⁻ᴹ) / (1 + a[0]·z⁻¹ + ... +
/// a[N-1]·z⁻ᴺ)` ([a] holds `a_1..a_N`; the implicit `a_0 = 1` is never
/// stored, the same convention [buildBiquadDf2t]'s `a1`/`a2` already
/// use). Unlike the canonical/minimal [buildIirDirectFormII] (which
/// shares one `max(M,N)`-long delay line between the numerator and
/// denominator taps), Direct Form I is the textbook *non-minimal*
/// realization: a separate `M`-long delay line for [b]'s taps on `x`
/// and a separate `N`-long delay line for [a]'s taps on the final,
/// already-computed `y` fed back — `M+N` delays total, not `max(M,N)`.
/// That non-minimality is the whole pedagogical point of drawing DF-I
/// as its own structure rather than only ever using DF-II.
FilterStructure buildIirDirectFormI({
  required String idPrefix,
  required List<num> b,
  required List<num> a,
  double x = 0,
  double y = 0,
}) {
  if (b.isEmpty) {
    throw ArgumentError.value(b, 'b', 'must not be empty');
  }
  if (a.isEmpty) {
    throw ArgumentError.value(
      a,
      'a',
      'must not be empty (feedback coefficients a_1..a_N; a purely '
          'feedforward filter has its own dedicated generators — '
          'buildFirDirectForm et al.)',
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

  final tapX = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapX, x: x, y: y + _stageDy),
  );

  // Feedforward: b[0]*x[n] + b[1]*x[n-1] + ... + b[M]*x[n-M].
  final xTaps = <String>[tapX];
  for (var i = 1; i < b.length; i++) {
    final d = nextId('d');
    elements.add(
      delay.instantiate(instanceId: d, x: x + i * _stageDx, y: y + _stageDy),
    );
    wire(xTaps.last, 'out1', d, 'in1');
    xTaps.add(d);
  }
  final bGains = <String>[];
  for (var i = 0; i < b.length; i++) {
    final g = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: g,
        x: x + i * _stageDx,
        y: y,
        params: {'gain': b[i]},
        label: 'b$i',
      ),
    );
    wire(xTaps[i], 'out1', g, 'in1');
    bGains.add(g);
  }
  var acc = bGains[0];
  var accPort = 'out1';
  for (var i = 1; i < bGains.length; i++) {
    final add = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: add,
        x: x + i * _stageDx,
        y: y + 2 * _stageDy,
      ),
    );
    wire(acc, accPort, add, 'in1');
    wire(bGains[i], 'out1', add, 'in2');
    acc = add;
    accPort = 'out1';
  }

  // Feedback: subtract a[0]*y[n-1] + ... + a[N-1]*y[n-N]. The delay
  // chain's own input (dys[0].in1) is wired only at the very end, once
  // `acc` names the final, fully-combined y[n] node — the real signal
  // graph has no cycle problem here (the delay breaks it), only the
  // *construction order* would, since dys[0]'s source doesn't exist
  // yet when the chain itself is built.
  final stageX = x + b.length * _stageDx;
  final dys = <String>[];
  for (var i = 0; i < a.length; i++) {
    final d = nextId('d');
    elements.add(
      delay.instantiate(
        instanceId: d,
        x: stageX + i * _stageDx,
        y: y + 3 * _stageDy,
      ),
    );
    dys.add(d);
  }
  for (var i = 1; i < dys.length; i++) {
    wire(dys[i - 1], 'out1', dys[i], 'in1');
  }
  final aGains = <String>[];
  for (var i = 0; i < a.length; i++) {
    final g = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: g,
        x: stageX + i * _stageDx,
        y: y,
        params: {'gain': a[i]},
        label: 'a${i + 1}',
      ),
    );
    wire(dys[i], 'out1', g, 'in1');
    aGains.add(g);
  }
  for (var i = 0; i < aGains.length; i++) {
    final add = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: add,
        x: stageX + (i + 1) * _stageDx,
        y: y + 2 * _stageDy,
        params: {
          'signs': ['+', '-'],
        },
      ),
    );
    wire(acc, accPort, add, 'in1');
    wire(aGains[i], 'out1', add, 'in2');
    acc = add;
    accPort = 'out1';
  }
  wire(acc, accPort, dys[0], 'in1');

  return FilterStructure(
    elements: elements,
    inputBlockId: tapX,
    inputPortId: 'in1',
    outputBlockId: acc,
    outputPortId: accPort,
  );
}

/// §5.5: IIR, Direct Form II (canonical, non-transposed), generalized to
/// arbitrary matched order `N` — `H(z) = (b[0] + b[1]·z⁻¹ + ... +
/// b[N]·z⁻ᴺ) / (1 + a[0]·z⁻¹ + ... + a[N-1]·z⁻ᴺ)` ([b] one longer than
/// [a], the same matched-order shape [buildBiquadDf2t] fixes at `N=2`).
/// Uses exactly `N` delays (not [buildIirDirectFormI]'s `M+N`) by
/// sharing ONE delay line, computing the intermediate `w[n] = x[n] -
/// a[0]·w[n-1] - ... - a[N-1]·w[n-N]` first and reading both the
/// feedback *and* the feedforward taps off that same line — the
/// "canonical"/minimal-delay realization Direct Form II is named for.
/// (This is the *non*-transposed form; [buildBiquadDf2t] already covers
/// the transposed one, whose own delays sit between partial sums
/// instead of holding `w` directly.)
FilterStructure buildIirDirectFormII({
  required String idPrefix,
  required List<num> b,
  required List<num> a,
  double x = 0,
  double y = 0,
}) {
  if (a.isEmpty) {
    throw ArgumentError.value(a, 'a', 'must not be empty');
  }
  if (b.length != a.length + 1) {
    throw ArgumentError(
      'b must have exactly one more coefficient than a for a matched-'
      'order system (b: b[0]..b[N], a: a[1]..a[N]) — got b.length='
      '${b.length}, a.length=${a.length}',
    );
  }
  final n = a.length;
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

  final tapX = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapX, x: x, y: y + 2 * _stageDy),
  );

  // w[n]'s own shared delay line (fed back from `w` itself, wired last).
  final dws = <String>[];
  for (var i = 0; i < n; i++) {
    final d = nextId('d');
    elements.add(
      delay.instantiate(
        instanceId: d,
        x: x + (i + 2) * _stageDx,
        y: y + 2 * _stageDy,
      ),
    );
    dws.add(d);
  }
  for (var i = 1; i < dws.length; i++) {
    wire(dws[i - 1], 'out1', dws[i], 'in1');
  }

  final aGains = <String>[];
  for (var i = 0; i < n; i++) {
    final g = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: g,
        x: x + (i + 2) * _stageDx,
        y: y + 4 * _stageDy,
        params: {'gain': a[i]},
        label: 'a${i + 1}',
      ),
    );
    wire(dws[i], 'out1', g, 'in1');
    aGains.add(g);
  }

  var wAcc = tapX;
  var wAccPort = 'out1';
  for (var i = 0; i < n; i++) {
    final add = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: add,
        x: x + (i + 1) * _stageDx,
        y: y + 3 * _stageDy,
        params: {
          'signs': ['+', '-'],
        },
      ),
    );
    wire(wAcc, wAccPort, add, 'in1');
    wire(aGains[i], 'out1', add, 'in2');
    wAcc = add;
    wAccPort = 'out1';
  }
  wire(wAcc, wAccPort, dws[0], 'in1');

  // Feedforward: b[0]*w[n] + b[1]*w[n-1] + ... + b[N]*w[n-N] — reads
  // straight off the same delay line just built, no second delay chain.
  final bGains = <String>[];
  final firstBGain = nextId('g');
  elements.add(
    gain.instantiate(
      instanceId: firstBGain,
      x: x + (n + 2) * _stageDx,
      y: y,
      params: {'gain': b[0]},
      label: 'b0',
    ),
  );
  wire(wAcc, wAccPort, firstBGain, 'in1');
  bGains.add(firstBGain);
  for (var i = 0; i < n; i++) {
    final g = nextId('g');
    elements.add(
      gain.instantiate(
        instanceId: g,
        x: x + (i + 2) * _stageDx,
        y: y,
        params: {'gain': b[i + 1]},
        label: 'b${i + 1}',
      ),
    );
    wire(dws[i], 'out1', g, 'in1');
    bGains.add(g);
  }

  var outAcc = bGains[0];
  var outAccPort = 'out1';
  for (var i = 1; i < bGains.length; i++) {
    final add = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: add,
        x: x + (n + 2 + i) * _stageDx,
        y: y + _stageDy,
      ),
    );
    wire(outAcc, outAccPort, add, 'in1');
    wire(bGains[i], 'out1', add, 'in2');
    outAcc = add;
    outAccPort = 'out1';
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: tapX,
    inputPortId: 'in1',
    outputBlockId: outAcc,
    outputPortId: outAccPort,
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

/// §5.5: parallel form (SOS) — feeds every [buildBiquadDf2t] stage the
/// *same* input (fanned out from one pickoff, unlike
/// [buildBiquadCascade]'s output-to-input chaining) and sums their
/// outputs, so the overall `H(z)` is the *sum* of each stage's rather
/// than the cascade's product.
FilterStructure buildBiquadParallel({
  required String idPrefix,
  required List<Sos> sections,
  double x = 0,
  double y = 0,
}) {
  if (sections.isEmpty) {
    throw ArgumentError.value(sections, 'sections', 'must not be empty');
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
  const stageWidth = _stageDx * 6;

  final tapId = nextId('tap');
  elements.add(
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + 3 * _stageDy),
  );

  final stageOutputs = <(String, String)>[];
  for (var i = 0; i < sections.length; i++) {
    final s = sections[i];
    final stage = buildBiquadDf2t(
      idPrefix: '$idPrefix-s$i',
      b0: s.b0,
      b1: s.b1,
      b2: s.b2,
      a1: s.a1,
      a2: s.a2,
      x: x + stageWidth,
      y: y + i * 6 * _stageDy,
    );
    elements.addAll(stage.elements);
    wire(tapId, 'out1', stage.inputBlockId, stage.inputPortId);
    stageOutputs.add((stage.outputBlockId, stage.outputPortId));
  }

  var (accId, accPort) = stageOutputs[0];
  for (var i = 1; i < stageOutputs.length; i++) {
    final (outId, outPort) = stageOutputs[i];
    final addId = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: addId,
        x: x + stageWidth * 2,
        y: y + i * 6 * _stageDy,
      ),
    );
    wire(accId, accPort, addId, 'in1');
    wire(outId, outPort, addId, 'in2');
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

/// §5.5: comb filter — feedforward/FIR (`feedback: false`, the
/// default): `y[n] = x[n] + gainCoefficient·x[n-delaySamples]`, i.e.
/// `H(z) = 1 + gainCoefficient·z⁻ᴹ`. Feedback/recursive/IIR
/// (`feedback: true`): `y[n] = x[n] + gainCoefficient·y[n-delaySamples]`,
/// i.e. `H(z) = 1 / (1 - gainCoefficient·z⁻ᴹ)` (the sign flip between
/// the two forms' `H(z)` is just how that algebra falls out of "plain
/// addition" in both recursions, not an inconsistency).
///
/// Uses a single [delay] block with its own `k` param set directly to
/// [delaySamples] — Mason already reads a delay's `k` as `z^-k` (see
/// `mason.dart`), so this needs no `delaySamples`-long chain of unit
/// delays the way e.g. [buildFirDirectForm] deliberately builds one,
/// tap by tap, for a different reason entirely (exposing every
/// intermediate tap for its own per-coefficient gain). A comb only
/// ever needs the one, fully-delayed tap.
FilterStructure buildCombFilter({
  required String idPrefix,
  required int delaySamples,
  required num gainCoefficient,
  bool feedback = false,
  double x = 0,
  double y = 0,
}) {
  if (delaySamples < 1) {
    throw ArgumentError.value(
      delaySamples,
      'delaySamples',
      'must be at least 1',
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

  final delayId = nextId('d');
  elements.add(
    delay.instantiate(
      instanceId: delayId,
      x: x + _stageDx,
      y: y + 2 * _stageDy,
      params: {'k': delaySamples},
    ),
  );

  final gainId = nextId('g');
  elements.add(
    gain.instantiate(
      instanceId: gainId,
      x: x + 2 * _stageDx,
      y: y + 2 * _stageDy,
      params: {'gain': gainCoefficient},
      label: 'g',
    ),
  );
  wire(delayId, 'out1', gainId, 'in1');

  final addId = nextId('add');
  elements.add(adder.instantiate(instanceId: addId, x: x + 2 * _stageDx, y: y));
  wire(tapId, 'out1', addId, 'in1');
  wire(gainId, 'out1', addId, 'in2');

  if (feedback) {
    // y[n] = x[n] + gain*y[n-M]: the delay reads the FINAL output, not
    // the raw input — wired last, since `addId` (the final node) isn't
    // created until just above. The real signal graph has no cycle
    // problem (the delay breaks it), only construction order would.
    wire(addId, 'out1', delayId, 'in1');
  } else {
    // y[n] = x[n] + gain*x[n-M]: the delay reads the raw input directly.
    wire(tapId, 'out1', delayId, 'in1');
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: tapId,
    inputPortId: 'in1',
    outputBlockId: addId,
    outputPortId: 'out1',
  );
}

/// §5.5: allpass filter (1st order) — `H(z) = (coefficient + z⁻¹) / (1
/// + coefficient·z⁻¹)`, real-coefficient allpass's defining property
/// (`|H(e^{jω})| = 1` for every `ω`, for ANY real `coefficient` — only
/// phase varies with frequency) confirmed algebraically in this
/// function's own test by expanding `|numerator|²` and
/// `|denominator|²` and finding them identical. Implemented as a thin,
/// honest wrapper over [buildIirDirectFormII] (`b: [coefficient, 1]`,
/// `a: [coefficient]`) rather than a second hand-wired topology for
/// what is, structurally, just a specific order-1 case of it. A
/// higher-order allpass can be built by cascading multiple calls (wire
/// one's output to the next's input, the same way [buildBiquadCascade]
/// chains stages) — not built as its own generator here since the spec
/// gives this stencil family no more elaboration than "allpass" itself.
FilterStructure buildAllpassFilter({
  required String idPrefix,
  required num coefficient,
  double x = 0,
  double y = 0,
}) => buildIirDirectFormII(
  idPrefix: idPrefix,
  b: [coefficient, 1],
  a: [coefficient],
  x: x,
  y: y,
);

/// §5.5: CIC (cascaded-integrator-comb / Hogenauer) filter — [stages]
/// (`N`) cascaded integrator sections (`y[n] = x[n] + y[n-1]`, i.e.
/// `H(z) = 1/(1-z⁻¹)` each) at the input rate, then — if [decimation]
/// (`R`) is greater than 1 — a real [downsampler] block by that
/// factor, then [stages] cascaded comb sections (`y[n] = x[n] -
/// x[n-differentialDelay]`, i.e. `H(z) = 1-z⁻ᴰ` each, `differentialDelay`
/// is CIC's own `M`, typically 1 or 2) at the (now decimated) rate.
///
/// KNOWN, DOCUMENTED LIMITATION, the same one `sd_graph`'s own rate-
/// propagation already documents (see README.md's "Architecture
/// decisions"): `computeTransferFunction` doesn't model a
/// [downsampler] as anything but unity gain, so it cannot report ONE
/// meaningful combined `H(z)` across a genuinely decimating
/// (`decimation > 1`) CIC filter — true multirate transfer-function
/// analysis is out of scope for this project so far. What this
/// function's own tests verify instead: the integrator cascade's own
/// `H(z) = 1/(1-z⁻¹)^N` and the comb cascade's own `H(z) =
/// (1-z⁻ᴰ)^N`, each independently correct on its own (neither crosses
/// the rate change); a `decimation: 1` CIC filter has no [downsampler]
/// in it at all, so its FULL, combined `H(z)` — the product of both
/// halves — is exactly the meaningful, end-to-end result this
/// project's Mason engine can and does report correctly; and that a
/// genuinely decimating (`decimation > 1`) structure still validates
/// as a real, correctly-wired, no-algebraic-loop diagram.
FilterStructure buildCicFilter({
  required String idPrefix,
  required int stages,
  required int decimation,
  int differentialDelay = 1,
  double x = 0,
  double y = 0,
}) {
  if (stages < 1) {
    throw ArgumentError.value(stages, 'stages', 'must be at least 1');
  }
  if (decimation < 1) {
    throw ArgumentError.value(decimation, 'decimation', 'must be at least 1');
  }
  if (differentialDelay < 1) {
    throw ArgumentError.value(
      differentialDelay,
      'differentialDelay',
      'must be at least 1',
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
    pickoffNode.instantiate(instanceId: tapId, x: x, y: y + 2 * _stageDy),
  );
  var curId = tapId;
  var curPort = 'out1';

  for (var i = 0; i < stages; i++) {
    final stageX = x + (i + 1) * _stageDx;
    final d = nextId('d');
    elements.add(
      delay.instantiate(instanceId: d, x: stageX, y: y + 4 * _stageDy),
    );
    final add = nextId('add');
    elements.add(
      adder.instantiate(instanceId: add, x: stageX, y: y + 2 * _stageDy),
    );
    wire(curId, curPort, add, 'in1');
    wire(d, 'out1', add, 'in2');
    wire(add, 'out1', d, 'in1');
    curId = add;
    curPort = 'out1';
  }

  final decimatedX = x + (stages + 1) * _stageDx;
  if (decimation > 1) {
    final ds = nextId('ds');
    elements.add(
      downsampler.instantiate(
        instanceId: ds,
        x: decimatedX,
        y: y + 2 * _stageDy,
        params: {'M': decimation},
      ),
    );
    wire(curId, curPort, ds, 'in1');
    curId = ds;
    curPort = 'out1';
  }

  for (var i = 0; i < stages; i++) {
    final stageX = decimatedX + (i + 1) * _stageDx;
    final d = nextId('d');
    elements.add(
      delay.instantiate(
        instanceId: d,
        x: stageX,
        y: y + 4 * _stageDy,
        params: {'k': differentialDelay},
      ),
    );
    wire(curId, curPort, d, 'in1');
    final add = nextId('add');
    elements.add(
      adder.instantiate(
        instanceId: add,
        x: stageX,
        y: y + 2 * _stageDy,
        params: {
          'signs': ['+', '-'],
        },
      ),
    );
    wire(curId, curPort, add, 'in1');
    wire(d, 'out1', add, 'in2');
    curId = add;
    curPort = 'out1';
  }

  return FilterStructure(
    elements: elements,
    inputBlockId: tapId,
    inputPortId: 'in1',
    outputBlockId: curId,
    outputPortId: curPort,
  );
}
