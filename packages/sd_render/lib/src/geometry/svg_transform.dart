import 'dart:math' as math;

import 'package:sd_document/sd_document.dart';
import 'package:vector_math/vector_math_64.dart';

final _functionPattern = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
final _numberPattern = RegExp(r'[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?');

/// Parses an SVG `transform` attribute value (e.g.
/// `"translate(10,20) rotate(45) scale(2)"`) into one composed [Matrix4].
/// Per the SVG spec, "the resulting matrix is the product of the individual
/// matrices in [the order listed]": each function is right-multiplied onto
/// the running result in the order it appears in the string.
Matrix4 parseSvgTransform(String value) {
  var result = Matrix4.identity();
  for (final match in _functionPattern.allMatches(value)) {
    final args = _numberPattern
        .allMatches(match.group(2)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    result = result * _matrixFor(match.group(1)!, args);
  }
  return result;
}

Matrix4 _matrixFor(String function, List<double> a) {
  double arg(int i, [double fallback = 0]) => i < a.length ? a[i] : fallback;

  switch (function) {
    case 'matrix':
      if (a.length != 6) return Matrix4.identity();
      // SVG matrix(a,b,c,d,e,f) is the 3x3 affine matrix
      //   [ a c e ]        so, in column-major 4x4 (this package's Matrix4
      //   [ b d f ]        constructor fills storage column-by-column):
      //   [ 0 0 1 ]        col0=(a,b,0,0) col1=(c,d,0,0) col3=(e,f,0,1).
      return Matrix4(
        a[0],
        a[1],
        0,
        0,
        a[2],
        a[3],
        0,
        0,
        0,
        0,
        1,
        0,
        a[4],
        a[5],
        0,
        1,
      );

    case 'translate':
      return Matrix4.translationValues(arg(0), arg(1), 0);

    case 'scale':
      final sx = arg(0, 1);
      final sy = a.length > 1 ? a[1] : sx;
      return Matrix4.identity()..scaleByDouble(sx, sy, 1.0, 1.0);

    case 'rotate':
      if (a.isEmpty) return Matrix4.identity();
      final angle = arg(0) * math.pi / 180.0;
      if (a.length >= 3) {
        final cx = a[1];
        final cy = a[2];
        // Rotate about (cx, cy): translate it to the origin, rotate, then
        // translate back. `rotateZ`/`translate` right-multiply onto the
        // matrix built so far, so this sequence *is* T(cx,cy)·Rz·T(-cx,-cy).
        return Matrix4.translationValues(cx, cy, 0)
          ..rotateZ(angle)
          ..translateByDouble(-cx, -cy, 0.0, 1.0);
      }
      return Matrix4.rotationZ(angle);

    case 'skewX':
      final t = math.tan(arg(0) * math.pi / 180.0);
      return Matrix4(1, 0, 0, 0, t, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

    case 'skewY':
      final t = math.tan(arg(0) * math.pi / 180.0);
      return Matrix4(1, t, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

    default:
      return Matrix4.identity();
  }
}

/// The world transform of [element]'s *parent* — i.e. what [element]'s own
/// `transform` attribute is relative to — by walking up to the document
/// root and composing each ancestor's own `transform` (root-most first).
/// Works for any element, not just ones with their own paintable geometry
/// (e.g. a `<use>` or a `<g>`).
Matrix4 parentWorldTransformOf(SdElement element) {
  final ancestors = <SdElement>[];
  for (var p = element.parent; p != null; p = p.parent) {
    ancestors.add(p);
  }
  var m = Matrix4.identity();
  for (final ancestor in ancestors.reversed) {
    final raw = ancestor.getAttribute(const SdQName('transform'));
    if (raw != null) m = m * parseSvgTransform(raw);
  }
  return m;
}

/// [element]'s own current local transform (identity if it has none).
Matrix4 currentLocalTransform(SdElement element) {
  final raw = element.getAttribute(const SdQName('transform'));
  return raw == null ? Matrix4.identity() : parseSvgTransform(raw);
}

/// Serializes [m] as a generic SVG `matrix(a,b,c,d,e,f)` — always valid,
/// and represents any 2D affine transform exactly without the ambiguity of
/// decomposing it into translate/rotate/scale.
String matrixToSvgTransform(Matrix4 m) {
  final s = m.storage;
  return 'matrix(${_fmt(s[0])} ${_fmt(s[1])} ${_fmt(s[4])} ${_fmt(s[5])} ${_fmt(s[12])} ${_fmt(s[13])})';
}

String _fmt(double v) {
  // Round to a sane precision so repeated edits don't accumulate
  // floating-point noise in the saved file.
  final rounded = (v * 1e6).round() / 1e6;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}

/// Applies a *world-space* delta transform to [element] — rewrites its
/// `transform` attribute so that, composed with its (unchanged) parent
/// chain, its world transform becomes `worldDelta * <old world transform>`.
/// The core primitive behind drag-to-move and drag-to-scale handles
/// (`sigma_canvas.dart`): both just compute the right `worldDelta` and call
/// this, regardless of how deeply [element] is nested. A no-op if an
/// ancestor's transform is degenerate (zero scale) and so uninvertible.
void applyWorldDelta(SdElement element, Matrix4 worldDelta) {
  final parentWorld = parentWorldTransformOf(element);
  final parentInverse = Matrix4.tryInvert(parentWorld);
  if (parentInverse == null) return;
  final oldLocal = currentLocalTransform(element);
  final newLocal = parentInverse * worldDelta * parentWorld * oldLocal;
  element.setAttribute(
    const SdQName('transform'),
    matrixToSvgTransform(newLocal),
  );
}
