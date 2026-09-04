/// Generic command pattern, undo/redo, and transactional grouping (§2/§12)
/// for `SdDocument` edits.
///
/// Not owned by any one phase — needed by whichever UI actually mutates a
/// document (so far: `sd_render`'s canvas drags/connector creation,
/// `sd_ui`'s inspector edits and palette drop-to-place). See [UndoStack]
/// for the transaction model and [SdCommand] for the reversible-edit
/// contract every concrete command implements.
library;

export 'src/command.dart';
export 'src/document_commands.dart';
export 'src/undo_stack.dart';
