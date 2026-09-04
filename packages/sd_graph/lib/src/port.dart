import 'package:meta/meta.dart';

import 'types.dart';

enum PortDirection { input, output }

/// A typed port on a [Block] (§4). Modeled after GNU Radio's port
/// concept (dtype, vlen, optional rate) plus the fixed-point/position
/// fields §4 explicitly calls for.
@immutable
class Port {
  const Port({
    required this.id,
    required this.direction,
    required this.dataType,
    this.vlen = 1,
    this.sampleRate,
    this.wordLength,
    this.x = 0,
    this.y = 0,
    this.angle = 0,
  });

  final String id;
  final PortDirection direction;
  final DataType dataType;

  /// Vector length per item (GNU Radio's `vlen`) — separate from
  /// [DataType.shape]'s vector/matrix *kind*.
  final int vlen;
  final SampleRate? sampleRate;
  final QFormat? wordLength;

  /// Layout position/orientation in the owning block's local coordinate
  /// space, for port-snap and connector routing (§9).
  final double x;
  final double y;
  final double angle;

  /// Parses one entry of `sd:ports` JSON (`{id,dir,dtype,vlen,rate,x,y,
  /// angle}` — `sd_document`'s `SdBlockSemantics.blockPorts` shape).
  factory Port.fromJson(Map<String, Object?> json) {
    final rate = json['rate'];
    return Port(
      id: json['id']! as String,
      direction: json['dir'] == 'out'
          ? PortDirection.output
          : PortDirection.input,
      dataType: parseDataType(json['dtype'] as String? ?? 'real'),
      vlen: (json['vlen'] as num?)?.toInt() ?? 1,
      sampleRate: rate is String ? SampleRate.symbol(rate) : null,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      angle: (json['angle'] as num?)?.toDouble() ?? 0,
    );
  }
}
