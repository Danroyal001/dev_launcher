// Dev Launcher's own Recents: the apps opened last, as cards, each opened
// with a tap and removed from the list with its own control. A third-party
// home app can never be the phone's Recents (only the system's or the phone
// maker's launcher can), so on a phone whose Recents shows nothing over
// another home app (HiOS) this is the screen the person has. It opens from
// the Recents button in the dock, a swipe left on the home screen, and the
// system's Recents press when the phone reports one; Back closes it.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

Future<void> startApp(WidgetTester tester) async {
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
}

Future<void> settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('removing one app from the recents keeps the order of the rest', () {
    expect(forgetRecent(<String>['com.whatsapp', 'com.termux', 'com.slack'], 'com.termux'), <String>['com.whatsapp', 'com.slack']);
    expect(forgetRecent(<String>['com.whatsapp'], 'com.gone'), <String>['com.whatsapp']);
  });

  testWidgets('the dock\'s Recents button shows the recent apps as cards; remove takes one out; Back closes it', (WidgetTester tester) async {
    await startApp(tester);
    await tester.runAsync(() async {
      await LauncherStore.instance.open('com.termux');
      await LauncherStore.instance.open('com.slack');
    });
    await settle(tester);

    final Finder button = find.bySemanticsLabel('Recent apps');
    expect(button, findsWidgets, reason: 'the dock has a Recents button');
    expect(find.text('recent apps'), findsNothing);
    await tester.tap(button.first, warnIfMissed: false);
    await settle(tester);
    expect(find.text('recent apps'), findsOneWidget, reason: 'the Recents screen is up');
    expect(find.bySemanticsLabel('Open Slack'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Termux'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove Termux from recent apps'), warnIfMissed: false);
    await settle(tester);
    expect(find.bySemanticsLabel('Open Termux'), findsNothing, reason: 'removed from the list');
    expect(LauncherStore.instance.current.recents, isNot(contains('com.termux')));
    expect(find.bySemanticsLabel('Open Slack'), findsOneWidget);

    final bool handled = await tester.binding.handlePopRoute();
    await settle(tester);
    expect(handled, isTrue);
    expect(find.text('recent apps'), findsNothing, reason: 'Back closed the Recents screen');
  });

  testWidgets('a swipe left on the home screen opens Recents', (WidgetTester tester) async {
    await startApp(tester);
    await tester.flingFrom(const Offset(350, 400), const Offset(-300, 0), 1500);
    await settle(tester);
    expect(find.text('recent apps'), findsOneWidget);
  });

  testWidgets('the system\'s Recents press, when the phone reports it, opens our Recents', (WidgetTester tester) async {
    DVNativeBridge.register('apps.recentsPressedAt', (Object? _) => 0);
    addTearDown(() => DVNativeBridge.unregister('apps.recentsPressedAt'));
    await startApp(tester);
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage('recents:500'), (ByteData? _) {});
      await Future<void>.delayed(const Duration(milliseconds: 900));
    });
    await settle(tester);
    expect(find.text('recent apps'), findsOneWidget);
  });
}
