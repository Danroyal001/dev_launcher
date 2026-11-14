// A long press on an app in the drawer opens its menu (open, pin, info,
// uninstall). Until 0.1.9 the menu's name column had no width inside its row
// and threw while laying out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('long press in the drawer opens the app menu', (WidgetTester tester) async {
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
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    for (int frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.longPress(find.text('Termux').first, warnIfMissed: false);
    for (int frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('uninstall'), findsWidgets);
  });
}
