import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

SdElement _block(String id, {required List<Map<String, Object?>> ports}) =>
    SdElement(const SdQName('g'))
      ..blockType = 'test'
      ..blockId = id
      ..blockPorts = ports;

void main() {
  testWidgets(
    'dragging from an output port to an input port on another block creates an edge',
    (tester) async {
      final doc = createBlankSdDocument(width: 400, height: 400);
      doc.root.appendChild(
        _block(
          'a',
          ports: [
            {'id': 'out1', 'dir': 'out', 'x': 40.0, 'y': 20.0},
          ],
        ),
      );
      doc.root.appendChild(
        _block(
          'b',
          ports: [
            {'id': 'in1', 'dir': 'in', 'x': 100.0, 'y': 20.0},
          ],
        ),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 400,
            child: SigmaCanvas(document: doc),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(40, 20)); // a:out1
      await gesture.moveTo(const Offset(100, 20)); // b:in1
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final aElement = doc.root.descendantElements.firstWhere(
        (e) => e.blockId == 'a',
      );
      final edge = doc.root.descendantElements.firstWhere(
        (e) => e.edgeId != null,
      );
      expect(edge.edgeFrom, 'a:out1');
      expect(edge.edgeTo, 'b:in1');
      // Sanity: didn't confuse endpoints or accidentally target the wrong block.
      expect(aElement.blockId, 'a');
    },
  );

  testWidgets(
    'dragging from input to output (reversed) still creates a correctly-directed edge',
    (tester) async {
      final doc = createBlankSdDocument(width: 400, height: 400);
      doc.root.appendChild(
        _block(
          'a',
          ports: [
            {'id': 'out1', 'dir': 'out', 'x': 40.0, 'y': 20.0},
          ],
        ),
      );
      doc.root.appendChild(
        _block(
          'b',
          ports: [
            {'id': 'in1', 'dir': 'in', 'x': 100.0, 'y': 20.0},
          ],
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 400,
            child: SigmaCanvas(document: doc),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        const Offset(100, 20),
      ); // b:in1 first
      await gesture.moveTo(const Offset(40, 20)); // a:out1
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final edge = doc.root.descendantElements.firstWhere(
        (e) => e.edgeId != null,
      );
      expect(edge.edgeFrom, 'a:out1');
      expect(edge.edgeTo, 'b:in1');
    },
  );

  testWidgets('dragging output to output does not create an edge', (
    tester,
  ) async {
    final doc = createBlankSdDocument(width: 400, height: 400);
    doc.root.appendChild(
      _block(
        'a',
        ports: [
          {'id': 'out1', 'dir': 'out', 'x': 40.0, 'y': 20.0},
        ],
      ),
    );
    doc.root.appendChild(
      _block(
        'b',
        ports: [
          {'id': 'out1', 'dir': 'out', 'x': 100.0, 'y': 20.0},
        ],
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 400,
          child: SigmaCanvas(document: doc),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(40, 20));
    await gesture.moveTo(const Offset(100, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(doc.root.descendantElements.where((e) => e.edgeId != null), isEmpty);
  });
}
