// The Recents button on a phone whose own launcher hosts Recents (HiOS) shows
// nothing while Dev Launcher is the home app. The framework reports such an
// unanswered press (DV.Platform.apps.recentsPresses, faked here through its
// binding); Dev Launcher answers it with its own recent apps: the drawer,
// whose first row is the apps opened last. A second press closes it again.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('an unanswered Recents press opens the drawer; the next closes it', (WidgetTester tester) async {
    int stamp = 0;
    DVNativeBridge.register('apps.recentsPressedAt', (Object? _) => stamp);
    addTearDown(() => DVNativeBridge.unregister('apps.recentsPressedAt'));
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
    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(find.text('Search apps')).dy < screenHeight / 2;
    Future<void> press(int at) async {
      stamp = at;
      // The app started listening on the real event loop (runAsync above),
      // so its poll runs on real time.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    expect(drawerOpen(), isFalse);
    await press(1000);
    expect(drawerOpen(), isTrue, reason: 'Recents showed the launcher\'s own recent apps');
    await press(2000);
    expect(drawerOpen(), isFalse, reason: 'a second press closes them');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
