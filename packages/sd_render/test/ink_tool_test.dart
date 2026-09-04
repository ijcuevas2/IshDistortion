import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

Widget _harness(SdDocument doc, {UndoStack? undoStack}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 400,
    height: 300,
    child: SigmaCanvas(
      document: doc,
      tool: CanvasTool.ink,
      undoStack: undoStack,
    ),
  ),
);

void main() {
  testWidgets('a drag with the ink tool commits a real filled path stroke', (
    tester,
  ) async {
    final doc = createBlankSdDocument();
    await tester.pumpWidget(_harness(doc));

    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(60, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(100, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final strokes = doc.root.descendantElements.where(
      (e) => e.strokeId != null,
    );
    expect(strokes, hasLength(1));
    final stroke = strokes.single;
    expect(stroke.name.local, 'path');
    expect(stroke.getAttribute(const SdQName('d')), isNotEmpty);
    expect(stroke.strokeCenterline, isNotEmpty);
  });

  testWidgets('a lone tap with the ink tool still commits a dot', (
    tester,
  ) async {
    final doc = createBlankSdDocument();
    await tester.pumpWidget(_harness(doc));

    await tester.tapAt(const Offset(50, 50));
    await tester.pump();

    final strokes = doc.root.descendantElements.where(
      (e) => e.strokeId != null,
    );
    expect(strokes, hasLength(1));
  });

  testWidgets(
    'drawing with the ink tool never selects/moves an existing block',
    (tester) async {
      // A block sits right where the stroke is drawn — in the select tool
      // this would select-and-drag it; in the ink tool it must be
      // completely ignored (§10: tool determines the gesture, not what's
      // under the pointer).
      final doc = createBlankSdDocument();
      final rect = SdElement(const SdQName('rect'))
        ..setAttribute(const SdQName('x'), '10')
        ..setAttribute(const SdQName('y'), '10')
        ..setAttribute(const SdQName('width'), '50')
        ..setAttribute(const SdQName('height'), '50');
      doc.root.appendChild(rect);
      final selection = SelectionModel();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SigmaCanvas(
              document: doc,
              tool: CanvasTool.ink,
              selection: selection,
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(30, 30));
      await gesture.moveTo(const Offset(40, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(selection.isEmpty, isTrue);
      expect(rect.hasAttribute(const SdQName('transform')), isFalse);
    },
  );

  testWidgets('an ink stroke is undoable', (tester) async {
    final doc = createBlankSdDocument();
    final undoStack = UndoStack();
    await tester.pumpWidget(_harness(doc, undoStack: undoStack));

    bool hasStroke() =>
        doc.root.descendantElements.any((e) => e.strokeId != null);
    expect(hasStroke(), isFalse);

    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(80, 80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(hasStroke(), isTrue);
    expect(undoStack.canUndo, isTrue);
    expect(undoStack.undoDescription, contains('stroke'));

    undoStack.undo();
    expect(hasStroke(), isFalse);

    undoStack.redo();
    expect(hasStroke(), isTrue);
  });

  testWidgets('with no undoStack, a stroke still commits directly', (
    tester,
  ) async {
    final doc = createBlankSdDocument();
    await tester.pumpWidget(_harness(doc));

    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(80, 80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      doc.root.descendantElements.where((e) => e.strokeId != null),
      hasLength(1),
    );
  });

  testWidgets(
    'cancelling a stroke (pointer-cancel) before releasing still commits it',
    (tester) async {
      // onPointerCancel maps to the exact same handler as onPointerUp (see
      // the Listener wiring in build()) — this is already this canvas's
      // existing move/scale/connect behavior, so the ink tool matching it
      // isn't a special case that needed separate handling.
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_harness(doc));

      final gesture = await tester.startGesture(const Offset(20, 20));
      await gesture.moveTo(const Offset(80, 80));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(
        doc.root.descendantElements.where((e) => e.strokeId != null),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a touch pans instead of inking while a stylus is actively down (palm rejection)',
    (tester) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_harness(doc));

      // The stylus goes down first, as if the user is actively writing.
      final stylus = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();

      // While it's still down, a second pointer — the resting palm,
      // registering as an ordinary touch — starts elsewhere and drags.
      final touch = await tester.startGesture(
        const Offset(200, 100),
        kind: PointerDeviceKind.touch,
      );
      await touch.moveTo(const Offset(260, 160));
      await tester.pump();
      await touch.up();
      await tester.pump();

      await stylus.up();
      await tester.pump();

      // Exactly one stroke: the stylus's own (a lone tap, since it never
      // moved). The touch's drag must not have become a second one.
      expect(
        doc.root.descendantElements.where((e) => e.strokeId != null),
        hasLength(1),
      );
    },
  );

  testWidgets('the same touch drag inks normally when no stylus is active', (
    tester,
  ) async {
    final doc = createBlankSdDocument();
    await tester.pumpWidget(_harness(doc));

    final touch = await tester.startGesture(
      const Offset(200, 100),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveTo(const Offset(260, 160));
    await tester.pump();
    await touch.up();
    await tester.pump();

    expect(
      doc.root.descendantElements.where((e) => e.strokeId != null),
      hasLength(1),
    );
  });
}
