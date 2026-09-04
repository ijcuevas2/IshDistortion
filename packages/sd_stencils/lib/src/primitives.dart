import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _d = StencilMetrics.operatorDiameter; // 40 — operator circle diameter
const _sq = StencilMetrics.squareBlock; // 80 — square block side
const _nr = StencilMetrics.nodeRadius; // 10 — pickoff node radius

/// §5.1 primitive: summing junction. Also covers "subtractor" and the
/// quadrant/cross summer: `signs` (one `'+'`/`'-'` per input, in port
/// order) covers all three — a subtractor is just `signs: ['+', '-']`.
/// See `sd_stencils` README-equivalent doc on `StencilCategory.primitives`
/// for why this isn't three separate stencil ids.
final adder = StencilDefinition(
  id: 'adder',
  category: StencilCategory.primitives,
  displayName: 'Adder / Summing Junction',
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
      id: 'in2',
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
  defaultParams: const {
    'signs': ['+', '+'],
  },
  geometryBuilder: (params) {
    final signs =
        (params['signs'] as List?)?.cast<String>() ?? const ['+', '+'];
    return [
      circleShape(cx: _d / 2, cy: _d / 2, r: _d / 2),
      if (signs.isNotEmpty)
        textLabel(
          x: _d * 0.3,
          y: _d / 2 + 5,
          text: signs[0],
          fontSize: _d * 0.35,
        ),
      if (signs.length > 1)
        textLabel(x: _d / 2, y: _d * 0.35, text: signs[1], fontSize: _d * 0.35),
    ];
  },
);

/// §5.1: multiplier/gain triangle. `gain` renders as plain text inside the
/// triangle (§11's LaTeX-rendered version lands in Phase 9).
final gain = StencilDefinition(
  id: 'gain',
  category: StencilCategory.primitives,
  displayName: 'Gain',
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
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  defaultParams: const {'gain': 1.0},
  geometryBuilder: (params) => [
    polygonShape([(0, 0), (0, _d), (_d, _d / 2)]),
    textLabel(
      x: _d * 0.32,
      y: _d / 2 + 4,
      text: '${params['gain']}',
      fontSize: _d * 0.3,
      anchor: 'start',
    ),
  ],
);

/// §5.1: pickoff/branch node — `filled` selects `dspnodefull` vs
/// `dspnodeopen`. Multiple edges may share this block's `out1` as their
/// `sd:from` to represent branching; no separate port per branch is
/// needed (§4's edge model already allows fan-out from one port).
final pickoffNode = StencilDefinition(
  id: 'pickoff-node',
  category: StencilCategory.primitives,
  displayName: 'Pickoff Node',
  directFeedthrough: true,
  width: _nr * 2,
  height: _nr * 2,
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _nr,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _nr * 2,
      y: _nr,
      angle: 0,
    ),
  ],
  defaultParams: const {'filled': true},
  geometryBuilder: (params) {
    final filled = params['filled'] != false;
    return [
      filled
          ? filledDot(cx: _nr, cy: _nr, r: _nr * 0.6)
          : circleShape(cx: _nr, cy: _nr, r: _nr * 0.6, fill: '#ffffff'),
    ];
  },
);

/// §5.1: signal source / constant — one output, no input.
final source = StencilDefinition(
  id: 'source',
  category: StencilCategory.primitives,
  displayName: 'Source / Constant',
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
  defaultLabel: 'x[n]',
  geometryBuilder: (params) => [
    lineShape(x1: 0, y1: _d / 2, x2: _d, y2: _d / 2),
    textLabel(x: _d / 2, y: _d * 0.3, text: '${params['label'] ?? ''}'),
  ],
);

/// §5.1: sink / output — one input, no output.
final sink = StencilDefinition(
  id: 'sink',
  category: StencilCategory.primitives,
  displayName: 'Sink / Output',
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
  ],
  defaultLabel: 'y[n]',
  geometryBuilder: (params) => [
    lineShape(x1: 0, y1: _d / 2, x2: _d, y2: _d / 2),
  ],
);

StencilDefinition _delayLike({
  required String id,
  required String displayName,
  required String Function(Map<String, Object?>) labelBuilder,
  required Map<String, Object?> defaultParams,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.delayShift,
  displayName: displayName,
  // A delay holds state: its output at time n does NOT depend on its
  // input at time n — this is exactly what breaks an algebraic loop
  // (§4). Every other stencil in this file defaults to true; this is the
  // one place that matters.
  directFeedthrough: false,
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
  defaultParams: defaultParams,
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 8,
      text: labelBuilder(params),
      fontSize: _sq * 0.3,
    ),
  ],
);

/// §5.2: unit/general delay `z^-k` (param `k`, default 1 -> "z⁻¹").
final delay = _delayLike(
  id: 'delay',
  displayName: 'Delay (z⁻ᵏ)',
  defaultParams: const {'k': 1},
  labelBuilder: (params) =>
      'z${_superscriptMinus((params['k'] as num?)?.toInt() ?? 1)}',
);

/// §5.2: continuous delay `e^-sT` (param `T`).
final continuousDelay = _delayLike(
  id: 'continuous-delay',
  displayName: 'Continuous Delay (e⁻ˢᵀ)',
  defaultParams: const {'T': 1},
  labelBuilder: (params) => 'e⁻ˢ${params['T']}',
);

const _superscripts = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
};

String _superscriptDigits(int n) =>
    n.toString().split('').map((c) => _superscripts[c] ?? c).join();

String _superscriptMinus(int k) => k == 1 ? '⁻¹' : '⁻${_superscriptDigits(k)}';

StencilDefinition _multirateLike({
  required String id,
  required String displayName,
  required String Function(Map<String, Object?>) labelBuilder,
  required Map<String, Object?> defaultParams,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.multirateSampling,
  displayName: displayName,
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
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  defaultParams: defaultParams,
  geometryBuilder: (params) => [
    polygonShape([
      (_d / 2, 0),
      (_d, _d / 2),
      (_d / 2, _d),
      (0, _d / 2),
    ]), // diamond, tikz-dsp style
    textLabel(
      x: _d / 2,
      y: _d / 2 + 4,
      text: labelBuilder(params),
      fontSize: _d * 0.32,
    ),
  ],
);

/// §5.3: upsampler `↑L` (rate ×L, param `L`).
final upsampler = _multirateLike(
  id: 'upsampler',
  displayName: 'Upsampler (↑L)',
  defaultParams: const {'L': 2},
  labelBuilder: (p) => '↑${p['L']}',
);

/// §5.3: downsampler/decimator `↓M` (rate /M, param `M`).
final downsampler = _multirateLike(
  id: 'downsampler',
  displayName: 'Downsampler (↓M)',
  defaultParams: const {'M': 2},
  labelBuilder: (p) => '↓${p['M']}',
);

/// §5.3: ideal sampler/switch.
final sampler = StencilDefinition(
  id: 'sampler',
  category: StencilCategory.multirateSampling,
  displayName: 'Ideal Sampler',
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
      id: 'out1',
      direction: PortDirection.output,
      x: _d,
      y: _d / 2,
      angle: 0,
    ),
  ],
  geometryBuilder: (params) => [
    lineShape(x1: 0, y1: _d / 2, x2: _d * 0.35, y2: _d / 2),
    lineShape(x1: _d * 0.35, y1: _d / 2, x2: _d * 0.7, y2: _d * 0.2),
    filledDot(cx: _d * 0.35, cy: _d / 2, r: _nr * 0.3),
    filledDot(cx: _d * 0.7, cy: _d / 2, r: _nr * 0.3),
    lineShape(x1: _d * 0.7, y1: _d / 2, x2: _d, y2: _d / 2),
  ],
);

StencilDefinition _holdLike(String id, String displayName, String label) =>
    StencilDefinition(
      id: id,
      category: StencilCategory.multirateSampling,
      displayName: displayName,
      directFeedthrough: true,
      width: _sq,
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
          id: 'out1',
          direction: PortDirection.output,
          x: _sq,
          y: _d / 2,
          angle: 0,
        ),
      ],
      geometryBuilder: (params) => [
        rectShape(x: 0, y: 0, width: _sq, height: _d),
        textLabel(x: _sq / 2, y: _d / 2 + 5, text: label, fontSize: _d * 0.4),
      ],
    );

/// §5.3: zero-order hold.
final zeroOrderHold = _holdLike('zoh', 'Zero-Order Hold', 'ZOH');

/// §5.3: first-order hold.
final firstOrderHold = _holdLike('foh', 'First-Order Hold', 'FOH');

/// Every stencil defined in this file, in a stable, deliberate palette
/// order (roughly matching §5's own subsection order).
final List<StencilDefinition> corePrimitiveStencils = [
  adder,
  gain,
  pickoffNode,
  source,
  sink,
  delay,
  continuousDelay,
  upsampler,
  downsampler,
  sampler,
  zeroOrderHold,
  firstOrderHold,
];
