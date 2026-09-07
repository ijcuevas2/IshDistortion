import 'dart:ui';

import 'package:sd_document/sd_document.dart';

import 'svg_path_data.dart';

double? _num(SdElement e, String name) {
  final raw = e.getAttribute(SdQName(name));
  return raw == null ? null : double.tryParse(raw.trim());
}

/// Converts a basic SVG shape element (`rect`/`circle`/`ellipse`/`line`/
/// `polyline`/`polygon`/`path`) to a [Path] in its own local coordinate
/// space (i.e. before its own `transform` attribute is applied — the scene
/// builder applies that separately). Returns `null` for any other element
/// (groups, text, defs, ...), which is not an error: those are handled
/// elsewhere or simply carry no direct geometry of their own.
Path? svgShapeToPath(SdElement element) {
  switch (element.name.local) {
    case 'rect':
      final x = _num(element, 'x') ?? 0;
      final y = _num(element, 'y') ?? 0;
      final w = _num(element, 'width') ?? 0;
      final h = _num(element, 'height') ?? 0;
      if (w <= 0 || h <= 0) return Path();
      var rx = _num(element, 'rx');
      var ry = _num(element, 'ry');
      rx ??= ry;
      ry ??= rx;
      if (rx == null || ry == null || (rx == 0 && ry == 0)) {
        return Path()..addRect(Rect.fromLTWH(x, y, w, h));
      }
      rx = rx.clamp(0, w / 2).toDouble();
      ry = ry.clamp(0, h / 2).toDouble();
      return Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.elliptical(rx, ry),
        ),
      );

    case 'circle':
      final cx = _num(element, 'cx') ?? 0;
      final cy = _num(element, 'cy') ?? 0;
      final r = _num(element, 'r') ?? 0;
      if (r <= 0) return Path();
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    case 'ellipse':
      final cx = _num(element, 'cx') ?? 0;
      final cy = _num(element, 'cy') ?? 0;
      final rx = _num(element, 'rx') ?? 0;
      final ry = _num(element, 'ry') ?? 0;
      if (rx <= 0 || ry <= 0) return Path();
      return Path()..addOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      );

    case 'line':
      final x1 = _num(element, 'x1') ?? 0;
      final y1 = _num(element, 'y1') ?? 0;
      final x2 = _num(element, 'x2') ?? 0;
      final y2 = _num(element, 'y2') ?? 0;
      return Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2);

    case 'polyline':
    case 'polygon':
      final raw = element.getAttribute(const SdQName('points'));
      if (raw == null) return Path();
      final points = parseSvgPointList(raw);
      if (points.isEmpty) return Path();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (element.name.local == 'polygon') path.close();
      return path;

    case 'path':
      final d = element.getAttribute(const SdQName('d'));
      return d == null ? Path() : parseSvgPathData(d);

    default:
      return null;
  }
}
