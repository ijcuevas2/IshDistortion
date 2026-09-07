/// Well-known XML namespace URIs used by SigmaDraw documents.
///
/// See `sigmadraw-implementation-prompt.md` §3: the native document format
/// is plain SVG: standard elements live in [svg] (and sometimes [xlink]);
/// all SigmaDraw semantics live in the private [sd] namespace so that any
/// other SVG viewer simply ignores them.
abstract final class SdNamespace {
  static const svg = 'http://www.w3.org/2000/svg';
  static const xlink = 'http://www.w3.org/1999/xlink';
  static const xml = 'http://www.w3.org/XML/1998/namespace';

  /// Inkscape's own extension namespace. We read/write a handful of
  /// `inkscape:*` attributes (e.g. `inkscape:groupmode="layer"`) purely for
  /// compatibility with Inkscape's layer convention — see §3.
  static const inkscape = 'http://www.inkscape.org/namespaces/inkscape';

  /// SigmaDraw's private namespace for semantic/graph data.
  ///
  /// This URI is an identifier, not a dereferenceable location — nothing is
  /// ever fetched from it. Follows Inkscape's own plain-SVG + private
  /// namespace approach exactly (see docs/inkscape-notes.md, §xml).
  static const sd = 'https://sigmadraw.app/ns/dsp/1.0';
}

/// Conventional prefixes SigmaDraw uses when *authoring* a namespace
/// declaration (e.g. building a blank document from scratch).
///
/// When *reading* an existing document we never assume these — we resolve
/// and preserve whatever prefix the source file actually declared for each
/// namespace URI, exactly as Inkscape does for third-party files.
abstract final class SdPrefix {
  static const sd = 'sd';
  static const inkscape = 'inkscape';
  static const xlink = 'xlink';
}
