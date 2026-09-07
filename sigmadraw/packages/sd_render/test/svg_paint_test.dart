import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

void main() {
  group('parseSvgColor', () {
    test('3, 6, and 8-digit hex', () {
      expect(parseSvgColor('#f00'), const Color(0xFFFF0000));
      expect(parseSvgColor('#ff0000'), const Color(0xFFFF0000));
      expect(parseSvgColor('#ff000080'), const Color(0x80FF0000));
    });

    test('rgb() and rgba(), including percentages', () {
      expect(parseSvgColor('rgb(255,0,0)'), const Color(0xFFFF0000));
      expect(parseSvgColor('rgb(100%,0%,0%)'), const Color(0xFFFF0000));
      expect(
        parseSvgColor('rgba(255,0,0,0.5)'),
        const Color.fromARGB(128, 255, 0, 0),
      );
    });

    test('none and transparent parse to null', () {
      expect(parseSvgColor('none'), isNull);
      expect(parseSvgColor('transparent'), isNull);
    });

    test('a named color', () {
      expect(parseSvgColor('blue'), const Color(0xFF0000FF));
    });

    test('unrecognized input falls back to black rather than throwing', () {
      expect(() => parseSvgColor('not-a-color'), returnsNormally);
      expect(parseSvgColor('not-a-color'), const Color(0xFF000000));
    });
  });

  group('SvgPaintState inheritance', () {
    test('fill inherits down to a child that does not set its own', () {
      final parent = SdElement(
        const SdQName('g'),
        attributes: {const SdQName('fill'): '#00ff00'},
      );
      final child = SdElement(const SdQName('rect'));
      parent.appendChild(child);

      final parentState = SvgPaintState.initial.resolve(parent);
      final childState = parentState.resolve(child);

      expect(childState.fill, const Color(0xFF00FF00));
    });

    test('a child fill overrides, without affecting later siblings via the parent state', () {
      final parentState = SvgPaintState.initial.resolve(
        SdElement(
          const SdQName('g'),
          attributes: {const SdQName('fill'): '#00ff00'},
        ),
      );
      final overriding = parentState.resolve(
        SdElement(
          const SdQName('rect'),
          attributes: {const SdQName('fill'): '#ff0000'},
        ),
      );
      final inheriting = parentState.resolve(SdElement(const SdQName('rect')));

      expect(overriding.fill, const Color(0xFFFF0000));
      expect(inheriting.fill, const Color(0xFF00FF00));
    });

    test('opacity is NOT inherited — each element starts fresh', () {
      final parentState = SvgPaintState.initial.resolve(
        SdElement(
          const SdQName('g'),
          attributes: {const SdQName('opacity'): '0.5'},
        ),
      );
      expect(parentState.opacity, 0.5);

      final childState = parentState.resolve(SdElement(const SdQName('rect')));
      expect(childState.opacity, 1.0);
    });

    test('style="" wins over a presentation attribute', () {
      final state = SvgPaintState.initial.resolve(
        SdElement(
          const SdQName('rect'),
          attributes: {
            const SdQName('fill'): '#ff0000',
            const SdQName('style'): 'fill: #0000ff',
          },
        ),
      );
      expect(state.fill, const Color(0xFF0000FF));
    });

    test('fill: none produces no fill paint', () {
      final state = SvgPaintState.initial.resolve(
        SdElement(
          const SdQName('rect'),
          attributes: {const SdQName('fill'): 'none'},
        ),
      );
      expect(state.fill, isNull);
      expect(state.fillPaint, isNull);
    });

    test('the initial state defaults to black fill and no stroke', () {
      expect(SvgPaintState.initial.fill, const Color(0xFF000000));
      expect(SvgPaintState.initial.stroke, isNull);
    });
  });
}
