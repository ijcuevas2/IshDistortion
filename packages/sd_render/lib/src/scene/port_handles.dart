import 'package:flutter/widgets.dart';
import 'package:sd_document/sd_document.dart';

import '../geometry/svg_transform.dart';

/// One port's resolved world-space position, for the canvas's connector-
/// drawing interaction and its rendered port dots (§9: "connectors attach
/// to typed PORTS — port snap").
class PortHandle {
  const PortHandle({
    required this.element,
    required this.portId,
    required this.isOutput,
    required this.position,
  });

  final SdElement element;
  final String portId;
  final bool isOutput;
  final Offset position;
}

/// Every port on every block anywhere in [document], with its world
/// position resolved through the full ancestor transform chain. Walks the
/// document directly (not the retained scene) since a port needn't have
/// its own paintable geometry to exist.
List<PortHandle> collectPortHandles(SdDocument document) {
  final handles = <PortHandle>[];
  for (final element in document.root.descendantElements) {
    final ports = element.blockPorts;
    if (ports.isEmpty) continue;
    final worldTransform =
        parentWorldTransformOf(element) * currentLocalTransform(element);
    for (final port in ports) {
      final x = (port['x'] as num?)?.toDouble() ?? 0;
      final y = (port['y'] as num?)?.toDouble() ?? 0;
      final id = port['id'] as String?;
      if (id == null) continue;
      handles.add(
        PortHandle(
          element: element,
          portId: id,
          isOutput: port['dir'] == 'out',
          position: MatrixUtils.transformPoint(worldTransform, Offset(x, y)),
        ),
      );
    }
  }
  return handles;
}

/// The closest handle to [point] within [tolerance] (document units), or
/// `null`. Pass [isOutput] to restrict to just output or just input ports,
/// e.g. only offering output ports as a connector's possible start.
PortHandle? nearestPortHandle(
  List<PortHandle> handles,
  Offset point,
  double tolerance, {
  bool? isOutput,
}) {
  PortHandle? closest;
  var closestDistance = double.infinity;
  for (final handle in handles) {
    if (isOutput != null && handle.isOutput != isOutput) continue;
    final distance = (handle.position - point).distance;
    if (distance <= tolerance && distance < closestDistance) {
      closest = handle;
      closestDistance = distance;
    }
  }
  return closest;
}
