import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_latex/sd_latex.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  group('ProblemsPanel', () {
    testWidgets('shows "no problems" for an empty document', (tester) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(ProblemsPanel(document: doc)));
      expect(find.text('No problems found.'), findsOneWidget);
    });

    testWidgets('lists an unconnected-port warning for a lone placed block', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(gain.instantiate(instanceId: 'g1'));
      await tester.pumpWidget(_wrap(ProblemsPanel(document: doc)));
      await tester.pump();
      expect(find.textContaining('Unconnected'), findsWidgets);
    });

    testWidgets('tapping an issue selects its block', (tester) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(gain.instantiate(instanceId: 'g1'));
      final selection = SelectionModel();
      await tester.pumpWidget(
        _wrap(ProblemsPanel(document: doc, selection: selection)),
      );
      await tester.pump();

      await tester.tap(find.textContaining('Unconnected').first);
      await tester.pump();

      expect(selection.selected.single.blockId, 'g1');
    });

    testWidgets('updates live when the document changes', (tester) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(ProblemsPanel(document: doc)));
      expect(find.text('No problems found.'), findsOneWidget);

      doc.root.appendChild(gain.instantiate(instanceId: 'g1'));
      await tester.pump();

      expect(find.text('No problems found.'), findsNothing);
    });
  });

  group('TransferFunctionPanel', () {
    testWidgets('prompts for source/sink when neither is present', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(TransferFunctionPanel(document: doc)));
      expect(find.textContaining('Place a "source"'), findsOneWidget);
    });

    testWidgets('shows H(z) for a simple source -> gain -> sink chain', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(
        gain.instantiate(instanceId: 'g1', params: {'gain': 2.0}, x: 100, y: 0),
      );
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 200, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'g1:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'g1:out1'
          ..edgeTo = 'snk:in1',
      );

      await tester.pumpWidget(_wrap(TransferFunctionPanel(document: doc)));
      await tester.pump();

      // Rendered as real typeset math (LatexLabel), not a plain Text widget
      // carrying the literal string — assert on what was actually computed
      // and handed to the renderer, not on glyph-rendering internals.
      final label = tester.widget<LatexLabel>(find.byType(LatexLabel));
      expect(label.tex, 'H(z) = 2');
    });

    testWidgets('reports an algebraic loop instead of a bogus H(z)', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(gain.instantiate(instanceId: 'a', x: 0, y: 0));
      doc.root.appendChild(gain.instantiate(instanceId: 'b', x: 100, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'a:out1'
          ..edgeTo = 'b:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'b:out1'
          ..edgeTo = 'a:in1',
      );

      await tester.pumpWidget(_wrap(TransferFunctionPanel(document: doc)));
      await tester.pump();

      expect(find.textContaining('algebraic'), findsOneWidget);
    });
  });

  group('PoleZeroPanel', () {
    testWidgets('prompts for source/sink when neither is present', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(PoleZeroPanel(document: doc)));
      expect(find.textContaining('Place a "source"'), findsOneWidget);
    });

    testWidgets('reports an algebraic loop instead of a bogus plot', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(gain.instantiate(instanceId: 'a', x: 0, y: 0));
      doc.root.appendChild(gain.instantiate(instanceId: 'b', x: 100, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'a:out1'
          ..edgeTo = 'b:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'b:out1'
          ..edgeTo = 'a:in1',
      );

      await tester.pumpWidget(_wrap(PoleZeroPanel(document: doc)));
      await tester.pump();

      expect(find.textContaining('algebraic'), findsOneWidget);
    });

    testWidgets('a pure gain chain plots as stable with no poles or zeros', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(
        gain.instantiate(instanceId: 'g1', params: {'gain': 2.0}, x: 100, y: 0),
      );
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 200, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'g1:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'g1:out1'
          ..edgeTo = 'snk:in1',
      );

      await tester.pumpWidget(_wrap(PoleZeroPanel(document: doc)));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('Stable'), findsOneWidget);
    });

    testWidgets(
      'a delay-only chain (a pole at the origin) still plots as stable',
      (tester) async {
        final doc = createBlankSdDocument();
        doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
        doc.root.appendChild(delay.instantiate(instanceId: 'd1', x: 100, y: 0));
        doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 200, y: 0));
        doc.root.appendChild(
          SdElement(const SdQName('path'))
            ..edgeId = 'e1'
            ..edgeFrom = 'src:out1'
            ..edgeTo = 'd1:in1',
        );
        doc.root.appendChild(
          SdElement(const SdQName('path'))
            ..edgeId = 'e2'
            ..edgeFrom = 'd1:out1'
            ..edgeTo = 'snk:in1',
        );

        await tester.pumpWidget(_wrap(PoleZeroPanel(document: doc)));
        await tester.pump();

        expect(find.textContaining('Stable'), findsOneWidget);
      },
    );

    testWidgets('updates live when the document changes', (tester) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(PoleZeroPanel(document: doc)));
      expect(find.textContaining('Place a "source"'), findsOneWidget);

      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 100, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'snk:in1',
      );
      await tester.pump();

      expect(find.textContaining('Place a "source"'), findsNothing);
      expect(find.textContaining('Stable'), findsOneWidget);
    });
  });

  group('BodePanel', () {
    testWidgets('prompts for source/sink when neither is present', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(BodePanel(document: doc)));
      expect(find.textContaining('Place a "source"'), findsOneWidget);
    });

    testWidgets('reports an algebraic loop instead of a bogus plot', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(gain.instantiate(instanceId: 'a', x: 0, y: 0));
      doc.root.appendChild(gain.instantiate(instanceId: 'b', x: 100, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'a:out1'
          ..edgeTo = 'b:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'b:out1'
          ..edgeTo = 'a:in1',
      );

      await tester.pumpWidget(_wrap(BodePanel(document: doc)));
      await tester.pump();

      expect(find.textContaining('algebraic'), findsOneWidget);
    });

    testWidgets('a pure gain chain plots without error', (tester) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(
        gain.instantiate(instanceId: 'g1', params: {'gain': 2.0}, x: 100, y: 0),
      );
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 200, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'g1:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'g1:out1'
          ..edgeTo = 'snk:in1',
      );

      await tester.pumpWidget(_wrap(BodePanel(document: doc)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('Nyquist'), findsOneWidget);
    });

    testWidgets('an unresolved symbolic gain shows its own message', (
      tester,
    ) async {
      final doc = createBlankSdDocument();
      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(
        gain.instantiate(instanceId: 'g1', params: {'gain': 'k'}, x: 100, y: 0),
      );
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 200, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'g1:in1',
      );
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e2'
          ..edgeFrom = 'g1:out1'
          ..edgeTo = 'snk:in1',
      );

      await tester.pumpWidget(_wrap(BodePanel(document: doc)));
      await tester.pump();

      expect(find.textContaining('unresolved'), findsOneWidget);
    });

    testWidgets('updates live when the document changes', (tester) async {
      final doc = createBlankSdDocument();
      await tester.pumpWidget(_wrap(BodePanel(document: doc)));
      expect(find.textContaining('Place a "source"'), findsOneWidget);

      doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
      doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 100, y: 0));
      doc.root.appendChild(
        SdElement(const SdQName('path'))
          ..edgeId = 'e1'
          ..edgeFrom = 'src:out1'
          ..edgeTo = 'snk:in1',
      );
      await tester.pump();

      expect(find.textContaining('Place a "source"'), findsNothing);
      expect(find.textContaining('Nyquist'), findsOneWidget);
    });
  });
}
