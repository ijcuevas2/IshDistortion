import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _sq = StencilMetrics.squareBlock;

/// A labeled hardware box. If a caller overrides [width] without also
/// overriding [ports], the default ports (positioned for the default
/// [_sq] width) will land outside a narrower box or short of a wider one
/// — always pass a matching `ports` list alongside a custom `width`.
StencilDefinition _hwBox(
  String id,
  String displayName,
  String label, {
  List<PortSpec> ports = const [
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
  bool directFeedthrough = true,
  double width = _sq,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.hardware,
  displayName: displayName,
  directFeedthrough: directFeedthrough,
  width: width,
  height: _sq,
  ports: ports,
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: width, height: _sq),
    textLabel(x: width / 2, y: _sq / 2 + 6, text: label, fontSize: _sq * 0.24),
  ],
);

/// §5.10: multiply-accumulate — one fused multiply-add step. Wire its
/// output back through a [register]/[accumulator] to build true
/// accumulation (kept composable rather than baking state in here).
final mac = StencilDefinition(
  id: 'mac',
  category: StencilCategory.hardware,
  displayName: 'MAC',
  directFeedthrough: true,
  width: _sq,
  height: _sq,
  ports: const [
    PortSpec(
      id: 'a',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.3,
      angle: 180,
    ),
    PortSpec(
      id: 'b',
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
    textLabel(x: _sq / 2, y: _sq / 2 + 6, text: 'MAC', fontSize: _sq * 0.24),
  ],
);

/// §5.10: accumulator (has state — output depends on history, not just
/// the current input).
final accumulator = _hwBox(
  'accumulator',
  'Accumulator',
  'ACC',
  directFeedthrough: false,
);

/// §5.10: a pipeline/state register — semantically a unit delay, framed
/// as hardware.
final register = _hwBox(
  'register',
  'Register',
  'REG',
  directFeedthrough: false,
);

/// §5.10: 2-to-1 multiplexer.
final mux = _hwBox(
  'mux',
  'Multiplexer',
  'MUX',
  ports: const [
    PortSpec(
      id: 'in0',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.25,
      angle: 180,
    ),
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.75,
      angle: 180,
    ),
    PortSpec(
      id: 'sel',
      direction: PortDirection.input,
      x: _sq / 2,
      y: 0,
      dtype: 'bit',
      angle: 270,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
);

/// §5.10: 1-to-2 demultiplexer.
final demux = _hwBox(
  'demux',
  'Demultiplexer',
  'DEMUX',
  ports: const [
    PortSpec(
      id: 'in1',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      angle: 180,
    ),
    PortSpec(
      id: 'sel',
      direction: PortDirection.input,
      x: _sq / 2,
      y: 0,
      dtype: 'bit',
      angle: 270,
    ),
    PortSpec(
      id: 'out0',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.25,
      angle: 0,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.75,
      angle: 0,
    ),
  ],
);

/// §5.10: coefficient memory / ROM (address in, data out).
final rom = _hwBox(
  'rom',
  'ROM / Coefficient Memory',
  'ROM',
  ports: const [
    PortSpec(
      id: 'addr',
      direction: PortDirection.input,
      x: 0,
      y: _sq / 2,
      dtype: 'int',
      angle: 180,
    ),
    PortSpec(
      id: 'data',
      direction: PortDirection.output,
      x: _sq,
      y: _sq / 2,
      angle: 0,
    ),
  ],
);

/// §5.10: systolic-array cell — a MAC with a pass-through data tap,
/// modeled as a labeled box pending real systolic-array layout support.
/// Uses the default (square) width/ports — see [_hwBox]'s doc on why a
/// custom `width` there needs matching custom `ports` too.
final systolicCell = _hwBox('systolic-cell', 'Systolic Array Cell', 'PE');

final List<StencilDefinition> hardwareStencils = [
  mac,
  accumulator,
  register,
  mux,
  demux,
  rom,
  systolicCell,
];
