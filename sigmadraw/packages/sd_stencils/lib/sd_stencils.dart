/// The DSP symbol library for SigmaDraw (§5): stencil definitions (SVG
/// geometry generator + ports + parameter schema + semantic mapping),
/// instantiated as real, placeable `SdElement`s with the full block dual
/// representation. Ships §5.1-§5.4, §5.6-§5.10's leaf stencils, and
/// §5.5's filter *structures* as composite generators (`buildFirDirectForm`
/// et al. — see `filter_templates.dart`; every other subsection's stencils
/// are single placeable blocks). §5.7 (`comms.dart`)/§5.8 (`adaptive.dart`)
/// are mostly "topological/visual only" boxes — real modulation/
/// synchronization/adaptive-filter blocks are whole subsystems, not one
/// concrete z-domain gain, the same honest simplification `control.dart`'s
/// `plant`/`controller` already make for §5.9. §5.11 (analysis-plot
/// objects) isn't implemented as placeable stencils — those live as
/// live-computed panels instead (`sd_render`/`sd_ui`).
library;

export 'src/adaptive.dart';
export 'src/comms.dart';
export 'src/control.dart';
export 'src/edge_builder.dart';
export 'src/filter_templates.dart';
export 'src/geometry.dart';
export 'src/hardware.dart';
export 'src/markers.dart';
export 'src/port_spec.dart';
export 'src/primitives.dart';
export 'src/quantization.dart';
export 'src/registry.dart';
export 'src/stencil_definition.dart';
export 'src/transforms.dart';
