import 'package:xml/xml.dart' as xml;

import 'document_tree.dart';
import 'namespaces.dart';
import 'qname.dart';
import 'save_mode.dart';

/// Namespaces that "Export Plain SVG" strips — see [SdSaveMode.plain].
/// `sd:` is always stripped; this is a `Set` (rather than a hard-coded
/// single check) so a later phase can register another editor-only
/// namespace without touching the write path.
const Set<String> editorOnlyNamespaces = {SdNamespace.sd};

/// Parses [source] (an SVG document, or any well-formed XML) into an
/// [SdDocument].
///
/// Every element, attribute, namespace declaration, comment, CDATA section,
/// processing instruction, and text node is preserved, including foreign
/// (non-SVG, non-`sd:`) content — per §3 ("preserve all unknown foreign
/// attributes/elements so third-party edits round-trip") and §15 ("do not
/// drop unknown/foreign SVG content on load"). Pair with [writeSdDocument]
/// for the round-trip.
///
/// Throws [xml.XmlException] on malformed XML, or [FormatException] if the
/// document has no root element.
SdDocument parseSdDocument(String source) {
  final parsed = xml.XmlDocument.parse(source);

  String? version;
  String? encoding;
  bool? standalone;
  for (final declaration in parsed.children.whereType<xml.XmlDeclaration>()) {
    version = declaration.version;
    encoding = declaration.encoding;
    // Not `declaration.standalone`: that getter defaults to `false` when
    // the attribute is simply absent, which would fabricate a
    // `standalone="no"` on write. Read the raw attribute so "absent"
    // round-trips as `null`, not `false`.
    final rawStandalone = declaration.getAttribute('standalone');
    standalone = rawStandalone == null ? null : rawStandalone == 'yes';
  }

  final prolog = <SdNode>[];
  final epilog = <SdNode>[];
  xml.XmlElement? rootXml;
  for (final child in parsed.children) {
    if (child is xml.XmlDeclaration) continue;
    if (child is xml.XmlElement) {
      rootXml = child;
      continue;
    }
    final node = _parseMisc(child);
    if (node == null) continue;
    (rootXml == null ? prolog : epilog).add(node);
  }
  if (rootXml == null) {
    throw const FormatException('Document has no root element.');
  }

  // `xml:` is implicitly bound by the XML spec itself, with no explicit
  // declaration required anywhere in the source.
  const rootScope = _NsScope({'xml': SdNamespace.xml});
  return SdDocument(
    root: _parseElement(rootXml, rootScope),
    xmlVersion: version,
    xmlEncoding: encoding,
    xmlStandalone: standalone,
    prolog: prolog,
    epilog: epilog,
  );
}

/// Serializes [document] back to an XML string. In [SdSaveMode.native]
/// (the default) every `sd:*` attribute round-trips; in [SdSaveMode.plain]
/// they — and any other [editorOnlyNamespaces] — are omitted, per §3's
/// "native save keeps `sd:`; Export Plain SVG strips `sd:`" and matching
/// Inkscape's own Plain SVG export.
///
/// Pretty-printed with a stable 2-space indent for readable diffs; any
/// element containing non-whitespace text (e.g. an SVG `<text>` label) is
/// left untouched rather than re-indented, so meaningful text content is
/// never disturbed.
String writeSdDocument(
  SdDocument document, {
  SdSaveMode mode = SdSaveMode.native,
}) {
  final children = <xml.XmlNode>[];

  if (document.xmlVersion != null || document.xmlEncoding != null) {
    children.add(
      xml.XmlDeclaration([
        if (document.xmlVersion != null)
          xml.XmlAttribute(
            const xml.XmlName.qualified('version'),
            document.xmlVersion!,
          ),
        if (document.xmlEncoding != null)
          xml.XmlAttribute(
            const xml.XmlName.qualified('encoding'),
            document.xmlEncoding!,
          ),
        if (document.xmlStandalone != null)
          xml.XmlAttribute(
            const xml.XmlName.qualified('standalone'),
            document.xmlStandalone! ? 'yes' : 'no',
          ),
      ]),
    );
  }

  for (final node in document.prolog) {
    final converted = _writeMisc(node);
    if (converted != null) children.add(converted);
  }

  const rootScope = _WriteScope({'xml': SdNamespace.xml});
  final rootXml = _writeElement(document.root, mode, rootScope);
  if (rootXml == null) {
    throw StateError(
      'Save mode $mode stripped the root element itself — the root must '
      'not be in a namespace registered in editorOnlyNamespaces.',
    );
  }
  children.add(rootXml);

  for (final node in document.epilog) {
    final converted = _writeMisc(node);
    if (converted != null) children.add(converted);
  }

  final buffer = xml.XmlDocument(children).toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: _hasSignificantText,
  );
  return '$buffer\n';
}

bool _hasSignificantText(xml.XmlNode node) =>
    node is xml.XmlElement &&
    node.children.any((c) => c is xml.XmlText && c.value.trim().isNotEmpty);

// --- parsing -----------------------------------------------------------

/// Prefixes bound in scope at some point in the tree, `null` key = default
/// namespace. Immutable; [extend] returns a new scope for one element's
/// worth of additional declarations, so siblings don't see each other's
/// bindings — exactly XML's actual scoping rule.
class _NsScope {
  const _NsScope(this._uriByPrefix);

  final Map<String?, String> _uriByPrefix;

  String? uriFor(String? prefix) => _uriByPrefix[prefix];

  _NsScope extend(Map<String?, String> declared) =>
      declared.isEmpty ? this : _NsScope({..._uriByPrefix, ...declared});
}

SdElement _parseElement(xml.XmlElement element, _NsScope parentScope) {
  final declared = <String?, String>{};
  for (final attr in element.attributes) {
    final prefix = attr.name.prefix;
    final local = attr.name.local;
    if (prefix == 'xmlns') {
      declared[local] = attr.value;
    } else if (prefix == null && local == 'xmlns') {
      declared[null] = attr.value;
    }
  }
  final scope = parentScope.extend(declared);

  // Unlike attributes, an *unprefixed element* does inherit the default
  // namespace.
  final elementUri = scope.uriFor(element.name.prefix);
  final name = SdQName(element.name.local, elementUri);

  final attributes = <SdQName, String>{};
  for (final attr in element.attributes) {
    final prefix = attr.name.prefix;
    final local = attr.name.local;
    if (prefix == 'xmlns' || (prefix == null && local == 'xmlns')) {
      continue; // Namespace declarations, not data — captured above.
    }
    // An unprefixed attribute is never in any namespace, not even the
    // default one in scope (XML Namespaces spec).
    final uri = prefix == null ? null : scope.uriFor(prefix);
    attributes[SdQName(local, uri)] = attr.value;
  }

  final children = <SdNode>[];
  for (final child in element.children) {
    final node = child is xml.XmlElement
        ? _parseElement(child, scope)
        : _parseMisc(child);
    if (node != null) children.add(node);
  }

  return SdElement(
    name,
    namespaceDeclarations: declared,
    attributes: attributes,
    children: children,
  );
}

SdNode? _parseMisc(xml.XmlNode node) => switch (node) {
  xml.XmlText() => SdText(node.value),
  xml.XmlComment() => SdComment(node.value),
  xml.XmlCDATA() => SdCData(node.value),
  xml.XmlProcessing() => SdProcessingInstruction(node.target, node.value),
  xml.XmlDoctype() => SdDoctype(
    node.name,
    publicId: node.externalId?.publicId,
    systemId: node.externalId?.systemId,
    internalSubset: node.internalSubset,
  ),
  _ => null,
};

// --- writing -------------------------------------------------------------

/// Mirror of [_NsScope] for the write side: given a namespace URI, find (or
/// mint) the prefix that should represent it at this point in the tree.
class _WriteScope {
  const _WriteScope(this._uriByPrefix);

  final Map<String?, String> _uriByPrefix;

  bool isPrefixBound(String prefix) => _uriByPrefix.containsKey(prefix);

  /// A prefix already bound to [uri], preferring a real prefix over the
  /// default namespace; `''` means only the *default* namespace is bound
  /// to it; `null` means nothing in scope is bound to it at all.
  String? prefixFor(String uri) {
    String? defaultMatch;
    for (final entry in _uriByPrefix.entries) {
      if (entry.value != uri) continue;
      if (entry.key == null) {
        defaultMatch = '';
      } else {
        return entry.key;
      }
    }
    return defaultMatch;
  }

  _WriteScope extend(Map<String?, String> declared) =>
      declared.isEmpty ? this : _WriteScope({..._uriByPrefix, ...declared});
}

String _mintPrefix(_WriteScope scope, String uri) {
  final base = switch (uri) {
    SdNamespace.sd => SdPrefix.sd,
    SdNamespace.inkscape => SdPrefix.inkscape,
    SdNamespace.xlink => SdPrefix.xlink,
    _ => 'ns',
  };
  if (!scope.isPrefixBound(base)) return base;
  var i = 2;
  while (scope.isPrefixBound('$base$i')) {
    i++;
  }
  return '$base$i';
}

/// Converts one element (and its subtree) for writing, or returns `null` if
/// [mode] strips it (its own tag is in an [editorOnlyNamespaces] entry).
xml.XmlElement? _writeElement(
  SdElement element,
  SdSaveMode mode,
  _WriteScope parentScope,
) {
  if (mode == SdSaveMode.plain &&
      element.name.namespaceUri != null &&
      editorOnlyNamespaces.contains(element.name.namespaceUri)) {
    return null;
  }

  final declarations = <String?, String>{
    for (final entry in element.namespaceDeclarations.entries)
      if (mode != SdSaveMode.plain ||
          !editorOnlyNamespaces.contains(entry.value))
        entry.key: entry.value,
  };
  var scope = parentScope.extend(declarations);

  String? elementPrefix;
  final elementUri = element.name.namespaceUri;
  if (elementUri != null) {
    final existing = scope.prefixFor(elementUri);
    if (existing != null) {
      elementPrefix = existing.isEmpty ? null : existing;
    } else {
      elementPrefix = _mintPrefix(scope, elementUri);
      declarations[elementPrefix] = elementUri;
      scope = scope.extend({elementPrefix: elementUri});
    }
  }

  final xmlAttributes = <xml.XmlAttribute>[
    for (final entry in declarations.entries)
      xml.XmlAttribute(
        entry.key == null
            ? const xml.XmlName.qualified('xmlns')
            : xml.XmlName.parts(entry.key!, prefix: 'xmlns'),
        entry.value,
      ),
  ];

  for (final entry in element.attributes.entries) {
    final qname = entry.key;
    if (mode == SdSaveMode.plain &&
        qname.namespaceUri != null &&
        editorOnlyNamespaces.contains(qname.namespaceUri)) {
      continue;
    }
    String? attrPrefix;
    final attrUri = qname.namespaceUri;
    if (attrUri != null) {
      final existing = scope.prefixFor(attrUri);
      if (existing != null && existing.isNotEmpty) {
        attrPrefix = existing;
      } else {
        // Attributes are never in the default namespace, even if `attrUri`
        // happens to be bound as default here — mint a real prefix.
        attrPrefix = _mintPrefix(scope, attrUri);
        xmlAttributes.add(
          xml.XmlAttribute(
            xml.XmlName.parts(attrPrefix, prefix: 'xmlns'),
            attrUri,
          ),
        );
        scope = scope.extend({attrPrefix: attrUri});
      }
    }
    xmlAttributes.add(
      xml.XmlAttribute(
        xml.XmlName.parts(qname.local, prefix: attrPrefix),
        entry.value,
      ),
    );
  }

  final xmlChildren = <xml.XmlNode>[];
  for (final child in element.children) {
    final converted = child is SdElement
        ? _writeElement(child, mode, scope)
        : _writeMisc(child);
    if (converted != null) xmlChildren.add(converted);
  }

  return xml.XmlElement(
    xml.XmlName.parts(element.name.local, prefix: elementPrefix),
    xmlAttributes,
    xmlChildren,
  );
}

xml.XmlNode? _writeMisc(SdNode node) => switch (node) {
  SdText() => xml.XmlText(node.data),
  SdComment() => xml.XmlComment(node.data),
  SdCData() => xml.XmlCDATA(node.data),
  SdProcessingInstruction() => xml.XmlProcessing(node.target, node.data),
  // See the doc comment on SdDoctype: package:xml exposes no public way to
  // reconstruct DtdExternalId, so a re-saved doctype loses its external ID.
  SdDoctype() => xml.XmlDoctype(node.name),
  SdElement() => throw StateError('SdElement must go through _writeElement.'),
};
