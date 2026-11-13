// The real app on the smallest phones people use, with the system font made
// large: nothing may overflow or be cut off, on the home screen or in the
// drawer, and the drawer's recent row shows the app just opened.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

Future<void> _startApp(WidgetTester tester, {required Size logical, required double textScale}) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

void main() {
  for (final (Size, double) screen in <(Size, double)>[(const Size(320, 568), 1.0), (const Size(320, 568), 1.3), (const Size(360, 640), 2.0), (const Size(412, 915), 1.3)]) {
    testWidgets('${screen.$1.width.toInt()}x${screen.$1.height.toInt()} at font x${screen.$2}: nothing overflows, home or drawer', (WidgetTester tester) async {
      await _startApp(tester, logical: screen.$1, textScale: screen.$2);
      expect(tester.takeException(), isNull, reason: 'the home screen lays out');

      await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'the open drawer lays out');

      // With a recent row on top too.
      expect(find.text('Calendar'), findsWidgets);
      await tester.tap(find.text('Calendar').last, warnIfMissed: false);
      await _settle(tester);
      expect(find.text('recent'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the drawer with recent apps lays out');
    });
  }

  testWidgets('the app just opened leads the drawer, under "recent"', (WidgetTester tester) async {
    await _startApp(tester, logical: const Size(390, 844), textScale: 1);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);

    // Both are only in the drawer (the home screen shows dev tools). The
    // first tap on each is in the A-Z list, the last one opened leads.
    for (final String app in <String>['Chrome', 'Camera']) {
      await tester.tap(find.text(app).last, warnIfMissed: false);
      await _settle(tester);
    }
    expect(find.text('recent'), findsOneWidget);
    final double recentTop = tester.getTopLeft(find.text('recent')).dy;
    Offset inRecentRow(String app) => find.text(app).evaluate().map((Element element) => tester.getTopLeft(find.byElementPredicate((Element each) => each == element))).firstWhere((Offset at) => at.dy > recentTop && at.dy < recentTop + 140, orElse: () => const Offset(-1, -1));
    expect(inRecentRow('Camera').dy, greaterThan(0), reason: 'Camera sits in the recent row');
    expect(inRecentRow('Chrome').dy, greaterThan(0), reason: 'Chrome sits in the recent row');
    expect(inRecentRow('Camera').dx, lessThan(inRecentRow('Chrome').dx), reason: 'the newest comes first');
    expect(tester.takeException(), isNull);
  });
}
