import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'qname.dart';

/// A dependency-free observable, shape-compatible with Flutter's
/// `Listenable`/`ChangeNotifier` (same `addListener` / `removeListener` /
/// `notifyListeners` methods).
///
/// `sd_document` is a pure-Dart package — no Flutter SDK dependency — so it
/// cannot use `package:flutter/foundation.dart`'s `ChangeNotifier` directly
/// (see `sigmadraw-implementation-prompt.md` §2, "feed a Listenable to
/// `CustomPainter.repaint`"). Because the method names match exactly,
/// `sd_render` can trivially bridge one of these to a real
/// `Listenable`/`ChangeNotifier` — e.g. a Flutter `ChangeNotifier` whose
/// constructor does `sdDocument.changes.addListener(notifyListeners)` — with
/// no adapter boilerplate. This keeps the document model (and everything
/// that only needs to read or mutate it, e.g. off the UI isolate) free of
/// the Flutter engine, which matters for fast `dart test` runs and for
/// running SVG parse/serialize work in a plain `Isolate.run`.
class SdChangeNotifier {
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  @protected
  void notifyListeners() {
    // Snapshot first: a listener may add/remove listeners while iterating.
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void dispose() => _listeners.clear();
}

/// Base type for every node in a SigmaDraw document tree.
///
/// This tree is the single source of truth (mirrors Inkscape's `XML::Node`
/// tree — see docs/inkscape-notes.md, §xml). It is *not* itself the parsed
/// `package:xml` tree: `xml_codec.dart` uses `package:xml` purely as the
/// parser/serializer and converts to/from this model, which additionally
/// tracks parent/document links and fires change notifications so higher
/// layers (a future `sd_commands` undo stack, `sd_render`'s repaint
/// scheduling) can observe mutations without diffing the whole tree.
sealed class SdNode {
  SdElement? _parent;

  /// The parent element, or `null` if this node is a document root or is
  /// currently detached (e.g. mid-move, or held by an undo command —
  /// mirrors Inkscape's Repr attach/release lifecycle).
  SdElement? get parent => _parent;

  SdDocument? _ownerDocument;

  /// The document this node is currently attached to, or `null` if
  /// detached. Resolved by walking up to whichever ancestor (typically the
  /// root) is registered as a document's root.
  SdDocument? get document => _ownerDocument ?? _parent?.document;

  /// Detaches this node from its parent, if any. A no-op if already
  /// detached.
  void detach() => _parent?.removeChild(this);

  void _notifyChanged() => document?._changes.notifyListeners();

  /// Deep structural equivalence: same content and, for elements, same
  /// attributes/namespace declarations/children (children order matters;
  /// attribute and namespace-declaration order does not). Parent/document
  /// links are ignored. This is the round-trip oracle used by
  /// `test/svg_round_trip_test.dart` — *not* an `==` override, since these
  /// are mutable, reference-identity objects (e.g. usable as `Set`/`Map`
  /// keys during editing) like Inkscape's own Repr nodes.
  bool isEquivalentTo(SdNode other);
}

/// A text content node, e.g. the `Hello` in `<text>Hello</text>`.
final class SdText extends SdNode {
  SdText(this.data);

  String data;

  @override
  bool isEquivalentTo(SdNode other) => other is SdText && other.data == data;

  @override
  String toString() => 'SdText(${_ellipsize(data)})';
}

/// An XML comment, e.g. `<!-- Created with SigmaDraw -->`.
final class SdComment extends SdNode {
  SdComment(this.data);

  String data;

  @override
  bool isEquivalentTo(SdNode other) => other is SdComment && other.data == data;

  @override
  String toString() => 'SdComment(${_ellipsize(data)})';
}

/// A CDATA section, e.g. embedded raw text inside `<style><![CDATA[...]]>`.
final class SdCData extends SdNode {
  SdCData(this.data);

  String data;

  @override
  bool isEquivalentTo(SdNode other) => other is SdCData && other.data == data;

  @override
  String toString() => 'SdCData(${_ellipsize(data)})';
}

/// A processing instruction, e.g. `<?xml-stylesheet ...?>`.
final class SdProcessingInstruction extends SdNode {
  SdProcessingInstruction(this.target, this.data);

  String target;
  String data;

  @override
  bool isEquivalentTo(SdNode other) =>
      other is SdProcessingInstruction &&
      other.target == target &&
      other.data == data;

  @override
  String toString() => 'SdProcessingInstruction($target, ${_ellipsize(data)})';
}

/// A document type declaration, e.g.
/// `<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "...">`. Vanishingly rare
/// in modern SVG. [publicId]/[systemId]/[internalSubset] are captured on
/// parse for introspection, but `package:xml` does not expose a public API
/// to reconstruct its `DtdExternalId` type, so `xml_codec.dart` can only
/// re-emit a bare `<!DOCTYPE name>` on write — a documented, deliberately
/// accepted gap (real SigmaDraw documents never author a DOCTYPE; this only
/// affects re-saving a handful of legacy third-party files that both carry
/// one *and* reference an external subset).
final class SdDoctype extends SdNode {
  SdDoctype(this.name, {this.publicId, this.systemId, this.internalSubset});

  String name;
  String? publicId;
  String? systemId;
  String? internalSubset;

  @override
  bool isEquivalentTo(SdNode other) =>
      other is SdDoctype &&
      other.name == name &&
      other.publicId == publicId &&
      other.systemId == systemId &&
      other.internalSubset == internalSubset;

  @override
  String toString() => 'SdDoctype($name)';
}

const _mapEquality = MapEquality<Object?, String>();

/// `ListEquality`'s default element comparison is `==` — which, for
/// [SdNode], is reference identity (deliberately not overridden; see the
/// doc comment on [SdNode.isEquivalentTo]). This bridges it to
/// [SdNode.isEquivalentTo] instead, so two *different* node instances with
/// equivalent content compare equal in a list. `hash` is intentionally
/// trivial (never used: nothing here puts nodes in a `Set`/`Map` keyed by
/// this equality — [ListEquality.equals] only ever calls [equals]).
class _NodeEquivalence implements Equality<SdNode> {
  const _NodeEquivalence();

  @override
  bool equals(SdNode e1, SdNode e2) => e1.isEquivalentTo(e2);

  @override
  int hash(SdNode e) => 0;

  @override
  bool isValidKey(Object? o) => o is SdNode;
}

const _listEquality = ListEquality<SdNode>(_NodeEquivalence());

/// Whitespace-only text (e.g. the indentation `writeSdDocument`'s pretty
/// printer introduces between siblings) carries no meaning — two documents
/// that differ only in *how* they're indented are still equivalent. Used to
/// filter node lists before comparing them in [SdNode.isEquivalentTo], so a
/// document with no prolog is still equivalent to one reparsed from output
/// that happens to have a formatting newline before the root element.
/// Meaningful text (anything with a non-whitespace character) is still
/// compared exactly.
bool _isSignificant(SdNode node) =>
    node is! SdText || node.data.trim().isNotEmpty;

/// An XML element: a tag name, its namespace declarations, its attributes,
/// and its children (which may be further elements, text, comments, ...).
///
/// This is the workhorse of the document tree: every SVG shape, group, and
/// SigmaDraw semantic payload (`sd:type`, `sd:edge`, `sd:stroke`, ...) is
/// carried on an [SdElement] — see `semantics/*.dart` for typed accessors
/// over the private `sd:` namespace, and §3 of the implementation brief for
/// the attribute vocabulary.
final class SdElement extends SdNode {
  SdElement(
    this.name, {
    Map<String?, String>? namespaceDeclarations,
    Map<SdQName, String>? attributes,
    List<SdNode> children = const [],
  }) : namespaceDeclarations = LinkedHashMap.of(namespaceDeclarations ?? {}),
       _attributes = LinkedHashMap.of(attributes ?? {}) {
    for (final child in children) {
      appendChild(child);
    }
  }

  /// The element's qualified name (e.g. `SdQName('g')` for a plain SVG
  /// group, or `SdQName('edge', SdNamespace.sd)` for `<sd:edge>`).
  SdQName name;

  /// Namespace declarations (`xmlns` / `xmlns:*`) carried by *this exact*
  /// element in the source, keyed by prefix (`null` key = default
  /// namespace, i.e. a bare `xmlns="..."`). Order is preserved for
  /// round-tripping; these are surfaced separately from [attributes]
  /// because, per the XML Namespaces spec, they are not themselves
  /// namespace-qualified attributes.
  final LinkedHashMap<String?, String> namespaceDeclarations;

  final LinkedHashMap<SdQName, String> _attributes;

  /// This element's non-namespace-declaration attributes, in source order.
  /// Mutate via [setAttribute] / [removeAttribute], not this view.
  Map<SdQName, String> get attributes => UnmodifiableMapView(_attributes);

  final _children = <SdNode>[];

  /// This element's children, in document order. Mutate via [appendChild],
  /// [insertChildAt], or [removeChild], not this view.
  List<SdNode> get children => UnmodifiableListView(_children);

  /// The subset of [children] that are themselves elements.
  Iterable<SdElement> get childElements => _children.whereType<SdElement>();

  /// Every element in this element's subtree, in document (depth-first,
  /// pre-order) order — not including this element itself. Used by
  /// `sd_graph` (a later phase) to find every block/edge by scanning for
  /// `sd:type` / `sd:edge`, and by the tests here as a lookup helper.
  Iterable<SdElement> get descendantElements sync* {
    for (final child in childElements) {
      yield child;
      yield* child.descendantElements;
    }
  }

  String? getAttribute(SdQName name) => _attributes[name];

  bool hasAttribute(SdQName name) => _attributes.containsKey(name);

  void setAttribute(SdQName name, String value) {
    _attributes[name] = value;
    _notifyChanged();
  }

  void removeAttribute(SdQName name) {
    if (_attributes.remove(name) != null) {
      _notifyChanged();
    }
  }

  void appendChild(SdNode child) => insertChildAt(_children.length, child);

  void insertChildAt(int index, SdNode child) {
    child.detach();
    _children.insert(index, child);
    child._parent = this;
    _notifyChanged();
  }

  void removeChild(SdNode child) {
    if (identical(child.parent, this) && _children.remove(child)) {
      child._parent = null;
      _notifyChanged();
    }
  }

  @override
  bool isEquivalentTo(SdNode other) =>
      other is SdElement &&
      other.name == name &&
      _mapEquality.equals(other.namespaceDeclarations, namespaceDeclarations) &&
      _mapEquality.equals(other._attributes, _attributes) &&
      _listEquality.equals(
        other._children.where(_isSignificant).toList(),
        _children.where(_isSignificant).toList(),
      );

  @override
  String toString() =>
      'SdElement($name, ${_attributes.length} attrs, '
      '${_children.length} children)';
}

/// A whole SigmaDraw/SVG document: an `<svg>` root plus whatever the XML
/// prolog/epilog carried (declaration, doctype, leading/trailing comments —
/// preserved losslessly even though SigmaDraw itself never generates most
/// of it).
///
/// Listen to [changes] to repaint/react to any edit anywhere in the tree —
/// see [SdChangeNotifier].
class SdDocument {
  SdDocument({
    required SdElement root,
    this.xmlVersion,
    this.xmlEncoding,
    this.xmlStandalone,
    List<SdNode>? prolog,
    List<SdNode>? epilog,
  }) : _root = root,
       prolog = List.of(prolog ?? const []),
       epilog = List.of(epilog ?? const []) {
    root._ownerDocument = this;
  }

  SdElement _root;

  /// The root `<svg>` element.
  SdElement get root => _root;

  set root(SdElement value) {
    _root._ownerDocument = null;
    _root = value;
    value._ownerDocument = this;
    _changes.notifyListeners();
  }

  /// From the XML declaration (`<?xml version="1.0" ...?>`), if the source
  /// had one. Preserved verbatim on round-trip; a freshly-created document
  /// has no declaration until one is set.
  String? xmlVersion;
  String? xmlEncoding;
  bool? xmlStandalone;

  /// Comments, processing instructions, or a doctype that appeared before
  /// the root element in the source. Rare in practice, but preserved for
  /// lossless round-tripping of third-party files (see §3: "preserve all
  /// unknown foreign attributes/elements").
  final List<SdNode> prolog;

  /// The same, but after the root element (rarer still).
  final List<SdNode> epilog;

  final _changes = SdChangeNotifier();

  /// Fires after any mutation anywhere in this document's tree.
  SdChangeNotifier get changes => _changes;

  /// Deep structural equivalence with [other] — see
  /// `SdNode.isEquivalentTo`. This is what the round-trip acceptance test
  /// (§13: "SVG round-trip equality (incl. foreign content)") asserts.
  bool isEquivalentTo(SdDocument other) =>
      other.xmlVersion == xmlVersion &&
      other.xmlEncoding == xmlEncoding &&
      other.xmlStandalone == xmlStandalone &&
      _listEquality.equals(
        other.prolog.where(_isSignificant).toList(),
        prolog.where(_isSignificant).toList(),
      ) &&
      _listEquality.equals(
        other.epilog.where(_isSignificant).toList(),
        epilog.where(_isSignificant).toList(),
      ) &&
      other.root.isEquivalentTo(root);

  void dispose() => _changes.dispose();
}

String _ellipsize(String s, [int max = 24]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
