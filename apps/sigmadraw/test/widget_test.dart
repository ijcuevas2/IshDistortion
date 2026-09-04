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

    await tester.tap(find.text('Bode'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Same "findsWidgets, not findsOneWidget" reasoning as the Pole-Zero
    // tab above: BodePanel's own in-body heading is a second match once
    // its message branch doesn't apply.
    expect(find.text('Bode'), findsWidgets);
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
}
