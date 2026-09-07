import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_ui/sd_ui.dart';

Widget _harness(List<RibbonTab> tabs) => MaterialApp(
  home: Scaffold(body: Ribbon(tabs: tabs)),
);

void main() {
  group('Ribbon', () {
    testWidgets('shows the first tab\'s groups by default', (tester) async {
      await tester.pumpWidget(
        _harness([
          RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(
                title: 'Clipboard',
                actions: [
                  RibbonAction(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          RibbonTab(
            title: 'Insert',
            groups: [
              RibbonGroup(
                title: 'Equation',
                actions: [
                  RibbonAction(
                    icon: Icons.functions,
                    label: 'Insert Eq.',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Insert'), findsOneWidget);
      expect(find.text('Clipboard'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      // Insert's own group/action are not shown until its tab is selected.
      expect(find.text('Equation'), findsNothing);
    });

    testWidgets('tapping a tab switches the visible groups', (tester) async {
      await tester.pumpWidget(
        _harness([
          RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(
                title: 'Clipboard',
                actions: [
                  RibbonAction(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          RibbonTab(
            title: 'Insert',
            groups: [
              RibbonGroup(
                title: 'Equation',
                actions: [
                  RibbonAction(
                    icon: Icons.functions,
                    label: 'Insert Eq.',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ]),
      );

      await tester.tap(find.text('Insert'));
      await tester.pump();

      expect(find.text('Clipboard'), findsNothing);
      expect(find.text('Equation'), findsOneWidget);
    });

    testWidgets('tapping an enabled action invokes its callback', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        _harness([
          RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(
                title: 'Clipboard',
                actions: [
                  RibbonAction(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onPressed: () => tapped++,
                  ),
                ],
              ),
            ],
          ),
        ]),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_copy));
      expect(tapped, 1);
    });

    testWidgets('tapping an action\'s caption label also invokes it', (
      tester,
    ) async {
      // Not just the icon: a real ribbon button's whole control (icon +
      // label) is one tap target.
      var tapped = 0;
      await tester.pumpWidget(
        _harness([
          RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(
                title: 'Clipboard',
                actions: [
                  RibbonAction(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onPressed: () => tapped++,
                  ),
                ],
              ),
            ],
          ),
        ]),
      );

      await tester.tap(find.text('Copy'));
      expect(tapped, 1);
    });

    testWidgets('a disabled action renders as a disabled IconButton', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness([
          const RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(
                title: 'Clipboard',
                actions: [
                  RibbonAction(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onPressed: null,
                  ),
                ],
              ),
            ],
          ),
        ]),
      );

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a group\'s child widget renders alongside its actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness([
          const RibbonTab(
            title: 'Home',
            groups: [
              RibbonGroup(title: 'Tools', child: Text('custom-tool-widget')),
            ],
          ),
        ]),
      );

      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('custom-tool-widget'), findsOneWidget);
    });
  });
}
