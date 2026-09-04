import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'port.dart';

/// A typed block instance (§4): a stencil type, its ports, its resolved
/// parameters, and whether it passes signal through within the same
/// sample instant (`directFeedthrough` — false only for state-holding
/// blocks; this is exactly what [detectAlgebraicLoops] keys off of).
///
/// Hierarchical/subsystem support ("bridge ports to inner graph", §4) is
/// flagged via [isSubsystem] but not implemented: a full nested-graph
/// model is a substantial feature on its own, and every stencil this
/// project ships so far (§5.1-5.3) is flat. Revisit when §5.5's composite
/// filter-structure templates need it.
@immutable
class Block {
  const Block({
    required this.id,
    required this.type,
    required this.ports,
    this.label,
    this.params = const {},
    this.directFeedthrough = true,
    this.isSubsystem = false,
  });

  final String id;
  final String type;
  final List<Port> ports;
  final String? label;
  final Map<String, Object?> params;
  final bool directFeedthrough;
  final bool isSubsystem;

  Port? portById(String portId) =>
      ports.firstWhereOrNull((p) => p.id == portId);

  Iterable<Port> get inputPorts =>
      ports.where((p) => p.direction == PortDirection.input);

  Iterable<Port> get outputPorts =>
      ports.where((p) => p.direction == PortDirection.output);
}
