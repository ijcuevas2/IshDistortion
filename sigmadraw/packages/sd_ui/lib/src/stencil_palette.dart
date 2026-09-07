import 'package:flutter/material.dart';
import 'package:sd_stencils/sd_stencils.dart';

/// The searchable, categorized stencil palette (§10): drag a [_PaletteItem]
/// onto `SigmaCanvas` (via a `DragTarget<StencilDefinition>` — see
/// `stencil_canvas_area.dart`) to place it. Custom-symbol creation/reuse
/// (also called for in §5) is not implemented yet — this only surfaces the
/// built-in catalog.
class StencilPalette extends StatefulWidget {
  const StencilPalette({super.key, required this.registry});

  final StencilRegistry registry;

  @override
  State<StencilPalette> createState() => _StencilPaletteState();
}

class _StencilPaletteState extends State<StencilPalette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.registry.search(_query);
    final byCategory = <StencilCategory, List<StencilDefinition>>{};
    for (final stencil in results) {
      (byCategory[stencil.category] ??= []).add(stencil);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search stencils…',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(
                    categoryLabel(entry.key),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final stencil in entry.value)
                  _PaletteItem(stencil: stencil),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.stencil});

  final StencilDefinition stencil;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      dense: true,
      leading: const Icon(Icons.crop_square_outlined),
      title: Text(stencil.displayName, style: const TextStyle(fontSize: 13)),
    );
    return Draggable<StencilDefinition>(
      data: stencil,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(stencil.displayName),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}

/// A display label for [category] — reused by the element tree so a
/// block's category reads the same way everywhere.
String categoryLabel(StencilCategory category) => switch (category) {
  StencilCategory.primitives => 'Primitives',
  StencilCategory.delayShift => 'Delay & Shift',
  StencilCategory.multirateSampling => 'Multirate & Sampling',
  StencilCategory.quantizationConversion => 'Quantization & Conversion',
  StencilCategory.filterStructures => 'Filter Structures',
  StencilCategory.transforms => 'Transforms',
  StencilCategory.commsModulation => 'Comms / Modulation',
  StencilCategory.adaptiveStatistical => 'Adaptive / Statistical',
  StencilCategory.controlOverlap => 'Control',
  StencilCategory.hardware => 'Hardware',
  StencilCategory.analysisPlots => 'Analysis Plots',
};
