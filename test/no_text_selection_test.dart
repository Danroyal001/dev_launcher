// A home screen is not a document: a long press on a label is "more about
// this app", never "select this text". No launcher screen has a selection
// area (@DVPage(selectable: false) on every page); the search and command
// fields still take typing, and every control keeps its name.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('a long press on a heading or an app label selects nothing, on every screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      for (int frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    Future<void> settle() async {
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> longPressSelectsNothing(Finder text, String screen) async {
      expect(text, findsWidgets, reason: screen);
      await tester.longPress(text.first, warnIfMissed: false);
      await settle();
      expect(find.byType(SelectableRegion), findsNothing, reason: '$screen: no selection area');
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing, reason: '$screen: no copy menu');
      expect(find.byType(TextSelectionToolbar), findsNothing, reason: '$screen: no copy menu');
    }

    await longPressSelectsNothing(find.textContaining(' apps'), 'home');

    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    await longPressSelectsNothing(find.textContaining('all apps'), 'drawer');
    await longPressSelectsNothing(find.text('Termux'), 'drawer app label');
    // Long press on an app opened its menu; close it.
    await tester.tap(find.text('close'), warnIfMissed: false);
    await settle();

    // The search field still takes typing.
    await tester.tap(find.text('Search apps'), warnIfMissed: false);
    await settle();
    tester.testTextInput.enterText('slack');
    await settle();
    expect(find.text('Slack'), findsWidgets);
    expect(find.text('WhatsApp'), findsNothing, reason: 'the list narrowed to what was typed');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle();

    await tester.tap(find.bySemanticsLabel('Recent apps').first, warnIfMissed: false);
    await settle();
    await longPressSelectsNothing(find.text('recent apps'), 'recents');
    await tester.tap(find.text('Recents button settings'), warnIfMissed: false);
    await settle();
    await longPressSelectsNothing(find.text('recents settings'), 'recents settings');
    await longPressSelectsNothing(find.textContaining('recents diagnostics'), 'diagnostics');
    // Names stay: the controls are still found by their labels.
    expect(find.bySemanticsLabel(RegExp('back')), findsWidgets);
    expect(find.byTooltip('Empty the list of signals'), findsWidgets);
  });
}
