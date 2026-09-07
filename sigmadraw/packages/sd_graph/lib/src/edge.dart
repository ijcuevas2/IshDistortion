import 'package:meta/meta.dart';

/// A directed port -> port connection (§4).
@immutable
class Edge {
  const Edge({
    required this.id,
    required this.fromBlockId,
    required this.fromPortId,
    required this.toBlockId,
    required this.toPortId,
    this.route,
    this.signalLabel,
  });

  final String id;
  final String fromBlockId;
  final String fromPortId;
  final String toBlockId;
  final String toPortId;

  /// `orthogonal` | `polyline` | `curved` (§9), if set.
  final String? route;
  final String? signalLabel;

  @override
  String toString() => '$id: $fromBlockId:$fromPortId -> $toBlockId:$toPortId';
}
