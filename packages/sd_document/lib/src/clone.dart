import 'document_tree.dart';

/// A deep, fully-detached copy of [node]: same content, namespace
/// declarations, and attributes, with every child recursively cloned too
/// — no shared mutable state with the original (mutating the clone, or
/// re-parenting it into a document, never affects [node]). Used for
/// copy/paste (§10's Home-tab Clipboard group) and for duplicating any
/// subtree that needs to exist independently of where it came from.
///
/// The clone starts with no parent/owner document, same as any other
/// freshly-constructed node — call `appendChild`/`insertChildAt` on it to
/// attach it somewhere.
SdNode cloneNode(SdNode node) {
  return switch (node) {
    SdText() => SdText(node.data),
    SdComment() => SdComment(node.data),
    SdCData() => SdCData(node.data),
    SdProcessingInstruction() => SdProcessingInstruction(
      node.target,
      node.data,
    ),
    SdDoctype() => SdDoctype(
      node.name,
      publicId: node.publicId,
      systemId: node.systemId,
      internalSubset: node.internalSubset,
    ),
    SdElement() => SdElement(
      node.name,
      namespaceDeclarations: Map.of(node.namespaceDeclarations),
      attributes: Map.of(node.attributes),
      children: [for (final child in node.children) cloneNode(child)],
    ),
  };
}
