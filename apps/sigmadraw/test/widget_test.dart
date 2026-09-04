import 'package:flutter_test/flutter_test.dart';
import 'package:sigmadraw/main.dart';

void main() {
  testWidgets('app shell launches and shows the SigmaDraw title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SigmaDrawApp());

    expect(find.text('SigmaDraw'), findsOneWidget);
  });
}
