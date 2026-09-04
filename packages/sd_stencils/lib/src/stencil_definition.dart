import 'package:sd_document/sd_document.dart';

import 'geometry.dart';
import 'port_spec.dart';

/// Which §5 subsection a stencil belongs to — drives palette grouping.
enum StencilCategory {
  primitives, // §5.1
  delayShift, // §5.2
  multirateSampling, // §5.3
  quantizationConversion, // §5.4
  filterStructures, // §5.5
  transforms, // §5.6
  commsModulation, // §5.7
  adaptiveStatistical, // §5.8
  controlOverlap, // §5.9
  hardware, // §5.10
  analysisPlots, // §5.11
}

enum ParamType { number, integer, text, boolean, choice }

/// One entry in a stencil's editable-parameter schema — enough for
/// `sd_ui`'s inspector (Phase 3/5) to generate a typed editor without the
/// inspector needing to know about any specific stencil.
class ParamField {
  const ParamField({
    required this.key,
    required this.label,
    required this.type,
    this.choices = const [],
    this.min,
    this.max,
  });

  final String key;
  final String label;
  final ParamType type;
  final List<String> choices; // for ParamType.choice
  final num? min;
  final num? max;
}

typedef GeometryBuilder = List<SdElement> Function(Map<String, Object?> params);

/// Everything needed to place and (re-)render one kind of DSP symbol (§5):
/// its id/category, an SVG geometry generator, its ports, its parameter
/// schema, a default label, and whether it passes signal through within
/// the same sample instant (`directFeedthrough` — false only for
/// state-holding blocks; `sd_graph`'s algebraic-loop detection, Phase 4,
/// needs this on every block).
class StencilDefinition {
  const StencilDefinition({
    required this.id,
    required this.category,
    required this.displayName,
    required this.geometryBuilder,
    this.ports = const [],
    this.paramSchema = const [],
    this.defaultParams = const {},
    this.defaultLabel,
    this.directFeedthrough = true,
    this.width = StencilMetrics.squareBlock,
    this.height = StencilMetrics.squareBlock,
  });

  final String id;
  final StencilCategory category;
  final String displayName;
  final GeometryBuilder geometryBuilder;
  final List<PortSpec> ports;
  final List<ParamField> paramSchema;
  final Map<String, Object?> defaultParams;
  final String? defaultLabel;
  final bool directFeedthrough;

  /// Nominal footprint — palette icon sizing and default placement spacing.
  final double width;
  final double height;

  /// Builds a real, placeable instance: a `<g transform="translate(x,y)">`
  /// wrapping real SVG geometry, decorated with the `sd:*` dual-
  /// representation attributes (§3) — `sd_document`'s `SdBlockSemantics`.
  SdElement instantiate({
    required String instanceId,
    double x = 0,
    double y = 0,
    Map<String, Object?>? params,
    String? label,
  }) {
    final effectiveParams = <String, Object?>{...defaultParams, ...?params};
    return SdElement(
        const SdQName('g'),
        attributes: {const SdQName('transform'): 'translate($x,$y)'},
        children: geometryBuilder(effectiveParams),
      )
      ..blockType = id
      ..blockId = instanceId
      ..blockLabel = label ?? defaultLabel
      ..blockParams = effectiveParams
      ..blockPorts = [for (final p in ports) p.toJson()];
  }
}
