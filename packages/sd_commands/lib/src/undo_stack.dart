import 'command.dart';

/// Thrown by [UndoStack.beginTransaction] when one is already open — nested
/// transactions aren't supported (see the class doc comment).
class TransactionAlreadyOpenError extends StateError {
  TransactionAlreadyOpenError()
    : super('A transaction is already open; commit or roll it back first.');
}

/// Thrown by [UndoStack.commitTransaction]/[rollbackTransaction] when none
/// is open.
class NoTransactionOpenError extends StateError {
  NoTransactionOpenError() : super('No transaction is currently open.');
}

/// The undo/redo history for one document (§2/§12).
///
/// [execute] performs a command and pushes it as one undo step.
/// [beginTransaction]/[commitTransaction] group everything executed in
/// between into a *single* undo step instead (Inkscape's "event grouping" —
/// `document-undo.cpp` — is the reference this mirrors): a canvas drag, for
/// instance, opens a transaction on pointer-down, calls [execute] with a
/// fresh [SdCommand] on every pointer-move (so the document updates live,
/// every frame), and commits on pointer-up, collapsing what might have
/// been dozens of intermediate edits into the one undo step a user
/// actually expects "Undo" to reverse. [rollbackTransaction] immediately
/// un-applies everything recorded so far instead of committing — for a
/// drag cancelled outright (e.g. Escape) rather than dropped.
///
/// Only one transaction may be open at a time — not because nesting is
/// meaningless, but because nothing in this project yet needs it, and a
/// flat model is simpler to reason about and test; [beginTransaction]
/// throws [TransactionAlreadyOpenError] rather than silently misbehaving
/// if called again before a commit/rollback.
class UndoStack {
  final _undo = <SdCommand>[];
  final _redo = <SdCommand>[];
  List<SdCommand>? _openTransaction;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasOpenTransaction => _openTransaction != null;

  /// The description of the command an [undo] call would reverse, or
  /// `null` if [canUndo] is `false` — e.g. for an "Undo Move" menu label.
  String? get undoDescription => _undo.lastOrNull?.description;

  String? get redoDescription => _redo.lastOrNull?.description;

  /// Runs [command] immediately and records it. Outside a transaction,
  /// this is one undo step by itself and clears the redo stack (the usual
  /// rule: executing a new command after an undo discards the redone-away
  /// future). Inside an open transaction, it's folded into whatever
  /// [commitTransaction] eventually produces instead of becoming its own
  /// entry — the redo stack is still cleared immediately (the document
  /// has already diverged from it) even though the *undo* stack doesn't
  /// gain a new top-level entry until the commit.
  void execute(SdCommand command) {
    command.apply();
    _redo.clear();
    final open = _openTransaction;
    if (open != null) {
      open.add(command);
    } else {
      _undo.add(command);
    }
  }

  /// Opens a transaction: every [execute] until the matching
  /// [commitTransaction]/[rollbackTransaction] is folded into one undo
  /// step instead of many. Throws [TransactionAlreadyOpenError] if one is
  /// already open.
  void beginTransaction() {
    if (_openTransaction != null) throw TransactionAlreadyOpenError();
    _openTransaction = [];
  }

  /// Closes the open transaction and pushes everything recorded during it
  /// as a single [CompositeCommand] undo step — or pushes nothing at all
  /// if the transaction recorded zero commands (a drag that never actually
  /// moved anything shouldn't leave a no-op entry on the undo stack;
  /// Inkscape calls this same idea "maybe done"). Throws
  /// [NoTransactionOpenError] if none is open.
  void commitTransaction({String description = 'Multiple changes'}) {
    final open = _openTransaction;
    if (open == null) throw NoTransactionOpenError();
    _openTransaction = null;
    if (open.isEmpty) return;
    _undo.add(
      open.length == 1
          ? open.single
          : CompositeCommand(open, description: description),
    );
  }

  /// Closes the open transaction and immediately un-applies everything
  /// recorded during it, in reverse order, discarding it entirely rather
  /// than pushing an undo step — for a drag/edit cancelled outright.
  /// Throws [NoTransactionOpenError] if none is open.
  void rollbackTransaction() {
    final open = _openTransaction;
    if (open == null) throw NoTransactionOpenError();
    _openTransaction = null;
    for (final command in open.reversed) {
      command.unapply();
    }
  }

  /// Un-applies the most recent undo step (or the most recent one not
  /// already redone away) and moves it to the redo stack. A no-op if
  /// [canUndo] is `false`. Undoing while a transaction is open is refused
  /// ([StateError]) — the half-open transaction has to be resolved first,
  /// or "undo" would reverse an edit from *before* it, leaving the
  /// transaction's own (not yet committed) changes stranded on top.
  void undo() {
    if (_openTransaction != null) {
      throw StateError('Cannot undo while a transaction is open.');
    }
    if (_undo.isEmpty) return;
    final command = _undo.removeLast();
    command.unapply();
    _redo.add(command);
  }

  /// Re-applies the most recently undone step. A no-op if [canRedo] is
  /// `false`.
  void redo() {
    if (_openTransaction != null) {
      throw StateError('Cannot redo while a transaction is open.');
    }
    if (_redo.isEmpty) return;
    final command = _redo.removeLast();
    command.apply();
    _undo.add(command);
  }

  /// Discards all history without un-applying anything — e.g. when a
  /// document is closed/replaced, so a stale command from the old document
  /// can never be undone into the new one.
  void clear() {
    _undo.clear();
    _redo.clear();
    _openTransaction = null;
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
