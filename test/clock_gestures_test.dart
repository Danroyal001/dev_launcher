// The clock is how the person reaches the launcher settings without the drawer:
// a long press opens them (it also has a tooltip saying so, which must not take
// the press for itself).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('a long press on the clock opens the launcher settings', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      for (int frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(find.text('launcher settings'), findsNothing);
    await tester.longPress(find.bySemanticsLabel(RegExp(r'^Dev Launcher, ')).first, warnIfMissed: false);
    for (int frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('launcher settings'), findsOneWidget);
  });
}
