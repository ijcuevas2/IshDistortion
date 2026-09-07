import 'package:meta/meta.dart';

import 'namespaces.dart';

/// A namespace-qualified name: a local name plus an optional *resolved*
/// namespace URI.
///
/// Two [SdQName]s are equal iff their local name and resolved namespace URI
/// match — the source prefix is irrelevant to identity, exactly as the XML
/// Namespaces spec defines equivalence. (The prefix actually used in a file
/// is preserved separately, per element, via
/// `SdElement.namespaceDeclarations` — see `document_tree.dart`.)
///
/// `namespaceUri == null` means "no namespace", which for an *attribute* is
/// also what an unprefixed name means (unlike elements, unprefixed
/// attributes are never in the default namespace — see the XML Namespaces
/// spec, and `xml_codec.dart` for where this distinction is applied).
@immutable
class SdQName {
  const SdQName(this.local, [this.namespaceUri]);

  /// A name in SigmaDraw's private namespace, e.g. `SdQName.sd('type')` for
  /// the `sd:type` attribute.
  factory SdQName.sd(String local) => SdQName(local, SdNamespace.sd);

  final String local;
  final String? namespaceUri;

  @override
  bool operator ==(Object other) =>
      other is SdQName &&
      other.local == local &&
      other.namespaceUri == namespaceUri;

  @override
  int get hashCode => Object.hash(local, namespaceUri);

  @override
  String toString() => namespaceUri == null ? local : '{$namespaceUri}$local';
}
