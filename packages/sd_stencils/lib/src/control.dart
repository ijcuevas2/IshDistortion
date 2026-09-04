import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _sq = StencilMetrics.squareBlock;

StencilDefinition _controlBox({
  required String id,
  required String displayName,
  required String defaultLabel,
  bool directFeedthrough = true,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.controlOverlap,
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
      fontSize: _sq * 0.24,
    ),
  ],
);

/// §5.9: the controlled system (transfer function box).
final plant = _controlBox(
  id: 'plant',
  displayName: 'Plant',
  defaultLabel: 'G(s)',
);

/// §5.9: the compensator/controller (transfer function box).
final controller = _controlBox(
  id: 'controller',
  displayName: 'Controller',
  defaultLabel: 'C(s)',
);

/// §5.9: ideal continuous-time integrator `1/s`. Has state (it's the
/// continuous-time analog of a delay), so — like `delay` — it's what a
/// feedback loop needs to avoid being reported as algebraic.
final integrator = _controlBox(
  id: 'integrator',
  displayName: 'Integrator (1/s)',
  defaultLabel: '1/s',
  directFeedthrough: false,
);

/// §5.9: ideal differentiator `s`. `sd_graph`'s Mason engine only assigns
/// a special symbolic gain to `gain`/`delay` blocks (§4 — z-domain only);
/// this and [plant]/[controller] contribute unity gain to H(z), i.e. they
/// are topological/visual only until a Laplace-domain analysis exists.
final differentiator = _controlBox(
  id: 'differentiator',
  displayName: 'Differentiator (s)',
  defaultLabel: 's',
);

final List<StencilDefinition> controlStencils = [
  plant,
  controller,
  integrator,
  differentiator,
];
