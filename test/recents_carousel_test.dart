// Dev Launcher's Recents looks and works like a phone's Recents: a row of
// large app cards, newest first, scrolled sideways; swipe a card up to close
// it, tap it to open the app, and "Clear all" after the last card.
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter/widgets.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

const Size _phone = Size(360, 760);

Future<void> _openRecents(WidgetTester tester, List<String> opened) async {
  tester.view.physicalSize = _phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // The sides are saved on the device, which other test files share and
    // change: each test starts from the defaults.
    await LauncherStore.instance.setIndexSide(IndexSide.device);
    await LauncherStore.instance.setRecentsSide(RecentsSide.device);
    await LauncherStore.instance.clearRecents();
    for (final String package in opened) {
      await LauncherStore.instance.open(package);
    }
  });
  await _settle(tester);
  await tester.tap(find.bySemanticsLabel('Recent apps').first, warnIfMissed: false);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('large cards side by side, newest first', (WidgetTester tester) async {
    await _openRecents(tester, <String>['com.termux', 'com.slack']);
    final Rect slack = tester.getRect(find.bySemanticsLabel('Open Slack'));
    final Rect termux = tester.getRect(find.bySemanticsLabel('Open Termux'));
    expect(slack.left, lessThan(termux.left), reason: 'newest (Slack) first, then sideways');
    expect((slack.top - termux.top).abs(), lessThan(1), reason: 'one row, not a list');
    expect(slack.height, greaterThan(_phone.height * 0.4), reason: 'a large card, like a phone\'s Recents');
    expect(slack.width, greaterThan(_phone.width * 0.5));
  });

  testWidgets('swiping a card up closes it; the others stay', (WidgetTester tester) async {
    await _openRecents(tester, <String>['com.termux', 'com.slack']);
    await tester.fling(find.bySemanticsLabel('Open Slack'), const Offset(0, -300), 1500, warnIfMissed: false);
    await _settle(tester);
    expect(find.bySemanticsLabel('Open Slack'), findsNothing, reason: 'swiped away');
    expect(LauncherStore.instance.current.recents, isNot(contains('com.slack')));
    expect(find.bySemanticsLabel('Open Termux'), findsOneWidget);
  });

  testWidgets('"Clear all" comes after the last card and closes every one', (WidgetTester tester) async {
    await _openRecents(tester, <String>['com.termux', 'com.slack']);
    final Finder clearAll = find.bySemanticsLabel(RegExp('^Clear all'));
    expect(clearAll, findsOneWidget);
    await tester.dragUntilVisible(clearAll, find.bySemanticsLabel('Open Termux'), const Offset(-200, 0));
    expect(tester.getCenter(clearAll).dx, greaterThan(tester.getRect(find.bySemanticsLabel('Open Termux')).right), reason: 'after the last card');
    await tester.tap(clearAll);
    await _settle(tester);
    expect(LauncherStore.instance.current.recents, isEmpty);
    expect(find.bySemanticsLabel(RegExp('^Open (Slack|Termux)')), findsNothing);
  });

  testWidgets('tapping a card opens the app', (WidgetTester tester) async {
    await _openRecents(tester, <String>['com.termux', 'com.slack']);
    // Termux is the second card, partly off screen: scrolled to first, as a
    // finger would.
    await tester.ensureVisible(find.bySemanticsLabel('Open Termux'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Open Termux'), warnIfMissed: false);
    // Opening saves the recent list to a file: real time for it to finish.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await _settle(tester);
    // On a phone Recents then closes behind the app; this test device has
    // no apps to open (a preview), so it says so instead.
    expect(find.textContaining('Preview: on your phone this opens the app'), findsOneWidget);
    expect(LauncherStore.instance.current.recents.first, 'com.termux', reason: 'the app opened leads the list now');
  });
}
