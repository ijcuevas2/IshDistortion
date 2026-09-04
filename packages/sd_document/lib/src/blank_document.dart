import 'document_tree.dart';
import 'namespaces.dart';
import 'qname.dart';
import 'semantics/document_semantics.dart';

/// Creates a minimal, valid SigmaDraw document: an `<svg>` root in the
/// standard SVG namespace (declared as default) with `xmlns:sd` declared
/// up front, sized to [width]×[height], and the document-level `sd:*`
/// metadata set (§3).
SdDocument createBlankSdDocument({
  num width = 800,
  num height = 600,
  String schema = '1.0',
  String? sampleRate,
  String? defaultDtype,
}) {
  final root = SdElement(
    const SdQName('svg', SdNamespace.svg),
    namespaceDeclarations: {null: SdNamespace.svg, SdPrefix.sd: SdNamespace.sd},
    attributes: {
      const SdQName('width'): '$width',
      const SdQName('height'): '$height',
      const SdQName('viewBox'): '0 0 $width $height',
    },
  );
  final document = SdDocument(
    root: root,
    xmlVersion: '1.0',
    xmlEncoding: 'UTF-8',
  )..schema = schema;
  if (sampleRate != null) document.sampleRate = sampleRate;
  if (defaultDtype != null) document.defaultDtype = defaultDtype;
  return document;
}
