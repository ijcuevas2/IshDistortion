import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_input/sd_input.dart';

PointerDownEvent eventOf(PointerDeviceKind kind) =>
    PointerDownEvent(kind: kind, device: 1);

void main() {
  group('classifyDevice', () {
    test('a stylus is pen', () {
      expect(classifyDevice(eventOf(PointerDeviceKind.stylus)), DeviceRole.pen);
    });

    test('an inverted stylus is penEraser, not a "flipped pen"', () {
      expect(
        classifyDevice(eventOf(PointerDeviceKind.invertedStylus)),
        DeviceRole.penEraser,
      );
    });

    test('touch is touch', () {
      expect(
        classifyDevice(eventOf(PointerDeviceKind.touch)),
        DeviceRole.touch,
      );
    });

    test('mouse is mouse', () {
      expect(
        classifyDevice(eventOf(PointerDeviceKind.mouse)),
        DeviceRole.mouse,
      );
    });

    test(
      'trackpad and unknown are both unknown, never trusted as a specific role',
      () {
        // Not eventOf/PointerDownEvent here: Flutter's own PointerDownEvent
        // asserts its kind is never trackpad (a trackpad's own interaction
        // surfaces as pan/zoom gesture events, never a literal pointer
        // "down") — found by actually running this test, not assumed.
        // PointerAddedEvent carries no such physical-semantics assertion.
        expect(
          classifyDevice(
            const PointerAddedEvent(
              kind: PointerDeviceKind.trackpad,
              device: 1,
            ),
          ),
          DeviceRole.unknown,
        );
        expect(
          classifyDevice(
            const PointerAddedEvent(kind: PointerDeviceKind.unknown, device: 1),
          ),
          DeviceRole.unknown,
        );
      },
    );
  });
}
