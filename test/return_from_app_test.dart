// Open an app from the drawer, come back: every launcher shows its home
// screen again, not the drawer you left from. On Appetize Android 12 the
// drawer was still open after Back from Clock: Android does not always stop
// the home app before it comes back (only pause and resume reach it), so
// closing the drawer only when the app was "backgrounded" missed it.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('back from an app opened in the drawer, the drawer is closed', (WidgetTester tester) async {
    final Map<String, String> installed = <String, String>{'com.android.calendar': 'Calendar', 'com.termux': 'Termux'};
    final List<String> opened = <String>[];
    DVNativeBridge.register('apps.list', (Object? _) => <Object?>[for (final MapEntry<String, String> app in installed.entries) <String, Object?>{'package': app.key, 'label': app.value}]);
    DVNativeBridge.register('apps.icon', (Object? _) => Uint8List(0));
    DVNativeBridge.register('apps.open', (Object? arguments) {
      opened.add('${(arguments as Map)['package']}');
      return true;
    });
    DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
    DVNativeBridge.register('apps.defaultFor', (Object? _) => null);
    addTearDown(() {
      for (final String name in <String>['apps.list', 'apps.icon', 'apps.open', 'apps.isDefaultLauncher', 'apps.defaultFor']) {
        DVNativeBridge.unregister(name);
      }
    });
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(find.text('Search apps')).dy < screenHeight / 2;

    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue);
    await tester.tap(find.text('Calendar').last, warnIfMissed: false);
    await settle();
    expect(opened, <String>['com.android.calendar'], reason: 'the tap opened Calendar');

    // Calendar covers the launcher and goes away again: only pause and
    // resume reach it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
    expect(drawerOpen(), isFalse, reason: 'back on the home screen, not in the drawer');
  });
}
