// On a phone the first frame can be built before Android has told Flutter
// how big the screen is: its height is 0. Dev Launcher 0.1.8 remembered that
// first height as "where the closed drawer sits", so everything that closed
// the drawer from outside a tap (Home, leaving for an app) put it at 0, which
// is fully open, and let go of Back: the drawer stayed open and Back did
// nothing. Seen on an Android 12 emulator with Dev Launcher as the home app.
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('Home closes the drawer and Back still works when the first frame had no size', (WidgetTester tester) async {
    DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
    addTearDown(() => DVNativeBridge.unregister('apps.homePressedAt'));
    tester.view.physicalSize = Size.zero;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      // The home screen is built, and starts listening, with no size yet.
      for (int frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // Android reports the screen.
      tester.view.physicalSize = const Size(1080, 2400);
      for (int frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    Future<void> settle() async {
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pressHome(int at) async {
      await tester.runAsync(() async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage('home:$at'), (ByteData? _) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle();
    }

    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(find.text('Search apps')).dy < screenHeight / 2;

    expect(drawerOpen(), isFalse, reason: 'the drawer starts closed');
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue);

    await pressHome(1000);
    expect(drawerOpen(), isFalse, reason: 'Home closed the drawer');

    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue);
    await pressHome(2000);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue);
    final bool handled = await tester.binding.handlePopRoute();
    await settle();
    expect(handled, isTrue, reason: 'Back is still Dev Launcher\'s after Home');
    expect(drawerOpen(), isFalse, reason: 'Back closed the drawer');
  });
}
