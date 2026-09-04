import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _sq = StencilMetrics.squareBlock;
const _d = StencilMetrics.operatorDiameter;

StencilDefinition _transformBox(String id, String displayName, String label) =>
    StencilDefinition(
      id: id,
      category: StencilCategory.transforms,
      displayName: displayName,
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
      defaultParams: const {'N': 1024},
      paramSchema: const [
        ParamField(key: 'N', label: 'N', type: ParamType.integer),
      ],
      geometryBuilder: (params) => [
        rectShape(x: 0, y: 0, width: _sq, height: _sq),
        textLabel(x: _sq / 2, y: _sq * 0.45, text: label, fontSize: _sq * 0.24),
        textLabel(
          x: _sq / 2,
          y: _sq * 0.72,
          text: 'N=${params['N']}',
          fontSize: _sq * 0.16,
        ),
      ],
    );

/// §5.6: fast Fourier transform (or DFT at any `N`).
final fft = _transformBox('fft', 'FFT / DFT', 'FFT');

/// §5.6: inverse FFT.
final ifft = _transformBox('ifft', 'IFFT', 'IFFT');

/// §5.6: bit-reversal permutation (paired with an in-place FFT).
final bitReversal = StencilDefinition(
  id: 'bit-reversal',
  category: StencilCategory.transforms,
  displayName: 'Bit-Reversal',
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
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(x: _sq / 2, y: _sq / 2 + 6, text: '⟲bit', fontSize: _sq * 0.22),
  ],
);

/// §5.6: radix-2 butterfly (decimation-in-time by default; set
/// `stage: 'DIF'` for decimation-in-frequency — differs only in whether
/// the twiddle multiply is drawn/applied before or after the add/subtract,
/// which is a rendering/documentation distinction here, not a functional
/// one, since both inputs already carry whatever twiddle a real FFT stage
/// needs applied upstream/downstream of this primitive).
///
/// Has two independent outputs from two independent inputs — the first
/// stencil this package ships with more than one output port. `sd_graph`'s
/// Mason-formula engine (§4) tracks forward paths/loops by block id, not
/// by (block, port) pair (an intentional Phase 4 simplification, since
/// every §5.1-5.3/5.4/5.9/5.10 stencil has at most one output); a diagram
/// where this butterfly's *two* outputs both lie on paths reconverging at
/// a shared sink may not get fully correct H(z) until that engine is made
/// port-aware. The stencil and its ports are still exactly right for
/// diagramming, independent of that analysis limitation.
final butterfly = StencilDefinition(
  id: 'butterfly',
  category: StencilCategory.transforms,
  displayName: 'Radix-2 Butterfly',
  directFeedthrough: true,
  width: _d,
  height: _d,
  ports: const [
    PortSpec(id: 'x0', direction: PortDirection.input, x: 0, y: 0, angle: 180),
    PortSpec(id: 'x1', direction: PortDirection.input, x: 0, y: _d, angle: 180),
    PortSpec(id: 'y0', direction: PortDirection.output, x: _d, y: 0, angle: 0),
    PortSpec(id: 'y1', direction: PortDirection.output, x: _d, y: _d, angle: 0),
  ],
  defaultParams: const {'k': 0, 'N': 8, 'stage': 'DIT'},
  paramSchema: const [
    ParamField(key: 'k', label: 'Twiddle index k', type: ParamType.integer),
    ParamField(key: 'N', label: 'N', type: ParamType.integer),
    ParamField(
      key: 'stage',
      label: 'Stage',
      type: ParamType.choice,
      choices: ['DIT', 'DIF'],
    ),
  ],
  geometryBuilder: (params) => [
    lineShape(x1: 0, y1: 0, x2: _d, y2: 0),
    lineShape(x1: 0, y1: 0, x2: _d, y2: _d),
    lineShape(x1: 0, y1: _d, x2: _d, y2: 0),
    lineShape(x1: 0, y1: _d, x2: _d, y2: _d),
    filledDot(cx: 0, cy: 0, r: StencilMetrics.nodeRadius * 0.5),
    filledDot(cx: 0, cy: _d, r: StencilMetrics.nodeRadius * 0.5),
    filledDot(cx: _d, cy: 0, r: StencilMetrics.nodeRadius * 0.5),
    filledDot(cx: _d, cy: _d, r: StencilMetrics.nodeRadius * 0.5),
    textLabel(
      x: _d / 2,
      y: -6,
      text: 'W${params['N']}^${params['k']}',
      fontSize: _d * 0.22,
    ),
    textLabel(x: _d / 2, y: _d + 16, text: '-1', fontSize: _d * 0.22),
  ],
);

final List<StencilDefinition> transformStencils = [
  fft,
  ifft,
  bitReversal,
  butterfly,
];
