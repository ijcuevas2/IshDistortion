import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_input/sd_input.dart';

void main() {
  group('PalmRejectionFilter', () {
    test('starts with no stylus active, and allows touch', () {
      final filter = PalmRejectionFilter();
      expect(filter.isStylusActive, isFalse);
      expect(filter.shouldInk(PointerDeviceKind.touch), isTrue);
    });

    test('a stylus going down activates it; going up deactivates it', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isTrue);

      filter.onPointerEvent(
        const PointerUpEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isFalse);
    });

    test('a stylus in proximity (hover) counts as active too', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerHoverEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isTrue);

      filter.onPointerEvent(
        const PointerRemovedEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isFalse);
    });

    test('the eraser end also counts as "a stylus", not just the tip', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(
          kind: PointerDeviceKind.invertedStylus,
          device: 1,
        ),
      );
      expect(filter.isStylusActive, isTrue);
    });

    test('cancelling a stylus down deactivates it, same as lifting it', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      filter.onPointerEvent(
        const PointerCancelEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isFalse);
    });

    test('touch and mouse events never affect stylus-active state', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.touch, device: 2),
      );
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.mouse, device: 3),
      );
      expect(filter.isStylusActive, isFalse);
    });

    test('two simultaneous styluses: only inactive once both lift', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 2),
      );
      filter.onPointerEvent(
        const PointerUpEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(filter.isStylusActive, isTrue, reason: 'device 2 is still down');

      filter.onPointerEvent(
        const PointerUpEvent(kind: PointerDeviceKind.stylus, device: 2),
      );
      expect(filter.isStylusActive, isFalse);
    });

    test('shouldInk: touch is rejected only while a stylus is active', () {
      final filter = PalmRejectionFilter();
      expect(filter.shouldInk(PointerDeviceKind.touch), isTrue);

      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      expect(
        filter.shouldInk(PointerDeviceKind.touch),
        isFalse,
        reason:
            'this is the palm-rejection case: a resting palm while '
            'the stylus writes',
      );
    });

    test('shouldInk: a pen, its eraser, and a mouse are never rejected', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      // Even with a stylus active, none of these are the palm-rejection
      // case, so none should ever be blocked by this filter.
      expect(filter.shouldInk(PointerDeviceKind.stylus), isTrue);
      expect(filter.shouldInk(PointerDeviceKind.invertedStylus), isTrue);
      expect(filter.shouldInk(PointerDeviceKind.mouse), isTrue);
    });

    test('reset() clears all tracked state', () {
      final filter = PalmRejectionFilter();
      filter.onPointerEvent(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, device: 1),
      );
      filter.reset();
      expect(filter.isStylusActive, isFalse);
      expect(filter.shouldInk(PointerDeviceKind.touch), isTrue);
    });
  });

  group('hasInkablePressure', () {
    test('null (device reports no pressure at all) is inkable', () {
      expect(hasInkablePressure(null), isTrue);
    });

    test('a positive pressure is inkable', () {
      expect(hasInkablePressure(0.5), isTrue);
    });

    test('exactly zero pressure is not inkable', () {
      expect(hasInkablePressure(0.0), isFalse);
    });

    test('a negative pressure (never physically real, but defensively) is not inkable', () {
      expect(hasInkablePressure(-0.1), isFalse);
    });
  });
}
