/// A port's direction. Named to avoid the `in` keyword clash mentioned in
/// `sd_document`'s `sd:ports` schema (§3/§4): serializes to `"in"`/`"out"`.
enum PortDirection {
  input,
  output;

  String get wireValue => this == input ? 'in' : 'out';
}

/// A stencil's port, in the stencil's own local coordinate space (before
/// placement). Serializes to exactly the `{id,dir,dtype,vlen,rate,x,y,
/// angle}` shape `sd_document`'s `SdBlockSemantics.blockPorts` expects —
/// `sd_graph` (Phase 4) is what turns this raw JSON into a typed `Port`
/// model; this package only needs to emit it correctly.
class PortSpec {
  const PortSpec({
    required this.id,
    required this.direction,
    this.dtype = 'real',
    this.vlen = 1,
    this.rate,
    required this.x,
    required this.y,
    this.angle = 0,
  });

  final String id;
  final PortDirection direction;
  final String dtype;
  final int vlen;
  final String? rate;

  /// Position in the stencil's own local coordinate space.
  final double x;
  final double y;

  /// Outward-facing direction in degrees (0 = +x/right, 90 = +y/down,
  /// matching SVG's y-down convention), e.g. for port-snap alignment.
  final double angle;

  Map<String, Object?> toJson() => {
    'id': id,
    'dir': direction.wireValue,
    'dtype': dtype,
    'vlen': vlen,
    if (rate != null) 'rate': rate,
    'x': x,
    'y': y,
    'angle': angle,
  };
}
