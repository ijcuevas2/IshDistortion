import 'package:flutter_test/flutter_test.dart';
import 'package:sigmadraw/main.dart';

void main() {
  testWidgets('app shell launches and shows the SigmaDraw title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());

    expect(find.text('SigmaDraw'), findsOneWidget);
  });

  testWidgets('the Pole-Zero tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    // ensureVisible first: the tabbed-panels area's TabBar is scrollable
    // (11 tabs no longer fit the fixed-width sidebar at once — the same
    // overflow shape the Ribbon's own horizontal-scroll fix already
    // addresses elsewhere), so a tab this far along isn't guaranteed to
    // already be on-screen (and a tap at an off-screen coordinate warns,
    // even where it happens not to fail outright).
    await tester.ensureVisible(find.text('Pole-Zero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pole-Zero'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // "Pole-Zero" appears at least as the tab label itself; not
    // findsOneWidget since PoleZeroPanel's own in-body heading (present
    // once its message branch doesn't apply) would be a second match —
    // this only needs to prove the tab switch didn't crash or go blank.
    expect(find.text('Pole-Zero'), findsWidgets);
  });

  testWidgets('the Bode tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.ensureVisible(find.text('Bode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bode'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Same "findsWidgets, not findsOneWidget" reasoning as the Pole-Zero
    // tab above: BodePanel's own in-body heading is a second match once
    // its message branch doesn't apply.
    expect(find.text('Bode'), findsWidgets);
  });

  testWidgets('the Nyquist tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.ensureVisible(find.text('Nyquist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nyquist'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Same "findsWidgets, not findsOneWidget" reasoning as the Pole-Zero/
    // Bode tabs above: NyquistPanel's own in-body heading is a second
    // match once its message branch doesn't apply.
    expect(find.text('Nyquist'), findsWidgets);
  });

  testWidgets('the Spectrogram tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.ensureVisible(find.text('Spectrogram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spectrogram'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Same "findsWidgets, not findsOneWidget" reasoning as the Pole-Zero/
    // Bode/Nyquist tabs above: SpectrogramPanel's own in-body heading is
    // a second match once its message branch doesn't apply.
    expect(find.text('Spectrogram'), findsWidgets);
  });

  testWidgets('the Group Delay tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    // The tabbed-panels area's TabBar is scrollable (11 tabs no longer
    // fit the fixed-width sidebar at once — the same overflow shape the
    // Ribbon's own horizontal-scroll fix already addresses elsewhere),
    // so a tab this far along needs scrolling into view before it can
    // be tapped.
    await tester.ensureVisible(find.text('Group Delay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group Delay'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Group Delay'), findsWidgets);
  });

  testWidgets('the Impulse/Step tab is reachable without error', (
    tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.ensureVisible(find.text('Impulse/Step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impulse/Step'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // ImpulseStepPanel's own in-body heading is "Impulse / Step
    // Response" (with slashes spaced out), not "Impulse/Step" (the
    // tab's own compact label) — so, unlike the other tabs' reachability
    // tests, only the tab label itself matches here; that's still
    // sufficient to prove the tab switch didn't crash or go blank.
    expect(find.text('Impulse/Step'), findsOneWidget);
  });

  testWidgets('the Root Locus tab is reachable without error', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.ensureVisible(find.text('Root Locus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Root Locus'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Root Locus'), findsWidgets);
  });

  testWidgets('the Insert ribbon opens the equation dialog', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.tap(find.text('Insert'));
    await tester.pump();
    // Taps the action's caption label, not its icon — RibbonAction's
    // whole control (icon + label) is one tap target.
    await tester.tap(find.text('New Equation'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Insert Equation'), findsOneWidget);
  });

  testWidgets('the Export ribbon opens the PDF export dialog', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Export to PDF'), findsOneWidget);
    // Doesn't go on to tap the dialog's own Export button: that would
    // invoke the real exportToPdf, which spawns pdflatex via
    // Isolate.run — not reliable from inside a widget test (see
    // ExportPdfDialog.exportPdf's doc comment). The real pipeline is
    // fully covered in sd_export's own plain (non-widget) tests, and
    // this dialog's own reaction to success/failure is covered in
    // sd_ui's export_pdf_dialog_test.dart via an injected fake.
  });

  testWidgets('the Export ribbon opens the EPS export dialog', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.tap(find.text('EPS'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Export to EPS'), findsOneWidget);
    // Same reasoning as the PDF dialog test above for not going on to
    // tap Export: exportToEps's real pdflatex+pdftops calls need
    // Isolate.run, not reliable from inside a widget test (see
    // ExportEpsDialog.exportEps's doc comment) — covered instead
    // directly in sd_export's eps_export_test.dart and via an injected
    // fake in sd_ui's export_eps_dialog_test.dart.
  });

  testWidgets('the Export ribbon opens the PNG export dialog', (tester) async {
    await tester.pumpWidget(const SigmaDrawApp());

    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Export to PNG'), findsOneWidget);
    // Same reasoning as the PDF dialog test above for not going on to
    // tap Export: exportToPng's real dart:ui rendering calls need
    // tester.runAsync to complete inside a widget test (see
    // ExportPngDialog's own doc comment), which doesn't mix with a
    // simulated tester.tap — covered instead directly in sd_export's
    // png_export_test.dart and via an injected fake in sd_ui's
    // export_png_dialog_test.dart.
  });
}
