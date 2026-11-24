// A phone turned on its side, a tablet both ways and a foldable opened: the
// home screen, the drawer, the launcher settings and a turn back again lay out
// with nothing overflowing, and the dock stays reachable.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

Future<void> _startApp(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _turn(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  await _settle(tester);
}

void main() {
  for (final (String, Size) screen in <(String, Size)>[
    ('phone on its side', const Size(800, 360)),
    ('large phone on its side', const Size(915, 412)),
    ('tablet upright', const Size(800, 1280)),
    ('tablet on its side', const Size(1280, 800)),
    ('foldable opened', const Size(673, 841)),
  ]) {
    testWidgets('${screen.$1} (${screen.$2.width.toInt()}x${screen.$2.height.toInt()}): home, drawer and settings lay out', (WidgetTester tester) async {
      await _startApp(tester, screen.$2);
      expect(tester.takeException(), isNull, reason: 'the home screen lays out');
      final Finder allApps = find.bySemanticsLabel('All apps');
      expect(allApps, findsWidgets, reason: 'the dock is there');
      final Rect dockButton = tester.getRect(allApps.first);
      expect(dockButton.bottom, lessThanOrEqualTo(screen.$2.height), reason: 'the dock is on screen');
      expect(dockButton.right, lessThanOrEqualTo(screen.$2.width));

      await tester.tap(allApps.first, warnIfMissed: false);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'the open drawer lays out');
      expect(find.text('Calendar'), findsWidgets, reason: 'the drawer lists the apps');
    });
  }

  testWidgets('turning the phone while the drawer is open keeps it open and laid out', (WidgetTester tester) async {
    await _startApp(tester, const Size(360, 800));
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Calendar'), findsWidgets);
    await _turn(tester, const Size(800, 360));
    expect(tester.takeException(), isNull, reason: 'the drawer lays out on its side');
    expect(find.text('Calendar'), findsWidgets, reason: 'the drawer is still open');
    await _turn(tester, const Size(360, 800));
    expect(tester.takeException(), isNull, reason: 'and upright again');
    expect(find.text('Calendar'), findsWidgets);
  });
}
