// Owner, 21 Nov (Tecno, 0.1.12): a big gap between the dock and the
// navigation bar, and between the drawer's last row and it. The page sits in
// Flutter's SafeArea (Dartvel's page shell); the launcher adds no inset
// arithmetic of its own, so the dock sits just above the navigation bar and
// the letter index ends inside the safe area.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';

// The owner's Tecno: 720 x 1600 px at 2x, a 35 dp status bar and a 40 dp
// three-button navigation bar.
const Size _screen = Size(360, 800);
const double _statusBar = 35;
const double _navBar = 40;
const double _safeBottom = 800 - _navBar;

Future<void> _start(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: _statusBar * 2, bottom: _navBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar * 2, bottom: _navBar * 2);
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await LauncherStore.instance.setIndexSide(IndexSide.device);
    await LauncherStore.instance.setRecentsSide(RecentsSide.device);
  });
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Rect _circleOf(WidgetTester tester, Type glyph) {
  final Finder circle = find.ancestor(of: find.byType(glyph).first, matching: find.byType(DecoratedBox)).first;
  return tester.getRect(circle);
}

void main() {
  testWidgets('the dock sits just above the navigation bar, with no extra gap', (WidgetTester tester) async {
    await _start(tester);
    final Rect apps = _circleOf(tester, AppsButtonIcon);
    expect(apps.bottom, lessThanOrEqualTo(_safeBottom), reason: 'the dock is above the navigation bar: $apps');
    // The slot's inset (6) round the button, the dock's own padding (6) and
    // one small margin under the dock (8): nothing more.
    expect(_safeBottom - apps.bottom, lessThanOrEqualTo(22), reason: 'gap under the dock button: ${_safeBottom - apps.bottom}');
  });

  testWidgets('the drawer\'s letter index ends inside the safe area, Z included', (WidgetTester tester) async {
    await _start(tester);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    for (int frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final Finder z = find.bySemanticsLabel(RegExp(r'^(Jump to Z\b|Z, no apps)'));
    expect(z, findsOneWidget);
    final Rect letter = tester.getRect(z);
    expect(letter.bottom, lessThanOrEqualTo(_safeBottom), reason: 'Z is above the navigation bar: $letter');
    expect(_safeBottom - letter.bottom, lessThanOrEqualTo(16), reason: 'the index reaches down to the bottom: ${_safeBottom - letter.bottom}');
  });
}
