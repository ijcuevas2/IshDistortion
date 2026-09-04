/// A single reversible edit (§2/§12: "command pattern, undo/redo").
///
/// Deliberately the classic Command pattern (explicit apply/unapply per
/// edit) rather than Inkscape's own approach (`document-undo.cpp`: diffing
/// the whole XML tree before/after each user action) — a real
/// tree-diffing undo system is a substantial project on its own, and an
/// explicit command per edit is simpler to reason about and test while
/// still satisfying the same user-facing contract (every edit is
/// undoable/redoable, and several edits can be grouped into one undo
/// step — see `UndoStack`'s transactions).
///
/// Implementors must capture whatever "before" state [unapply] needs
/// *before* [apply] runs — typically by reading it in their own
/// constructor — never lazily inside [unapply] itself, since by the time
/// undo runs the document no longer holds that prior state. See
/// `SetAttributeCommand` for the canonical example.
abstract class SdCommand {
  /// Performs the edit. Called once when the command is first executed via
  /// [UndoStack.execute], and again on every subsequent redo — must be
  /// safe to call more than once (idempotent from the document's
  /// perspective), since [UndoStack] never re-runs [apply] on a command it
  /// hasn't just undone.
  void apply();

  /// Exactly reverses [apply] — the document must end up bit-for-bit
  /// equivalent (per `SdNode.isEquivalentTo`) to how it looked before
  /// [apply] first ran.
  void unapply();

  /// A short, human-readable description of this edit (e.g. for an
  /// Edit-menu "Undo Move" label). Not required to be unique.
  String get description;
}

/// Bundles [commands] into a single undo/redo unit: [apply] runs them in
/// order, [unapply] reverses them in *reverse* order (so a later command
/// that depended on an earlier one's effect — e.g. inserting a node, then
/// setting an attribute on it — unwinds correctly). This is what
/// [UndoStack]'s transactions produce, and is also usable directly for a
/// single call site that always performs several edits as one logical
/// step (e.g. "delete a block and every edge attached to it").
///
/// An empty [commands] list is allowed (a no-op command) rather than
/// rejected, so a transaction that ends up recording nothing can still
/// produce a valid (if pointless) `CompositeCommand` — though
/// `UndoStack.commitTransaction` specifically avoids pushing one in that
/// case (Inkscape's own "maybe done": an empty transaction shouldn't leave
/// a no-op entry on the undo stack).
class CompositeCommand implements SdCommand {
  CompositeCommand(this.commands, {this.description = 'Multiple changes'});

  final List<SdCommand> commands;

  @override
  final String description;

  @override
  void apply() {
    for (final command in commands) {
      command.apply();
    }
  }

  @override
  void unapply() {
    for (final command in commands.reversed) {
      command.unapply();
    }
  }
}

/// Wraps two closures as an [SdCommand] — for an edit that's naturally
/// made through a typed accessor (e.g. `sd_document`'s
/// `SdBlockSemantics.blockLabel`/`blockParams`) rather than a raw
/// `SdQName` attribute, where re-deriving that accessor's own
/// null-vs-remove or JSON-encoding rules at the call site would duplicate
/// logic it already gets right. The caller is responsible for capturing
/// whatever [unapply] needs to restore — typically by reading the "old"
/// value into a local before constructing this, exactly like every other
/// [SdCommand].
class CallbackCommand implements SdCommand {
  // Can't use the `this._apply`/`this._unapply` initializing-formal
  // shorthand here: that would force the named-parameter labels
  // themselves to be `_apply`/`_unapply` (private-prefixed, an unpleasant
  // call site), and the public names `apply`/`unapply` can't be the
  // *field* names either — they'd collide with the `apply()`/`unapply()`
  // methods `SdCommand` requires this class to also declare.
  const CallbackCommand({
    required void Function() apply,
    required void Function() unapply,
    this.description = 'Change',
  }) : _apply = apply, // ignore: prefer_initializing_formals
       _unapply = unapply; // ignore: prefer_initializing_formals

  final void Function() _apply;
  final void Function() _unapply;

  @override
  final String description;

  @override
  void apply() => _apply();

  @override
  void unapply() => _unapply();
}
