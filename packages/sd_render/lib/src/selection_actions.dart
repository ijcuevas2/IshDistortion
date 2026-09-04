import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:vector_math/vector_math_64.dart';

import 'geometry/svg_transform.dart';
import 'selection/selection_model.dart';

/// Deletes every currently selected element (§10's Home-tab "Clipboard"
/// group's Delete, and the Delete/Backspace key) as a single undo step
/// even when several are selected, via a transaction. Also deletes every
/// edge attached to a deleted *block* (matched by `sd:from`/`sd:to`
/// referencing its id) so deleting a block doesn't leave dangling wires
/// behind — `sd_graph`'s validation would just report those as a
/// separate problem otherwise, which is a safety net, not a substitute
/// for doing the obviously-expected thing here. Clears the selection
/// afterward (there's nothing left to keep selected). A no-op if nothing
/// is selected, or if everything selected has already been detached some
/// other way.
void deleteSelection(
  SelectionModel selection,
  SdDocument document, {
  UndoStack? undoStack,
}) {
  final directTargets = selection.selected.where((e) => e.parent != null);
  final blockIds = directTargets
      .map((e) => e.blockId)
      .whereType<String>()
      .toSet();
  final cascadedEdges = blockIds.isEmpty
      ? const <SdElement>[]
      : document.root.descendantElements.where((e) {
          final from = e.edgeFrom?.split(':').firstOrNull;
          final to = e.edgeTo?.split(':').firstOrNull;
          return (from != null && blockIds.contains(from)) ||
              (to != null && blockIds.contains(to));
        });

  final targets = {
    ...directTargets,
    ...cascadedEdges,
  }.where((e) => e.parent != null).toList();
  if (targets.isEmpty) return;

  if (undoStack == null) {
    for (final e in targets) {
      e.detach();
    }
  } else {
    undoStack.beginTransaction();
    for (final e in targets) {
      undoStack.execute(RemoveChildCommand(e));
    }
    undoStack.commitTransaction(
      description: targets.length == 1
          ? 'Delete'
          : 'Delete ${targets.length} elements',
    );
  }
  selection.clear();
}

/// A tiny in-memory clipboard for copy/paste (§10's Home-tab "Clipboard"
/// group) — holds detached clones of the last-copied elements. Nothing
/// persists across app restarts or reaches the OS clipboard (that would
/// need serializing to real SVG text on copy and parsing it back on
/// paste — not built).
///
/// Edge connectivity *between* copied elements isn't preserved or
/// remapped: pasting two blocks that were wired to each other won't
/// recreate that wire between the pasted copies. That's a deliberate
/// scope cut, not an oversight — the overwhelmingly common case (copy
/// one block, paste a duplicate of it) doesn't need it, and correctly
/// remapping arbitrary internal wiring for a copied sub-circuit is a
/// meaningfully bigger feature.
class SdClipboard {
  List<SdElement> _contents = const [];

  bool get isEmpty => _contents.isEmpty;

  /// Snapshots [elements] as detached clones, replacing whatever was
  /// copied before.
  void copy(Iterable<SdElement> elements) {
    _contents = [for (final e in elements) cloneNode(e) as SdElement];
  }

  /// Clones the clipboard contents again (so pasting more than once
  /// never reuses the same node instances — each paste is independent),
  /// mints a fresh `sd:id`/`sd:edge` for each pasted block/edge so it
  /// can't collide with one already in [document], and offsets each by
  /// ([dx], [dy]) in document space so a paste doesn't land exactly on
  /// top of what was copied.
  List<SdElement> pasteInto(
    SdDocument document, {
    double dx = 20,
    double dy = 20,
  }) {
    final existingBlockIds = document.root.descendantElements
        .map((e) => e.blockId)
        .whereType<String>()
        .toSet();
    final existingEdgeIds = document.root.descendantElements
        .map((e) => e.edgeId)
        .whereType<String>()
        .toSet();

    final pasted = <SdElement>[];
    for (final original in _contents) {
      final clone = cloneNode(original) as SdElement;
      final blockId = clone.blockId;
      if (blockId != null) {
        clone.blockId = _freshId(blockId, existingBlockIds);
      }
      final edgeId = clone.edgeId;
      if (edgeId != null) {
        clone.edgeId = _freshId(edgeId, existingEdgeIds);
      }
      applyWorldDelta(clone, Matrix4.translationValues(dx, dy, 0));
      pasted.add(clone);
    }
    return pasted;
  }
}

String _freshId(String base, Set<String> alreadyMinted) {
  if (alreadyMinted.add(base)) return base;
  var n = 2;
  while (!alreadyMinted.add('$base-copy$n')) {
    n++;
  }
  return '$base-copy$n';
}

/// Copies every currently selected element to [clipboard] (§10's
/// Home-tab "Clipboard" group's Copy). A no-op if nothing is selected —
/// deliberately does *not* clear an existing clipboard in that case,
/// matching how every ordinary clipboard behaves (an accidental
/// click-on-empty-space + Ctrl+C shouldn't wipe out a real copy from a
/// moment earlier).
void copySelectionToClipboard(SdClipboard clipboard, SelectionModel selection) {
  if (selection.isEmpty) return;
  clipboard.copy(selection.selected);
}

/// Pastes [clipboard]'s contents into [document] as a single undo step,
/// then selects the newly-pasted elements (so an immediate drag can
/// reposition them, mirroring what dropping a new stencil from the
/// palette already does). A no-op if the clipboard is empty.
void pasteFromClipboard(
  SdClipboard clipboard,
  SdDocument document,
  SelectionModel selection, {
  UndoStack? undoStack,
}) {
  if (clipboard.isEmpty) return;
  final pasted = clipboard.pasteInto(document);
  if (undoStack == null) {
    for (final e in pasted) {
      document.root.appendChild(e);
    }
  } else {
    undoStack.beginTransaction();
    for (final e in pasted) {
      undoStack.execute(InsertChildCommand(document.root, e));
    }
    undoStack.commitTransaction(
      description: pasted.length == 1
          ? 'Paste'
          : 'Paste ${pasted.length} elements',
    );
  }
  selection.selectAll(pasted);
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
