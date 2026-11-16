// The letter index follows the phone's reading direction (right, or left on a
// right-to-left phone) unless the person picks a side in the drawer's
// settings: Follow device, Left or Right.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

const Size _phone = Size(360, 640);

Future<void> _openDrawer(WidgetTester tester, {Locale locale = const Locale('en', 'US')}) async {
  tester.platformDispatcher.localeTestValue = locale;
  tester.platformDispatcher.localesTestValue = <Locale>[locale];
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
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
  });
  await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _indexX(WidgetTester tester) => tester.getCenter(find.bySemanticsLabel(RegExp(r'^Jump to C\b'))).dx;

void main() {
  test('the side is saved with the layout, "follow device" when never set', () {
    const LauncherLayout layout = LauncherLayout(indexSide: IndexSide.left);
    expect(LauncherLayout.decode(layout.encode()).indexSide, IndexSide.left);
    expect(LauncherLayout.decode('{"home":[],"dock":[]}').indexSide, IndexSide.device);
  });

  test('follow device: right, or left on a right-to-left phone; a chosen side wins', () {
    expect(indexOnLeft(IndexSide.device, rightToLeft: false), isFalse);
    expect(indexOnLeft(IndexSide.device, rightToLeft: true), isTrue);
    expect(indexOnLeft(IndexSide.left, rightToLeft: false), isTrue);
    expect(indexOnLeft(IndexSide.right, rightToLeft: true), isFalse);
  });

  testWidgets('Left and Right move the index; Follow device puts it back', (WidgetTester tester) async {
    await _openDrawer(tester);
    expect(_indexX(tester), greaterThan(_phone.width - 40));
    await tester.runAsync(() => LauncherStore.instance.setIndexSide(IndexSide.left));
    await _settle(tester);
    expect(_indexX(tester), lessThan(40));
    await tester.runAsync(() => LauncherStore.instance.setIndexSide(IndexSide.device));
    await _settle(tester);
    expect(_indexX(tester), greaterThan(_phone.width - 40));
  });

  testWidgets('on an Arabic phone, Right still puts it on the right', (WidgetTester tester) async {
    await _openDrawer(tester, locale: const Locale('ar'));
    expect(_indexX(tester), lessThan(40));
    await tester.runAsync(() => LauncherStore.instance.setIndexSide(IndexSide.right));
    await _settle(tester);
    expect(_indexX(tester), greaterThan(_phone.width - 40));
    await tester.runAsync(() => LauncherStore.instance.setIndexSide(IndexSide.device));
  });

  testWidgets('the drawer has the setting: three named choices', (WidgetTester tester) async {
    await _openDrawer(tester);
    await tester.tap(find.bySemanticsLabel('Drawer settings'));
    await _settle(tester);
    for (final String choice in <String>['Follow device', 'Left', 'Right']) {
      expect(find.bySemanticsLabel(RegExp('^Letter index: $choice')), findsOneWidget, reason: choice);
    }
    await tester.tap(find.bySemanticsLabel(RegExp('^Letter index: Left')));
    await _settle(tester);
    expect(LauncherStore.instance.current.layout.indexSide, IndexSide.left);
    await tester.runAsync(() => LauncherStore.instance.setIndexSide(IndexSide.device));
  });
}
