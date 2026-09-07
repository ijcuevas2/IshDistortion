import 'adaptive.dart';
import 'comms.dart';
import 'control.dart';
import 'hardware.dart';
import 'primitives.dart';
import 'quantization.dart';
import 'stencil_definition.dart';
import 'transforms.dart';

/// Lookup/search over the stencil catalog — the model behind `sd_ui`'s
/// stencil palette (§10: "searchable, categorized; drag-to-canvas").
class StencilRegistry {
  StencilRegistry(Iterable<StencilDefinition> stencils)
    : _byId = {for (final s in stencils) s.id: s};

  /// The default registry: every built-in stencil this package ships —
  /// §5.1-5.3 (Phase 3) plus §5.4/§5.6/§5.7/§5.8/§5.9/§5.10's leaf
  /// stencils (Phase 7). §5.5's filter *structures* are composite
  /// generators, not single stencils — see `filter_templates.dart`.
  /// §5.11 (analysis-plot objects) is not implemented as placeable
  /// stencils (the plots themselves — pole-zero/Bode/Nyquist/
  /// spectrogram — are live-computed panels, not drag-to-canvas blocks;
  /// see `sd_render`/`sd_ui`).
  ///
  /// `adaptiveStencils` already includes `correlator` (§5.7/§5.8 both
  /// name it — see `adaptive.dart`'s own doc comment), so it lands in
  /// this list via `commsStencils` twice; `StencilRegistry`'s own
  /// id-keyed map collapses the duplicate for free, so this is a no-op,
  /// not a bug.
  factory StencilRegistry.builtIn() => StencilRegistry([
    ...corePrimitiveStencils,
    ...quantizationStencils,
    ...controlStencils,
    ...hardwareStencils,
    ...transformStencils,
    ...commsStencils,
    ...adaptiveStencils,
  ]);

  final Map<String, StencilDefinition> _byId;

  StencilDefinition? byId(String id) => _byId[id];

  List<StencilDefinition> get all => List.unmodifiable(_byId.values);

  List<StencilDefinition> byCategory(StencilCategory category) =>
      _byId.values.where((s) => s.category == category).toList();

  /// Case-insensitive search over id and display name.
  List<StencilDefinition> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return _byId.values
        .where(
          (s) =>
              s.id.toLowerCase().contains(q) ||
              s.displayName.toLowerCase().contains(q),
        )
        .toList();
  }
}
