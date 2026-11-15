// Home pressed while the launcher is in front: every launcher closes its
// drawer (and whatever menu is open) and shows the home screen again.
// Android hands that press over as a new intent, with no pause or resume;
// the framework turns it into
// DV.Platform.apps.homePresses, faked here through its binding.
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('Home closes the open drawer', (WidgetTester tester) async {
    int stamp = 0;
    DVNativeBridge.register('apps.homePressedAt', (Object? _) => stamp);
    addTearDown(() => DVNativeBridge.unregister('apps.homePressedAt'));
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
    Future<void> settle() async {
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(find.text('Search apps')).dy < screenHeight / 2;

    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue, reason: 'the apps button opened the drawer');

    // Home while the launcher is in front: Android 10+ hands over the new
    // intent and nothing else, no pause and no resume (seen on an Android 12
    // emulator with Dev Launcher as the default home). The MainActivity tells
    // the app over its system-keys channel.
    stamp = 1234;
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage('home:1234'), (ByteData? _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    expect(drawerOpen(), isFalse, reason: 'Home closed the drawer');

    // And the Recents screen, the same way.
    await tester.tap(find.bySemanticsLabel('Recent apps').first, warnIfMissed: false);
    await settle();
    expect(find.text('recent apps'), findsOneWidget);
    stamp = 5678;
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage('home:5678'), (ByteData? _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    expect(find.text('recent apps'), findsNothing, reason: 'Home closed Recents');
  });
}
