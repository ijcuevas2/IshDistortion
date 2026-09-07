import 'dart:ui';

import 'package:sd_document/sd_document.dart';

/// Inheritance-aware paint state carried down the tree walk, mirroring
/// SVG/CSS presentation-attribute inheritance: `fill`/`stroke`/etc.
/// propagate from parent to child unless a child overrides them; `opacity`
/// (element, not inherited) always resets to `1.0` per element.
///
/// Known simplification: an element's own `opacity` is folded directly into
/// its fill/stroke alpha rather than composited via `Canvas.saveLayer`, so a
/// `<g opacity="0.5">` with *overlapping* children will show faint seams at
/// the overlaps instead of one uniformly-transparent group. Correct for the
/// common case (a block's children don't overlap); revisit with `saveLayer`
/// if a real diagram needs true group compositing (§7/§11 polish).
class SvgPaintState {
  const SvgPaintState({
    this.fill = const Color(0xFF000000),
    this.fillOpacity = 1.0,
    this.stroke,
    this.strokeWidth = 1.0,
    this.strokeOpacity = 1.0,
    this.opacity = 1.0,
    this.nonScalingStroke = false,
  });

  /// `null` means `fill: none`.
  final Color? fill;
  final double fillOpacity;

  /// `null` means `stroke: none` (SVG's initial value).
  final Color? stroke;
  final double strokeWidth;
  final double strokeOpacity;

  /// This element's own `opacity` — not inherited (see class doc).
  final double opacity;

  final bool nonScalingStroke;

  static const initial = SvgPaintState();

  /// The state after layering [element]'s own presentation attributes
  /// (and inline `style`, which wins per the CSS cascade) on top of this
  /// (its parent's) resolved state.
  SvgPaintState resolve(SdElement element) {
    final props = _presentationProperties(element);

    Color? resolveColor(String key, Color? inherited) {
      final raw = props[key];
      if (raw == null || raw == 'inherit') return inherited;
      return parseSvgColor(raw);
    }

    double resolveNumber(String key, double inherited) {
      final raw = props[key];
      if (raw == null) return inherited;
      return double.tryParse(raw.trim()) ?? inherited;
    }

    return SvgPaintState(
      fill: resolveColor('fill', fill),
      fillOpacity: resolveNumber('fill-opacity', fillOpacity),
      stroke: resolveColor('stroke', stroke),
      strokeWidth: resolveNumber('stroke-width', strokeWidth),
      strokeOpacity: resolveNumber('stroke-opacity', strokeOpacity),
      opacity: resolveNumber('opacity', 1.0), // element-level: never inherited
      nonScalingStroke:
          props['vector-effect']?.contains('non-scaling-stroke') ?? false,
    );
  }

  /// The fill paint to use for this element's own geometry, or `null` if it
  /// should not be filled at all (`fill: none`, or fully transparent).
  Paint? get fillPaint {
    final color = fill;
    if (color == null) return null;
    final alpha = (color.a * fillOpacity * opacity).clamp(0.0, 1.0).toDouble();
    if (alpha <= 0) return null;
    return Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
  }

  /// The stroke paint to use for this element's own geometry, or `null` if
  /// it should not be stroked at all.
  Paint? get strokePaint {
    final color = stroke;
    if (color == null || strokeWidth <= 0) return null;
    final alpha = (color.a * strokeOpacity * opacity)
        .clamp(0.0, 1.0)
        .toDouble();
    if (alpha <= 0) return null;
    return Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
  }
}

Map<String, String> _presentationProperties(SdElement element) {
  const keys = [
    'fill',
    'fill-opacity',
    'stroke',
    'stroke-width',
    'stroke-opacity',
    'opacity',
    'vector-effect',
  ];
  final props = <String, String>{
    for (final key in keys) key: ?element.getAttribute(SdQName(key)),
  };
  final style = element.getAttribute(const SdQName('style'));
  if (style != null) {
    for (final declaration in style.split(';')) {
      final colon = declaration.indexOf(':');
      if (colon <= 0) continue;
      final key = declaration.substring(0, colon).trim();
      final value = declaration.substring(colon + 1).trim();
      if (value.isNotEmpty) {
        props[key] = value; // style: wins over presentation attrs
      }
    }
  }
  return props;
}

final _hexColor = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$');
final _rgbColor = RegExp(r'^rgba?\(([^)]*)\)$');

/// Parses a subset of CSS/SVG color syntax: `#rgb`, `#rrggbb`, `#rrggbbaa`,
/// `rgb()`/`rgba()` (percentages or 0-255 per channel), `none`/
/// `transparent`, a handful of named colors, and `currentColor` (falls back
/// to black — no CSS cascade is tracked to resolve it properly). Returns
/// `null` for `none`/`transparent`; unrecognized input conservatively
/// resolves to opaque black rather than throwing, since a malformed color
/// on one shape shouldn't take down rendering of an entire diagram.
Color? parseSvgColor(String raw) {
  final value = raw.trim().toLowerCase();
  if (value == 'none' || value == 'transparent') return null;
  if (value == 'currentcolor') return const Color(0xFF000000);

  final hexMatch = _hexColor.firstMatch(value);
  if (hexMatch != null) {
    final hex = hexMatch.group(1)!;
    if (hex.length == 3) {
      final r = int.parse(hex[0] * 2, radix: 16);
      final g = int.parse(hex[1] * 2, radix: 16);
      final b = int.parse(hex[2] * 2, radix: 16);
      return Color.fromARGB(255, r, g, b);
    }
    if (hex.length == 6) {
      return Color(0xFF000000 | int.parse(hex, radix: 16));
    }
    // 8 hex digits: #rrggbbaa.
    final full = int.parse(hex, radix: 16);
    return Color.fromARGB(
      full & 0xFF,
      (full >> 24) & 0xFF,
      (full >> 16) & 0xFF,
      (full >> 8) & 0xFF,
    );
  }

  final rgbMatch = _rgbColor.firstMatch(value);
  if (rgbMatch != null) {
    final parts = rgbMatch.group(1)!.split(',').map((s) => s.trim()).toList();
    if (parts.length >= 3) {
      int channel(String s) {
        final pct = s.endsWith('%');
        final n = double.tryParse(pct ? s.substring(0, s.length - 1) : s) ?? 0;
        return (pct ? n / 100 * 255 : n).round().clamp(0, 255).toInt();
      }

      final a = parts.length > 3
          ? ((double.tryParse(parts[3]) ?? 1.0) * 255)
                .round()
                .clamp(0, 255)
                .toInt()
          : 255;
      return Color.fromARGB(
        a,
        channel(parts[0]),
        channel(parts[1]),
        channel(parts[2]),
      );
    }
  }

  return _namedColors[value] ?? const Color(0xFF000000);
}

const _namedColors = <String, Color>{
  'black': Color(0xFF000000),
  'white': Color(0xFFFFFFFF),
  'red': Color(0xFFFF0000),
  'green': Color(0xFF008000),
  'lime': Color(0xFF00FF00),
  'blue': Color(0xFF0000FF),
  'yellow': Color(0xFFFFFF00),
  'cyan': Color(0xFF00FFFF),
  'aqua': Color(0xFF00FFFF),
  'magenta': Color(0xFFFF00FF),
  'fuchsia': Color(0xFFFF00FF),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
  'orange': Color(0xFFFFA500),
  'purple': Color(0xFF800080),
  'brown': Color(0xFFA52A2A),
  'pink': Color(0xFFFFC0CB),
  'silver': Color(0xFFC0C0C0),
  'gold': Color(0xFFFFD700),
  'navy': Color(0xFF000080),
  'teal': Color(0xFF008080),
  'olive': Color(0xFF808000),
  'maroon': Color(0xFF800000),
  'indigo': Color(0xFF4B0082),
};
