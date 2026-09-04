/// Which attributes/elements a write keeps — see §3, "Two save modes".
enum SdSaveMode {
  /// Native SigmaDraw save: keeps every `sd:*` attribute/element, so the
  /// file reopens in SigmaDraw with full semantics restored.
  native,

  /// "Export Plain SVG": strips `sd:*` (and any other namespace registered
  /// as editor-only) so the output renders identically everywhere but
  /// carries no SigmaDraw-specific data — mirrors Inkscape's own
  /// "Plain SVG" export.
  plain,
}
