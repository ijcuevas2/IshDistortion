import 'comms.dart' show correlator;
import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _sq = StencilMetrics.squareBlock;

/// §5.8: an adaptive filter (LMS/RLS) block — a *signal* input, an
/// *error* input (the spec's own "block with error input" — the
/// adaptation target, distinct from the signal being filtered), and one
/// output; has state (its own coefficients adapt sample by sample, so
/// `directFeedthrough: false`, the same reasoning `primitives.dart`'s
/// `delay` and `control.dart`'s `integrator` already document for any
/// state-holding block).
///
/// The dashed line is the spec's own "dashed coefficient-update path" —
/// a schematic indicator that the error feeds an *internal* coefficient
/// update, not a real, separately-wireable port (this project's block
/// model has no notion of "a filter's own internal taps" to wire to
/// anyway — the same reason `control.dart`'s `plant`/`controller` stay
/// single opaque boxes rather than exposing internals that don't exist
/// as separate blocks).
StencilDefinition _adaptiveFilterBox({
  required String id,
  required String displayName,
  required String defaultLabel,
}) => StencilDefinition(
  id: id,
  category: StencilCategory.adaptiveStatistical,
  displayName: displayName,
  directFeedthrough: false,
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
      id: 'error',
      direction: PortDirection.input,
      x: 0,
      y: _sq * 0.7,
      angle: 180,
    ),
    PortSpec(
      id: 'out1',
      direction: PortDirection.output,
      x: _sq,
      y: _sq * 0.3,
      angle: 0,
    ),
  ],
  defaultLabel: defaultLabel,
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq * 0.4,
      text: '${params['label'] ?? defaultLabel}',
      fontSize: _sq * 0.24,
    ),
    lineShape(
      x1: _sq * 0.15,
      y1: _sq * 0.7,
      x2: _sq * 0.85,
      y2: _sq * 0.7,
      dashArray: '4,3',
    ),
  ],
);

/// §5.8: LMS (least-mean-squares) adaptive filter.
final lms = _adaptiveFilterBox(
  id: 'lms',
  displayName: 'LMS Adaptive Filter',
  defaultLabel: 'LMS',
);

/// §5.8: RLS (recursive-least-squares) adaptive filter.
final rls = _adaptiveFilterBox(
  id: 'rls',
  displayName: 'RLS Adaptive Filter',
  defaultLabel: 'RLS',
);

/// §5.8: a generic estimator block (e.g. a parameter/statistic
/// estimate) — has state, the same as [lms]/[rls].
final estimator = StencilDefinition(
  id: 'estimator',
  category: StencilCategory.adaptiveStatistical,
  displayName: 'Estimator',
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
  defaultLabel: 'EST',
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(
      x: _sq / 2,
      y: _sq / 2 + 6,
      text: '${params['label'] ?? 'EST'}',
      fontSize: _sq * 0.24,
    ),
  ],
);

// §5.8 also names "correlator" — the exact same stencil `comms.dart`
// already ships (§5.7 lists it too); the `import ... show correlator`
// above pulls in that one real definition rather than duplicating it,
// so both subsections' palettes point at the same stencil.
final List<StencilDefinition> adaptiveStencils = [
  lms,
  rls,
  estimator,
  correlator,
];
