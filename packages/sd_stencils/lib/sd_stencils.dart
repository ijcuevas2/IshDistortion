/// The DSP symbol library for SigmaDraw (§5): stencil definitions (SVG
/// geometry generator + ports + parameter schema + semantic mapping),
/// instantiated as real, placeable `SdElement`s with the full block dual
/// representation. Ships §5.1-5.3 (primitives, delay/shift, multirate) —
/// see `primitives.dart`'s doc comments for the deliberate scope cuts
/// (composite/macro stencils like tapped-delay-line land in Phase 7).
library;

export 'src/geometry.dart';
export 'src/markers.dart';
export 'src/port_spec.dart';
export 'src/primitives.dart';
export 'src/registry.dart';
export 'src/stencil_definition.dart';
