import 'geometry.dart';
import 'port_spec.dart';
import 'stencil_definition.dart';

const _sq = StencilMetrics.squareBlock;

/// A generic labeled square block (§5.4's quantization/conversion family
/// is overwhelmingly "static nonlinearity in a box with a label" —
/// quantizer/ADC/DAC/saturation/dither differ in label and default params,
/// not in shape).
StencilDefinition _labeledBox({
  required String id,
  required String displayName,
  required String label,
  Map<String, Object?> defaultParams = const {},
  List<ParamField> paramSchema = const [],
}) => StencilDefinition(
  id: id,
  category: StencilCategory.quantizationConversion,
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
  defaultParams: defaultParams,
  paramSchema: paramSchema,
  geometryBuilder: (params) => [
    rectShape(x: 0, y: 0, width: _sq, height: _sq),
    textLabel(x: _sq / 2, y: _sq / 2 + 6, text: label, fontSize: _sq * 0.26),
  ],
);

/// §5.4: quantizer (staircase). `levels` = number of quantization levels.
final quantizer = _labeledBox(
  id: 'quantizer',
  displayName: 'Quantizer',
  label: 'Q',
  defaultParams: const {'levels': 256},
  paramSchema: const [
    ParamField(key: 'levels', label: 'Levels', type: ParamType.integer),
  ],
);

/// §5.4: analog-to-digital converter.
final adc = _labeledBox(
  id: 'adc',
  displayName: 'ADC',
  label: 'ADC',
  defaultParams: const {'bits': 16},
);

/// §5.4: digital-to-analog converter.
final dac = _labeledBox(
  id: 'dac',
  displayName: 'DAC',
  label: 'DAC',
  defaultParams: const {'bits': 16},
);

/// §5.4: saturation / limiter.
final saturation = _labeledBox(
  id: 'saturation',
  displayName: 'Saturation / Limiter',
  label: 'SAT',
  defaultParams: const {'limit': 1.0},
  paramSchema: const [
    ParamField(key: 'limit', label: 'Limit', type: ParamType.number),
  ],
);

/// §5.4: rounding/truncation.
final rounding = _labeledBox(
  id: 'rounding',
  displayName: 'Rounding / Truncation',
  label: 'Round',
  defaultParams: const {'mode': 'round'},
  paramSchema: const [
    ParamField(
      key: 'mode',
      label: 'Mode',
      type: ParamType.choice,
      choices: ['round', 'truncate'],
    ),
  ],
);

/// §5.4: dither injection. Modeled as a pass-through (the actual injected
/// noise isn't a modeled signal source yet — see `sd_graph`'s `mason.dart`
/// doc comment on what branch gains it recognizes); the `amplitude` param
/// still records the intent for a later noise-modeling pass.
final ditherInjection = _labeledBox(
  id: 'dither',
  displayName: 'Dither Injection',
  label: '+dither',
  defaultParams: const {'amplitude': 1.0},
);

final List<StencilDefinition> quantizationStencils = [
  quantizer,
  adc,
  dac,
  saturation,
  rounding,
  ditherInjection,
];
