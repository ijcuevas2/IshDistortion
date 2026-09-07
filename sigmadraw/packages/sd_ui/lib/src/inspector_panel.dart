import 'package:flutter/material.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';

/// The property inspector (§10): the selected block's type, editable
/// label, editable parameters (typed by the stencil's [ParamField] schema
/// when [registry] knows the type, else a generic editor keyed off the
/// runtime type of each `sd:params` value), and a read-only port table.
/// Style/transform fields (also called for in §10) land alongside the
/// transform-handle UI in a later pass.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    super.key,
    required this.selection,
    this.registry,
    this.undoStack,
  });

  final SelectionModel selection;
  final StencilRegistry? registry;

  /// Routes label/parameter edits through this stack instead of mutating
  /// directly, so they become undoable — share the same instance passed to
  /// e.g. `SigmaCanvas`/`StencilCanvasArea`. `null` (the default) preserves
  /// this widget's original direct-mutation behavior.
  final UndoStack? undoStack;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() => setState(() {});

  void _setBlockLabel(SdElement element, String? value) {
    final undoStack = widget.undoStack;
    if (undoStack == null) {
      setState(() => element.blockLabel = value);
      return;
    }
    final oldValue = element.blockLabel;
    setState(
      () => undoStack.execute(
        CallbackCommand(
          apply: () => element.blockLabel = value,
          unapply: () => element.blockLabel = oldValue,
          description: 'Change label',
        ),
      ),
    );
  }

  void _setBlockParams(SdElement element, Map<String, Object?> value) {
    final undoStack = widget.undoStack;
    if (undoStack == null) {
      setState(() => element.blockParams = value);
      return;
    }
    final oldValue = element.blockParams;
    setState(
      () => undoStack.execute(
        CallbackCommand(
          apply: () => element.blockParams = value,
          unapply: () => element.blockParams = oldValue,
          description: 'Change parameter',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selection.selected;
    if (selected.length != 1) {
      return Center(
        child: Text(
          selected.isEmpty
              ? 'Nothing selected'
              : '${selected.length} elements selected',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final element = selected.single;
    final blockType = element.blockType;
    if (blockType == null) {
      return Center(
        child: Text(
          '<${element.name.local}> (not a block)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final stencil = widget.registry?.byId(blockType);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          stencil?.displayName ?? blockType,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _LabeledField(
          key: ValueKey('${element.blockId}-label'),
          label: 'Label',
          initialValue: element.blockLabel ?? '',
          onChanged: (v) => _setBlockLabel(element, v.isEmpty ? null : v),
        ),
        const SizedBox(height: 16),
        Text('Parameters', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        for (final entry in element.blockParams.entries)
          _ParamField(
            key: ValueKey('${element.blockId}-${entry.key}'),
            paramKey: entry.key,
            value: entry.value,
            onChanged: (v) {
              final params = Map<String, Object?>.of(element.blockParams);
              params[entry.key] = v;
              _setBlockParams(element, params);
            },
          ),
        const SizedBox(height: 16),
        Text('Ports', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        for (final port in element.blockPorts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${port['id']}   ${port['dir']}   ${port['dtype']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

/// One editable row for an `sd:params` entry, typed by the runtime type of
/// [value]: `bool` -> switch, `num` -> a numeric field (preserving
/// int-vs-double), `String` -> a text field. Anything else (nested
/// `List`/`Map`, e.g. the adder's `signs`) is shown read-only — editing
/// those needs a structured editor this phase doesn't build yet.
class _ParamField extends StatelessWidget {
  const _ParamField({
    super.key,
    required this.paramKey,
    required this.value,
    required this.onChanged,
  });

  final String paramKey;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(paramKey),
        value: v,
        onChanged: onChanged,
      );
    }
    if (v is num) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: '$v',
          decoration: InputDecoration(
            labelText: paramKey,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onChanged: (text) {
            final parsed = v is int
                ? int.tryParse(text)
                : double.tryParse(text);
            if (parsed != null) onChanged(parsed);
          },
        ),
      );
    }
    if (v is String) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: v,
          decoration: InputDecoration(
            labelText: paramKey,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$paramKey: $v',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
