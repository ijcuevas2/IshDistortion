import 'package:sd_document/sd_document.dart';

import 'command.dart';

/// Sets (or, if [newValue] is `null`, removes) one attribute on [element].
/// Captures the attribute's current value as soon as the command is
/// constructed, *not* inside [unapply] — by the time an undo runs, [apply]
/// has already overwritten it. Covers every "edit a field" mutation in
/// this project so far: an inspector label/param edit, and a canvas
/// move/scale drag's `transform` rewrite (see `sigma_canvas.dart`).
class SetAttributeCommand implements SdCommand {
  SetAttributeCommand(
    this.element,
    this.name,
    this.newValue, {
    String? description,
  }) : oldValue = element.getAttribute(name),
       description = description ?? 'Change ${name.local}';

  final SdElement element;
  final SdQName name;
  final String? oldValue;
  final String? newValue;

  @override
  final String description;

  @override
  void apply() => setOrRemoveAttribute(element, name, newValue);

  @override
  void unapply() => setOrRemoveAttribute(element, name, oldValue);
}

/// Inserts [child] into [parent] at [index] (defaulting to the end, e.g. a
/// palette drop placing a new stencil instance, or a canvas drag creating
/// a new connector edge). The exact inverse of [RemoveChildCommand].
class InsertChildCommand implements SdCommand {
  InsertChildCommand(
    this.parent,
    this.child, {
    int? index,
    this.description = 'Insert element',
  }) : index = index ?? parent.children.length;

  final SdElement parent;
  final SdNode child;
  final int index;

  @override
  final String description;

  @override
  void apply() => parent.insertChildAt(index, child);

  @override
  void unapply() => parent.removeChild(child);
}

/// Removes [child] from its current parent (captured at construction time,
/// along with its position, so [unapply] can restore it to exactly where
/// it was — not just "somewhere in the parent"). The exact inverse of
/// [InsertChildCommand].
///
/// Throws [ArgumentError] if [child] is not currently attached to a
/// parent — there is nothing meaningful to remove/restore otherwise, and
/// silently no-op-ing would leave `unapply` with no correct position to
/// restore to.
class RemoveChildCommand implements SdCommand {
  RemoveChildCommand(this.child, {this.description = 'Remove element'})
    : parent =
          child.parent ??
          (throw ArgumentError.value(
            child,
            'child',
            'has no parent to remove it from',
          )),
      index = child.parent!.children.indexOf(child);

  final SdElement parent;
  final SdNode child;
  final int index;

  @override
  final String description;

  @override
  void apply() => parent.removeChild(child);

  @override
  void unapply() => parent.insertChildAt(index, child);
}
