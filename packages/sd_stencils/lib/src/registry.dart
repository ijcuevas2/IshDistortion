import 'primitives.dart';
import 'stencil_definition.dart';

/// Lookup/search over the stencil catalog — the model behind `sd_ui`'s
/// stencil palette (§10: "searchable, categorized; drag-to-canvas").
class StencilRegistry {
  StencilRegistry(Iterable<StencilDefinition> stencils)
    : _byId = {for (final s in stencils) s.id: s};

  /// The default registry: every built-in stencil this package ships.
  factory StencilRegistry.builtIn() => StencilRegistry(corePrimitiveStencils);

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
