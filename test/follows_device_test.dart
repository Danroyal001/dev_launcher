// The home screen follows the phone it is on: the clock uses the phone's
// 12/24-hour setting and its language for the date; the dock's Recents
// button sits on the side the phone's own navigation bar puts Recents, with
// that bar's Recents glyph (three lines on Tecno, Xiaomi; three bars on
// Samsung), never a square; a setting overrides the side.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';

final DateTime _evening = DateTime(2026, 11, 15, 18, 49);

Future<void> _startApp(WidgetTester tester, {bool use24 = false, Locale locale = const Locale('en', 'US')}) async {
  tester.view.physicalSize = const Size(360, 760) * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.alwaysUse24HourFormatTestValue = use24;
  tester.platformDispatcher.localeTestValue = locale;
  tester.platformDispatcher.localesTestValue = <Locale>[locale];
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
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
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the clock', () {
    test('12-hour when the phone says so, 24-hour when it says so', () {
      expect(clockText(_evening, use24: false, locale: 'en_US'), '6:49 PM');
      expect(clockText(_evening, use24: true, locale: 'en_US'), '18:49');
      expect(clockText(DateTime(2026, 11, 15, 7, 5), use24: true, locale: 'en_GB'), '07:05');
      expect(clockText(DateTime(2026, 11, 15, 0, 5), use24: false, locale: 'en_US'), '12:05 AM');
    });

    test('the date line is in the phone\'s language and order', () {
      expect(dayLine(_evening, locale: 'en_US'), 'Sun, Nov 15');
      expect(dayLine(_evening, locale: 'en_GB'), 'Sun 15 Nov');
      expect(dayLine(_evening, locale: 'fr_FR'), contains('nov'));
      expect(dayLine(_evening, locale: 'ar'), isNot(contains('Nov')), reason: 'Arabic month names');
    });

    test('a language intl does not know falls back to its base language, then to English', () {
      expect(dayLine(_evening, locale: 'en_NG'), contains('Nov'));
      expect(dayLine(_evening, locale: 'xx_YY'), contains('Nov'));
    });

    testWidgets('on a 12-hour phone the home screen shows AM/PM', (WidgetTester tester) async {
      await _startApp(tester, use24: false);
      expect(find.textContaining(RegExp(r'^\d{1,2}:\d\d [AP]M$')), findsOneWidget, reason: '12-hour clock');
    });

    testWidgets('on a 24-hour phone the home screen shows no AM/PM', (WidgetTester tester) async {
      await _startApp(tester, use24: true);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget, reason: '24-hour clock');
    });
  });

  group('the Recents button follows the navigation bar', () {
    test('Tecno, Infinix and itel (HiOS/XOS): Recents on the left, three lines', () {
      final NavBarStyle style = navBarStyleFor(<String>['com.transsion.camera', 'com.android.chrome']);
      expect(style.recentsSide, RecentsSide.left);
      expect(style.glyph, RecentsGlyph.lines);
    });

    test('Samsung: Recents on the left, three bars', () {
      final NavBarStyle style = navBarStyleFor(<String>['com.sec.android.app.camera', 'com.samsung.android.messaging']);
      expect(style.recentsSide, RecentsSide.left);
      expect(style.glyph, RecentsGlyph.bars);
    });

    test('Xiaomi, Redmi, POCO (MIUI/HyperOS): Recents on the left, three lines', () {
      expect(navBarStyleFor(<String>['com.miui.gallery']).recentsSide, RecentsSide.left);
    });

    test('any other phone: the Android default, Recents on the right, and still never a square', () {
      final NavBarStyle style = navBarStyleFor(<String>['com.google.android.dialer']);
      expect(style.recentsSide, RecentsSide.right);
      expect(style.glyph, RecentsGlyph.lines);
    });

    test('the setting wins over the phone: left or right; "follow device" uses the phone', () {
      final NavBarStyle tecno = navBarStyleFor(<String>['com.transsion.camera']);
      expect(recentsSideFor(RecentsSide.device, tecno), RecentsSide.left);
      expect(recentsSideFor(RecentsSide.right, tecno), RecentsSide.right);
      expect(recentsSideFor(RecentsSide.left, navBarStyleFor(const <String>[])), RecentsSide.left);
    });

    test('the setting is saved with the layout, "follow device" when never set', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['com.termux'], recentsSide: RecentsSide.left);
      expect(LauncherLayout.decode(layout.encode()).recentsSide, RecentsSide.left);
      expect(LauncherLayout.decode('{"home":[],"dock":[]}').recentsSide, RecentsSide.device);
      expect(LauncherLayout.decode('["com.termux"]').recentsSide, RecentsSide.device);
    });

    testWidgets('no square glyph anywhere on the home screen; the Recents button follows the setting', (WidgetTester tester) async {
      await _startApp(tester);
      for (final String square in <String>['□', '■', '▢', '◻', '☐', '⋮⋮']) {
        expect(find.text(square), findsNothing, reason: 'no "$square" glyph');
      }
      final Finder recents = find.bySemanticsLabel('Recent apps');
      final Finder apps = find.bySemanticsLabel('All apps');
      expect(recents, findsOneWidget);
      // The test device lists the example apps (no OEM): Android's default.
      expect(tester.getCenter(recents).dx, greaterThan(tester.getCenter(apps.first).dx), reason: 'Recents on the right by default');

      await tester.runAsync(() => LauncherStore.instance.setRecentsSide(RecentsSide.left));
      await _settle(tester);
      final double leftmost = tester.getCenter(recents).dx;
      expect(leftmost, lessThan(tester.getCenter(apps.first).dx), reason: 'Left: Recents leads the dock');
      // In the first slot: left of every app in the dock (the bottom row).
      final Iterable<double> dockApps = find.bySemanticsLabel(RegExp(r'^(Phone|Messages|Camera|Chrome)$')).evaluate().map((Element element) => tester.getCenter(find.byElementPredicate((Element other) => other == element))).where((Offset at) => at.dy > tester.getCenter(recents).dy - 30 && at.dy < tester.getCenter(recents).dy + 30).map((Offset at) => at.dx);
      for (final double x in dockApps) {
        expect(leftmost, lessThan(x), reason: 'in the first slot');
      }

      await tester.runAsync(() => LauncherStore.instance.setRecentsSide(RecentsSide.device));
      await _settle(tester);
      expect(tester.getCenter(recents).dx, greaterThan(tester.getCenter(apps.first).dx));
    });

    testWidgets('the setting is on the Recents settings screen, three choices with names', (WidgetTester tester) async {
      await _startApp(tester);
      await tester.tap(find.bySemanticsLabel('Recent apps'));
      await _settle(tester);
      await tester.tap(find.text('Recents button settings'), warnIfMissed: false);
      await _settle(tester);
      for (final String choice in <String>['Follow device', 'Left', 'Right']) {
        expect(find.bySemanticsLabel(RegExp('^Recents button: $choice')), findsOneWidget, reason: choice);
      }
      await tester.tap(find.bySemanticsLabel(RegExp('^Recents button: Left')));
      await _settle(tester);
      expect(LauncherStore.instance.current.layout.recentsSide, RecentsSide.left);
      await tester.runAsync(() => LauncherStore.instance.setRecentsSide(RecentsSide.device));
    });
  });
}
