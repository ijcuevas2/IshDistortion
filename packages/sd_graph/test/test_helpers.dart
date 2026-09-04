import 'package:sd_graph/sd_graph.dart';

const _real = DataType(ScalarType.real);

Port inPort(String id, {DataType dataType = _real, int vlen = 1}) => Port(
  id: id,
  direction: PortDirection.input,
  dataType: dataType,
  vlen: vlen,
);

Port outPort(String id, {DataType dataType = _real, int vlen = 1}) => Port(
  id: id,
  direction: PortDirection.output,
  dataType: dataType,
  vlen: vlen,
);

Block block(
  String id,
  String type, {
  List<Port> ports = const [],
  Map<String, Object?> params = const {},
  bool directFeedthrough = true,
}) => Block(
  id: id,
  type: type,
  ports: ports,
  params: params,
  directFeedthrough: directFeedthrough,
);

Edge edge(String id, String from, String to) {
  final fromParts = from.split(':');
  final toParts = to.split(':');
  return Edge(
    id: id,
    fromBlockId: fromParts[0],
    fromPortId: fromParts[1],
    toBlockId: toParts[0],
    toPortId: toParts[1],
  );
}
