import 'dart:ui';

/// Thrown when an SVG path `d` attribute (or a `points` list) is malformed.
class SvgPathParseException implements Exception {
  SvgPathParseException(this.message);
  final String message;

  @override
  String toString() => 'SvgPathParseException: $message';
}

/// Parses an SVG path `d` attribute into a Flutter [Path].
///
/// Supports the full path grammar: `M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z`,
/// both absolute and relative, with implicit command repetition (extra
/// coordinate sets after one command letter reuse it — and, per spec, a
/// repeated `M`/`m` becomes an implicit `L`/`l`) and reflected control
/// points for `S`/`T`. Arc-to-bezier conversion is delegated to
/// `Path.arcToPoint`, which Flutter models directly on the SVG arc command
/// (`rotation` in degrees, `clockwise` == the sweep flag).
Path parseSvgPathData(String d) {
  final path = Path();
  final tokens = _PathTokenizer(d);

  var current = Offset.zero;
  var subpathStart = Offset.zero;
  Offset? lastCubicControl;
  Offset? lastQuadControl;
  String? lastCommand;

  while (tokens.hasMoreCommands) {
    final cmd = tokens.nextCommand();
    final relative = cmd == cmd.toLowerCase();
    var upper = cmd.toUpperCase();
    if (upper != 'Z' && !tokens.hasMoreNumbers()) {
      throw SvgPathParseException(
        'Command "$cmd" expects at least one parameter in "$d"',
      );
    }

    do {
      switch (upper) {
        case 'M':
          final p = _point(tokens, current, relative);
          path.moveTo(p.dx, p.dy);
          current = p;
          subpathStart = p;
          lastCubicControl = null;
          lastQuadControl = null;
          upper = 'L'; // repeated coordinate pairs after the first are implicit lineto
        case 'L':
          final p = _point(tokens, current, relative);
          path.lineTo(p.dx, p.dy);
          current = p;
          lastCubicControl = null;
          lastQuadControl = null;
        case 'H':
          final x = tokens.nextNumber();
          current = Offset(relative ? current.dx + x : x, current.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadControl = null;
        case 'V':
          final y = tokens.nextNumber();
          current = Offset(current.dx, relative ? current.dy + y : y);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadControl = null;
        case 'C':
          final c1 = _point(tokens, current, relative);
          final c2 = _point(tokens, current, relative);
          final p = _point(tokens, current, relative);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
          current = p;
          lastCubicControl = c2;
          lastQuadControl = null;
        case 'S':
          final c1 = _reflect(current, lastCommand, const {
            'C',
            'S',
          }, lastCubicControl);
          final c2 = _point(tokens, current, relative);
          final p = _point(tokens, current, relative);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
          current = p;
          lastCubicControl = c2;
          lastQuadControl = null;
        case 'Q':
          final c1 = _point(tokens, current, relative);
          final p = _point(tokens, current, relative);
          path.quadraticBezierTo(c1.dx, c1.dy, p.dx, p.dy);
          current = p;
          lastQuadControl = c1;
          lastCubicControl = null;
        case 'T':
          final c1 = _reflect(current, lastCommand, const {
            'Q',
            'T',
          }, lastQuadControl);
          final p = _point(tokens, current, relative);
          path.quadraticBezierTo(c1.dx, c1.dy, p.dx, p.dy);
          current = p;
          lastQuadControl = c1;
          lastCubicControl = null;
        case 'A':
          final rx = tokens.nextNumber().abs();
          final ry = tokens.nextNumber().abs();
          final rotation = tokens.nextNumber();
          final largeArc = tokens.nextFlag();
          final sweep = tokens.nextFlag();
          final p = _point(tokens, current, relative);
          if (rx == 0 || ry == 0) {
            path.lineTo(p.dx, p.dy);
          } else {
            path.arcToPoint(
              p,
              radius: Radius.elliptical(rx, ry),
              rotation: rotation,
              largeArc: largeArc,
              clockwise: sweep,
            );
          }
          current = p;
          lastCubicControl = null;
          lastQuadControl = null;
        case 'Z':
          path.close();
          current = subpathStart;
          lastCubicControl = null;
          lastQuadControl = null;
        default:
          throw SvgPathParseException(
            'Unsupported path command "$cmd" in "$d"',
          );
      }
      lastCommand = upper;
    } while (upper != 'Z' && tokens.hasMoreNumbers());
  }
  return path;
}

Offset _point(_PathTokenizer tokens, Offset current, bool relative) {
  final x = tokens.nextNumber();
  final y = tokens.nextNumber();
  final p = Offset(x, y);
  return relative ? current + p : p;
}

/// `S`/`T`'s control point is the reflection of the previous curve's last
/// control point through the current point — but only when the previous
/// command was the same curve family; otherwise it coincides with the
/// current point (SVG spec, "smooth curveto").
Offset _reflect(
  Offset current,
  String? lastCommand,
  Set<String> family,
  Offset? lastControl,
) {
  if (lastControl != null && family.contains(lastCommand)) {
    return current * 2 - lastControl;
  }
  return current;
}

/// Parses a `points` attribute (`<polyline>`/`<polygon>`): a flat,
/// whitespace/comma-separated list of numbers, taken pairwise.
List<Offset> parseSvgPointList(String points) {
  final tokens = _PathTokenizer(points);
  final result = <Offset>[];
  while (tokens.hasMoreNumbers()) {
    final x = tokens.nextNumber();
    if (!tokens.hasMoreNumbers()) {
      throw SvgPathParseException(
        'Odd number of coordinates in points list "$points"',
      );
    }
    final y = tokens.nextNumber();
    result.add(Offset(x, y));
  }
  return result;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isSeparator(String c) =>
    c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r';

class _PathTokenizer {
  _PathTokenizer(this._s);

  final String _s;
  int _i = 0;

  void _skipSeparators() {
    while (_i < _s.length && _isSeparator(_s[_i])) {
      _i++;
    }
  }

  bool get hasMoreCommands {
    _skipSeparators();
    return _i < _s.length;
  }

  String nextCommand() {
    _skipSeparators();
    return _s[_i++];
  }

  bool get _atNumberStart {
    if (_i >= _s.length) return false;
    final c = _s[_i];
    return c == '-' || c == '+' || c == '.' || _isDigit(c);
  }

  bool hasMoreNumbers() {
    _skipSeparators();
    return _atNumberStart;
  }

  double nextNumber() {
    _skipSeparators();
    final start = _i;
    if (_i < _s.length && (_s[_i] == '-' || _s[_i] == '+')) _i++;
    var sawDigits = false;
    while (_i < _s.length && _isDigit(_s[_i])) {
      _i++;
      sawDigits = true;
    }
    if (_i < _s.length && _s[_i] == '.') {
      _i++;
      while (_i < _s.length && _isDigit(_s[_i])) {
        _i++;
        sawDigits = true;
      }
    }
    if (!sawDigits) {
      throw SvgPathParseException(
        'Expected a number at offset $start in "$_s"',
      );
    }
    if (_i < _s.length && (_s[_i] == 'e' || _s[_i] == 'E')) {
      final expStart = _i;
      _i++;
      if (_i < _s.length && (_s[_i] == '-' || _s[_i] == '+')) _i++;
      var sawExpDigit = false;
      while (_i < _s.length && _isDigit(_s[_i])) {
        _i++;
        sawExpDigit = true;
      }
      if (!sawExpDigit) _i = expStart; // false alarm — not actually an exponent
    }
    return double.parse(_s.substring(start, _i));
  }

  /// Arc flags are exactly one `0`/`1` digit — parsed specially because e.g.
  /// `11` with no separator means two flags, not the number eleven.
  bool nextFlag() {
    _skipSeparators();
    if (_i >= _s.length || (_s[_i] != '0' && _s[_i] != '1')) {
      throw SvgPathParseException(
        'Expected an arc flag (0 or 1) at offset $_i in "$_s"',
      );
    }
    return _s[_i++] == '1';
  }
}
