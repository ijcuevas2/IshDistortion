import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';

import 'document_listenable.dart';

/// The hierarchical element tree (§10): each row shows a type icon, the
/// human-readable `sd:type` (via [registry], when known), `sd:label`, and
/// a port-count badge; selection syncs with the canvas via [selection].
/// Validation badges (also called for in §10) land in Phase 4 once
/// `sd_graph` exists to validate against.
class ElementTree extends StatefulWidget {
  const ElementTree({
    super.key,
    required this.document,
    required this.selection,
    this.registry,
  });

  final SdDocument document;
  final SelectionModel selection;
  final StencilRegistry? registry;

  @override
  State<ElementTree> createState() => _ElementTreeState();
}

class _ElementTreeState extends State<ElementTree> {
  late final DocumentListenable _documentListenable;

  @override
  void initState() {
    super.initState();
    _documentListenable = DocumentListenable(widget.document);
  }

  @override
  void dispose() {
    _documentListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_documentListenable, widget.selection]),
      builder: (context, _) {
        final rows = <Widget>[];
        void visit(SdElement element, int depth) {
          rows.add(
            _ElementRow(
              element: element,
              depth: depth,
              selected: widget.selection.isSelected(element),
              displayName: _displayNameFor(element, widget.registry),
              onTap: () => widget.selection.selectOnly(element),
            ),
          );
          for (final child in element.childElements) {
            visit(child, depth + 1);
          }
        }

        visit(widget.document.root, 0);
        return ListView(children: rows);
      },
    );
  }
}

String _displayNameFor(SdElement element, StencilRegistry? registry) {
  final blockType = element.blockType;
  if (blockType == null) return element.name.local;
  final stencilName =
      registry?.byId(blockType)?.displayName ?? _humanize(blockType);
  final label = element.blockLabel;
  return label == null || label.isEmpty ? stencilName : '$stencilName "$label"';
}

/// Falls back to turning e.g. `"pickoff-node"` into `"Pickoff Node"` when
/// [registry] doesn't know the type (a custom or not-yet-cataloged one).
String _humanize(String stencilId) => stencilId
    .split('-')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

class _ElementRow extends StatelessWidget {
  const _ElementRow({
    required this.element,
    required this.depth,
    required this.selected,
    required this.displayName,
    required this.onTap,
  });

  final SdElement element;
  final int depth;
  final bool selected;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBlock = element.blockType != null;
    final ports = element.blockPorts;
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 8 + depth * 16,
            top: 4,
            bottom: 4,
            right: 8,
          ),
          child: Row(
            children: [
              Icon(
                isBlock ? Icons.category_outlined : Icons.data_object,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(displayName, overflow: TextOverflow.ellipsis),
              ),
              if (ports.isNotEmpty)
                Text(
                  '${ports.length}p',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
