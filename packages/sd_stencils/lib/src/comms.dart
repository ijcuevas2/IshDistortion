import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _d = StencilMetrics.operatorDiameter;
const _sq = StencilMetrics.squareBlock;

/// A labeled 1-in/1-out box, the same "topological/visual only" shape
/// `control.dart`'s `_controlBox` already establishes for §5.9 — most of
/// §5.7's stencils don't have a simple, concrete z-domain gain the way
/// `gain`/`delay` do (real modulation/synchronization blocks are whole
/// subsystems in their own right), so this project represents them
/// honestly as labeled boxes rather than pretending a fabricated scalar
/// transfer function for each one.
StencilDefinition _commsBox({
  required String id,
  required String displayName,
  required String defaultLabel,
  bool directFeedthrough = true,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.commsModulation,
  displayName: displayName,
  directFeedthrough: directFeedthrough,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  defaultLabel: defaultLabel,
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 6,
      text: '${params['label'] ?? defaultLabel}',
      fontSize: _sq * 0.22,
    ),
  ],
);

/// A pure source (0 in, 1 out), the same shape `primitives.dart`'s own
/// `source` stencil already establishes.
StencilDefinition _commsSource({
  required String id,
  required String displayName,
  required String defaultLabel,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.commsModulation,
  displayName: displayName,
  directFeedthrough: true,
  width: _d,
  height: _d,
  ports: const [
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  defaultLabel: defaultLabel,
  geometryBuilder: (params) => [
    lineShape(x1: 0, y1: _d / 2, x2: _d, y2: _d / 2),
    textLabel(
      x: _d / 2,
      y: _d * 0.3,
      text: '${params['label'] ?? defaultLabel}',
      fontSize: _d * 0.28,
    ),
  ],
);

/// §5.7: mixer (frequency conversion) — the "circle x" (⊗) symbol,
/// signal in one port and a local-oscillator drive in the other.
final mixer = StencilDefinition(
  id: 'mixer',
  category: StencilCategory.commsModulation,
  displayName: 'Mixer',
  directFeedthrough: true,
  width: _d,
  height: _d,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _d / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'lo',
      direction: PortDirection.input,
      x: _d / 2,
      y: 0,
      angle: 270,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    circleShape(cx: _d / 2, cy: _d / 2, r: _d / 2),
    lineShape(x1: _d * 0.2, y1: _d * 0.2, x2: _d * 0.8, y2: _d * 0.8),
    lineShape(x1: _d * 0.2, y1: _d * 0.8, x2: _d * 0.8, y2: _d * 0.2),
  ],
);

/// §5.7: NCO/DDS (numerically-controlled oscillator) — a self-driven
/// source, like `source`/`awgnSource`, parameterized by its own
/// frequency word rather than fed one via a port (a real NCO's phase
/// accumulator is exactly the kind of internal state `plant`/
/// `controller` already leave unmodeled at this project's z-domain-only
/// analysis depth).
final nco = _commsSource(
  id: 'nco',
  displayName: 'NCO / DDS',
  defaultLabel: 'NCO',
);

/// §5.7: phase shifter (param `degrees`).
final phaseShifter = StencilDefinition(
  id: 'phase-shifter',
  category: StencilCategory.commsModulation,
  displayName: 'Phase Shifter',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  defaultParams: const {'degrees': 90},
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 6,
      text: '${params['degrees']}°',
      fontSize: _sq * 0.24,
    ),
  ],
);

/// §5.7: 90-degree hybrid — one input split into two quadrature
/// (90°-apart) outputs. Has two independent outputs from one input, the
/// same shape `transforms.dart`'s `butterfly` already flags: `sd_graph`'s
/// Mason engine tracks paths by block id, not `(block, port)`, so a
/// diagram where both outputs reconverge downstream may not get a fully
/// correct `H(z)` until that engine is made port-aware — see that
/// stencil's own doc comment for the fuller explanation.
final hybrid90 = StencilDefinition(
  id: 'hybrid-90',
  category: StencilCategory.commsModulation,
  displayName: '90° Hybrid',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'out0',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.25,
      angle: 0,
    ),
    PortSpec(
      id: 'out90',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.75,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(x: _sq / 2, y: _sq * 0.4, text: '0°/90°', fontSize: _sq * 0.2),
    textLabel(x: _sq / 2, y: _sq * 0.65, text: 'HYBRID', fontSize: _sq * 0.16),
  ],
);

/// §5.7: I/Q modulator — combines baseband I and Q into one passband
/// signal.
final iqModulator = StencilDefinition(
  id: 'iq-modulator',
  category: StencilCategory.commsModulation,
  displayName: 'I/Q Modulator',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'i',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.3,
      angle: 180,
    ),
    PortSpec(
      id: 'q',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.7,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(x: _sq / 2, y: _sq / 2 + 6, text: 'I/Q MOD', fontSize: _sq * 0.2),
  ],
);

/// §5.7: I/Q demodulator — splits one passband signal into baseband I
/// and Q. Two independent outputs from one input — see [hybrid90]'s own
/// doc comment on the same Mason-analysis caveat this shares.
final iqDemodulator = StencilDefinition(
  id: 'iq-demodulator',
  category: StencilCategory.commsModulation,
  displayName: 'I/Q Demodulator',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'i',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.3,
      angle: 0,
    ),
    PortSpec(
      id: 'q',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.7,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 6,
      text: 'I/Q DEMOD',
      fontSize: _sq * 0.17,
    ),
  ],
);

/// §5.7: matched filter.
final matchedFilter = _commsBox(
  id: 'matched-filter',
  displayName: 'Matched Filter',
  defaultLabel: 'MF',
);

/// §5.7/§5.8: correlator — compares two signals (shared between comms
/// synchronization and the adaptive/statistical family — see
/// `adaptive.dart`'s own doc comment).
final correlator = StencilDefinition(
  id: 'correlator',
  category: StencilCategory.commsModulation,
  displayName: 'Correlator',
  directFeedthrough: false, // correlation integrates over a window.
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.3,
      angle: 180,
    ),
    PortSpec(
      id: 'ref',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.7,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(x: _sq / 2, y: _sq / 2 + 6, text: 'CORR', fontSize: _sq * 0.22),
  ],
);

/// §5.7: integrate-and-dump — accumulates over a symbol period then
/// resets; has state.
final integrateAndDump = _commsBox(
  id: 'integrate-and-dump',
  displayName: 'Integrate & Dump',
  defaultLabel: '∫dt',
  directFeedthrough: false,
);

/// §5.7: PLL phase detector — compares a reference and a feedback
/// signal, outputting their phase error.
final phaseDetector = StencilDefinition(
  id: 'phase-detector',
  category: StencilCategory.commsModulation,
  displayName: 'Phase Detector',
  directFeedthrough: true,
  width: _d,
  height: _d,
  ports: const [
    PortSpec(
      id: 'ref',
      direction: PortDirection.input,
      x: 0,
      y: _d * 0.3,
      angle: 180,
    ),
    PortSpec(
      id: 'fb',
      direction: PortDirection.input,
      x: 0,
      y: _d * 0.7,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    circleShape(cx: _d / 2, cy: _d / 2, r: _d / 2),
    textLabel(x: _d / 2, y: _d / 2 + 4, text: 'PD', fontSize: _d * 0.3),
  ],
);

/// §5.7: PLL loop filter — the same "topological box" shape as
/// `control.dart`'s `plant`/`controller`.
final loopFilter = _commsBox(
  id: 'loop-filter',
  displayName: 'Loop Filter',
  defaultLabel: 'LF',
);

/// §5.7: PLL/Costas-loop VCO (voltage-controlled oscillator) — its
/// control input drives an internally-*integrated* phase, so — like
/// `control.dart`'s `integrator` — it has state.
final vco = _commsBox(
  id: 'vco',
  displayName: 'VCO',
  defaultLabel: 'VCO',
  directFeedthrough: false,
);

/// §5.7: PLL frequency divider (param `n`).
final frequencyDivider = StencilDefinition(
  id: 'frequency-divider',
  category: StencilCategory.commsModulation,
  displayName: 'Frequency Divider',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  defaultParams: const {'n': 2},
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 6,
      text: '÷${params['n']}',
      fontSize: _sq * 0.26,
    ),
  ],
);

/// §5.7: Costas loop — a whole carrier-recovery subsystem, drawn as one
/// labeled box (the same honest simplification `control.dart`'s
/// `plant`/`controller` already make for "an arbitrarily complex system,
/// diagrammed as a single symbol") rather than forcing its own internal
/// mixer/VCO/loop-filter wiring to be re-drawn inline every time — those
/// same sub-blocks ([phaseDetector], [loopFilter], [vco], [mixer]) are
/// all separately placeable for a diagram that wants to show a Costas
/// loop's own internals explicitly instead.
final costasLoop = _commsBox(
  id: 'costas-loop',
  displayName: 'Costas Loop',
  defaultLabel: 'Costas',
  directFeedthrough: false,
);

/// §5.7: automatic gain control — has state (its own gain adapts over
/// time).
final agc = _commsBox(
  id: 'agc',
  displayName: 'AGC',
  defaultLabel: 'AGC',
  directFeedthrough: false,
);

/// §5.7: (adaptive) equalizer — has state, the same as [agc]/[lms]/
/// [rls] in `adaptive.dart`.
final equalizer = _commsBox(
  id: 'equalizer',
  displayName: 'Equalizer',
  defaultLabel: 'EQ',
  directFeedthrough: false,
);

/// §5.7: interleaver — reorders across multiple samples; has state.
final interleaver = _commsBox(
  id: 'interleaver',
  displayName: 'Interleaver',
  defaultLabel: 'INTLV',
  directFeedthrough: false,
);

/// §5.7: deinterleaver — the inverse of [interleaver]; has state.
final deinterleaver = _commsBox(
  id: 'deinterleaver',
  displayName: 'Deinterleaver',
  defaultLabel: 'DEINTLV',
  directFeedthrough: false,
);

/// §5.7: (channel) encoder.
final encoder = _commsBox(
  id: 'encoder',
  displayName: 'Encoder',
  defaultLabel: 'ENC',
);

/// §5.7: (channel) decoder.
final decoder = _commsBox(
  id: 'decoder',
  displayName: 'Decoder',
  defaultLabel: 'DEC',
);

/// §5.7: symbol mapper (bits -> symbols).
final mapper = _commsBox(
  id: 'mapper',
  displayName: 'Mapper',
  defaultLabel: 'MAP',
);

/// §5.7: symbol demapper (symbols -> bits).
final demapper = _commsBox(
  id: 'demapper',
  displayName: 'Demapper',
  defaultLabel: 'DEMAP',
);

/// §5.7: RRC (root-raised-cosine) pulse shaper (param `rolloff`).
final rrcPulseShaper = StencilDefinition(
  id: 'rrc-pulse-shaper',
  category: StencilCategory.commsModulation,
  displayName: 'RRC Pulse Shaper',
  directFeedthrough: true,
  width: StencilMetrics.filterBlockWidth,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: StencilMetrics.filterBlockWidth,
      y: _sq / 2,
      angle: 0,
    ),
  ],
  defaultParams: const {'rolloff': 0.35},
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: StencilMetrics.filterBlockWidth, height: _sq),
    textLabel(
      x: StencilMetrics.filterBlockWidth / 2,
      y: _sq / 2 - 4,
      text: 'RRC',
      fontSize: _sq * 0.22,
    ),
    textLabel(
      x: StencilMetrics.filterBlockWidth / 2,
      y: _sq / 2 + 14,
      text: 'α=${params['rolloff']}',
      fontSize: _sq * 0.16,
    ),
  ],
);

/// §5.7: channel (models a communications channel's own distortion —
/// topological/visual only, like `control.dart`'s `plant`).
final channel = _commsBox(
  id: 'channel',
  displayName: 'Channel',
  defaultLabel: 'H',
);

/// §5.7: AWGN (additive white Gaussian noise) source — a pure source, the
/// same shape as `primitives.dart`'s `source` (param `variance`).
final awgnSource = _commsSource(
  id: 'awgn-source',
  displayName: 'AWGN Source',
  defaultLabel: 'AWGN',
);

/// §5.7: constellation object — a reference/parameter block naming the
/// modulation scheme's own symbol constellation (e.g. for [mapper]/
/// [demapper] to cite), distinct from §5.11's *constellation plot*
/// (an analysis-plot visualization of a live signal, not yet built —
/// see the repo's own README "What's not built").
final constellation = _commsBox(
  id: 'constellation',
  displayName: 'Constellation',
  defaultLabel: 'QPSK',
);

final List<StencilDefinition> commsStencils = [
  mixer,
  nco,
  phaseShifter,
  hybrid90,
  iqModulator,
  iqDemodulator,
  matchedFilter,
  correlator,
  integrateAndDump,
  phaseDetector,
  loopFilter,
  vco,
  frequencyDivider,
  costasLoop,
  agc,
  equalizer,
  interleaver,
  deinterleaver,
  encoder,
  decoder,
  mapper,
  demapper,
  rrcPulseShaper,
  channel,
  awgnSource,
  constellation,
];
