/// SVG DOM document model for SigmaDraw: an observable, namespace-aware XML
/// tree with lossless round-trip (including foreign/unknown content), plus
/// typed accessors over the private `sd:` semantic namespace.
///
/// See `sigmadraw-implementation-prompt.md` §3. This package is pure Dart
/// (no Flutter dependency) so it can be parsed/serialized off the UI
/// isolate and unit-tested with plain `dart test` — see
/// [SdChangeNotifier]'s doc comment for how a Flutter layer bridges its
/// change notifications to a real `Listenable`.
library;

export 'src/blank_document.dart';
export 'src/clone.dart';
export 'src/document_tree.dart';
export 'src/namespaces.dart';
export 'src/qname.dart';
export 'src/save_mode.dart';
export 'src/semantics/block_semantics.dart';
export 'src/semantics/document_semantics.dart';
export 'src/semantics/edge_semantics.dart';
export 'src/semantics/latex_semantics.dart';
export 'src/semantics/layer_semantics.dart';
export 'src/semantics/sd_attributes.dart';
export 'src/semantics/stroke_semantics.dart';
export 'src/xml_codec.dart';
