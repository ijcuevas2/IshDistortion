import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:vector_math/vector_math_64.dart';

Offset _apply(Matrix4 m, Offset p) {
  final v = m.transform3(Vector3(p.dx, p.dy, 0));
  return Offset(v.x, v.y);
}

void main() {
  group('parseSvgTransform', () {
    test('translate', () {
      final m = parseSvgTransform('translate(10,20)');
      expect(_apply(m, Offset.zero), const Offset(10, 20));
    });

    test('translate with one argument defaults ty to 0', () {
      final m = parseSvgTransform('translate(10)');
      expect(_apply(m, Offset.zero), const Offset(10, 0));
    });

    test('scale, one argument applies to both axes', () {
      final m = parseSvgTransform('scale(2)');
      expect(_apply(m, const Offset(3, 4)), const Offset(6, 8));
    });

    test('scale, two arguments apply per axis', () {
      final m = parseSvgTransform('scale(2,3)');
      expect(_apply(m, const Offset(1, 1)), const Offset(2, 3));
    });

    test('rotate about the origin', () {
      final m = parseSvgTransform('rotate(90)');
      final p = _apply(m, const Offset(10, 0));
      expect(p.dx, closeTo(0, 0.001));
      expect(p.dy, closeTo(10, 0.001));
    });

    test('rotate about an explicit center leaves that point fixed', () {
      final m = parseSvgTransform('rotate(180,5,5)');
      final p = _apply(m, const Offset(5, 5));
      expect(p.dx, closeTo(5, 0.001));
      expect(p.dy, closeTo(5, 0.001));
      // And a point mirrors through the center.
      final q = _apply(m, const Offset(10, 5));
      expect(q.dx, closeTo(0, 0.001));
      expect(q.dy, closeTo(5, 0.001));
    });

    test('skewX shifts x proportionally to y', () {
      final m = parseSvgTransform('skewX(45)');
      final p = _apply(m, const Offset(0, 10));
      expect(p.dx, closeTo(10, 0.01)); // tan(45deg) == 1
      expect(p.dy, closeTo(10, 0.01));
    });

    test('matrix() is applied directly', () {
      final m = parseSvgTransform('matrix(1,0,0,1,7,8)');
      expect(_apply(m, Offset.zero), const Offset(7, 8));
    });

    test('multiple functions compose left-to-right (translate then scale)', () {
      // translate(10,0) scale(2) applied to a point: SVG semantics are
      // equivalent to nesting <g translate><g scale>point</g></g> — i.e.
      // the point is scaled first, *then* translated.
      final m = parseSvgTransform('translate(10,0) scale(2)');
      expect(_apply(m, const Offset(1, 1)), const Offset(12, 2));
    });

    test('unknown function is ignored (identity), not a crash', () {
      final m = parseSvgTransform('foo(1,2,3) translate(5,0)');
      expect(_apply(m, Offset.zero), const Offset(5, 0));
    });
  });

  group('parentWorldTransformOf / applyWorldDelta', () {
    test('parent world transform composes ancestor transforms root-first', () {
      final child = SdElement(const SdQName('rect'));
      final group = SdElement(
        const SdQName('g'),
        attributes: {const SdQName('transform'): 'translate(100,0)'},
        children: [child],
      );
      SdElement(
        const SdQName('svg'),
        attributes: {const SdQName('transform'): 'scale(2)'},
        children: [group],
      );

      final parentWorld = parentWorldTransformOf(child);
      // Root scales by 2, then the group translates by 100 *in the
      // already-scaled space* — so a world-space point should come back
      // through: world = scale(2) * translate(100,0) * local.
      expect(_apply(parentWorld, Offset.zero), const Offset(200, 0));
    });

    test('applyWorldDelta moves an element by exactly the requested amount in world space, regardless of an ancestor scale', () {
      final child = SdElement(const SdQName('rect'));
      SdElement(
        const SdQName('g'),
        attributes: {const SdQName('transform'): 'scale(10)'},
        children: [child],
      );

      applyWorldDelta(child, Matrix4.translationValues(50, 0, 0));

      // The child's own local transform must absorb the parent's 10x scale
      // (i.e. become translate(5,0) locally) so the *world*-space move is
      // exactly 50 units, not 500.
      final world =
          parentWorldTransformOf(child) * currentLocalTransform(child);
      expect(_apply(world, Offset.zero).dx, closeTo(50, 0.001));
    });

    test('matrixToSvgTransform output re-parses to an equivalent matrix', () {
      final original = parseSvgTransform(
        'translate(3,4) rotate(30) scale(2,1.5)',
      );
      final roundTripped = parseSvgTransform(matrixToSvgTransform(original));
      final p = _apply(original, const Offset(5, -2));
      final q = _apply(roundTripped, const Offset(5, -2));
      expect(q.dx, closeTo(p.dx, 0.0001));
      expect(q.dy, closeTo(p.dy, 0.0001));
    });
  });
}
