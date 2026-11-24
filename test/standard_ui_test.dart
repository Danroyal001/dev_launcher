// The standard launcher features as the person meets them, on the owner's
// Tecno size (360 x 800, real status and navigation bars) with Android
// answered by fake bindings: an app's own shortcuts and "hide" in the
// long-press menu, folders, dragging home tiles into a new order, badges,
// the swipe-down / double-tap / pinch gestures, the launcher's settings
// screen, and settings pages and the web in the search.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter/services.dart' show ByteData, StringCodec, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _installed = <String, String>{
  'com.termux': 'Termux',
  'com.android.chrome': 'Chrome',
  'com.whatsapp': 'WhatsApp',
  'com.slack': 'Slack',
  'com.spotify.music': 'Spotify',
  'com.google.android.gm': 'Gmail',
};

final List<String> _asked = <String>[];
final List<Object?> _bridgeCalls = <Object?>[];
String _lockAnswer = 'false';

void _phone() {
  DVNativeBridge.register('apps.list', (Object? _) => <Object?>[for (final MapEntry<String, String> app in _installed.entries) <String, Object?>{'package': app.key, 'label': app.value}]);
  DVNativeBridge.register('apps.icon', (Object? _) => null);
  DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
  DVNativeBridge.register('apps.defaultFor', (Object? _) => null);
  DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
  DVNativeBridge.register('apps.open', (Object? _) => true);
  DVNativeBridge.register('apps.openSystemSettings', (Object? arguments) {
    _bridgeCalls.add('settings ${(arguments! as Map<Object?, Object?>)['page']}');
    return true;
  });
  DVNativeBridge.register('apps.pickWallpaper', (Object? _) {
    _bridgeCalls.add('wallpaper');
    return true;
  });
  DVNativeBridge.register('links.open', (Object? arguments) {
    _bridgeCalls.add('link ${(arguments! as Map<Object?, Object?>)['url']}');
    return true;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', (ByteData? message) async {
    final String question = const StringCodec().decodeMessage(message) ?? '';
    _asked.add(question);
    final String? answer = switch (question) {
      'shortcuts.list:com.whatsapp' => jsonEncode(<Object?>[
          <String, Object?>{'id': 'new_chat', 'label': 'New chat', 'icon': base64Encode(Uint8List.fromList(const <int>[137, 80, 78, 71]))},
          <String, Object?>{'id': 'camera', 'label': 'WhatsApp camera'},
        ]),
      final String other when other.startsWith('shortcuts.list:') => '[]',
      final String other when other.startsWith('shortcuts.open:') => 'true',
      'notifications.expand' => 'true',
      'screen.lock' => _lockAnswer,
      'badges.current' => '{}',
      'badges.isOn' => 'false',
      _ => null,
    };
    return answer == null ? null : const StringCodec().encodeMessage(answer);
  });
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _real(WidgetTester tester, [int turns = 6]) => tester.runAsync(() async {
      for (int turn = 0; turn < turns; turn++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

Future<void> _start(WidgetTester tester, {LauncherLayout layout = const LauncherLayout(dockChosen: false), Size screen = const Size(360, 800)}) async {
  tester.view.physicalSize = screen * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 70, bottom: 80);
  tester.view.viewPadding = const FakeViewPadding(top: 70, bottom: 80);
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await LauncherStore.instance.restore(layout);
  });
  await _settle(tester);
}

Future<void> _systemKey(WidgetTester tester, String message) async {
  await tester.runAsync(() async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage(message), (ByteData? _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await _settle(tester);
}

/// A tap whose handler saves to the phone's files: each step of the write
/// answers on the real event loop and goes on in the fake clock, so the two
/// take turns until it is done.
Future<void> _tapSaving(WidgetTester tester, Finder target) async {
  await tester.tap(target, warnIfMissed: false);
  for (int turn = 0; turn < 12; turn++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await _settle(tester);
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
  await _settle(tester);
}

Future<void> _longPress(WidgetTester tester, String label, {bool onHome = false}) async {
  // On the home screen the first copy; in the open drawer, which is drawn
  // over the home screen, the last.
  await tester.longPress(onHome ? find.text(label).first : find.text(label).last, warnIfMissed: false);
  await _settle(tester);
  await _real(tester);
  await _settle(tester);
}

void main() {
  setUpAll(() {
    DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
    _phone();
  });

  setUp(() {
    _asked.clear();
    _bridgeCalls.clear();
    _lockAnswer = 'false';
  });

  group('the long-press menu', () {
    testWidgets('shows the app\'s own shortcuts, and one opens straight into the app', (WidgetTester tester) async {
      await _start(tester);
      await _openDrawer(tester);
      await tester.enterText(find.bySemanticsLabel('Search apps').first, 'whats');
      await _settle(tester);
      await _longPress(tester, 'WhatsApp');
      expect(_asked, contains('shortcuts.list:com.whatsapp'));
      expect(find.text('New chat'), findsOneWidget);
      expect(find.text('WhatsApp camera'), findsOneWidget);
      await tester.tap(find.text('New chat'), warnIfMissed: false);
      await _settle(tester);
      await _real(tester);
      expect(_asked, contains('shortcuts.open:com.whatsapp:new_chat'));
      expect(find.text('New chat'), findsNothing, reason: 'the menu closed behind the shortcut');
    });

    testWidgets('hide takes an app out of the drawer and its search; settings brings it back', (WidgetTester tester) async {
      await _start(tester);
      await _openDrawer(tester);
      await _longPress(tester, 'Spotify');
      await _tapSaving(tester, find.text('hide'));
      expect(find.text('Spotify'), findsNothing, reason: 'hidden from the A-Z list');
      expect(LauncherStore.instance.current.layout.hidden, <String>['com.spotify.music']);

      await tester.runAsync(() => LauncherStore.instance.hideApp('com.spotify.music', hidden: false));
      await _settle(tester);
      expect(find.text('Spotify'), findsWidgets);
    });
  });

  group('folders', () {
    testWidgets('an app put in a new folder shows as the folder on home; the folder opens with its apps', (WidgetTester tester) async {
      await _start(tester, layout: const LauncherLayout(home: <String>['com.slack', 'com.termux'], dockChosen: false));
      await _longPress(tester, 'Slack', onHome: true);
      await tester.tap(find.text('to folder'), warnIfMissed: false);
      await _settle(tester);
      await _tapSaving(tester, find.text('new folder'));
      final LauncherLayout layout = LauncherStore.instance.current.layout;
      expect(layout.folders.single.apps, <String>['com.slack']);
      expect(layout.home.first, startsWith(folderPrefix));

      await tester.runAsync(() => LauncherStore.instance.putInFolder('com.termux', folderId: layout.folders.single.id));
      await _settle(tester);
      expect(find.bySemanticsLabel(RegExp(r'^Folder Folder, 2 apps')), findsOneWidget);
      await tester.tap(find.text('Folder').first);
      await _settle(tester);
      expect(find.text('Slack'), findsWidgets);
      expect(find.text('Termux'), findsWidgets);
      expect(find.bySemanticsLabel('Folder name'), findsOneWidget, reason: 'it can be renamed in place');
    });
  });

  testWidgets('arrange home: a tile dragged one cell right swaps places with its neighbour', (WidgetTester tester) async {
    await _start(tester, layout: const LauncherLayout(home: <String>['com.termux', 'com.android.chrome', 'com.slack'], dockChosen: false));
    await _longPress(tester, 'Termux', onHome: true);
    await tester.tap(find.text('arrange home'), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Done arranging'), findsOneWidget);
    final Rect termux = tester.getRect(find.text('Termux').first);
    final Rect chrome = tester.getRect(find.text('Chrome').first);
    final TestGesture drag = await tester.startGesture(termux.center);
    for (int step = 1; step <= 10; step++) {
      await drag.moveBy(Offset((chrome.center.dx - termux.center.dx) / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await _real(tester);
    await _settle(tester);
    expect(LauncherStore.instance.current.layout.home, <String>['com.android.chrome', 'com.termux', 'com.slack']);
    await tester.tap(find.text('Done arranging'), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Done arranging'), findsNothing);
  });

  testWidgets('a badge shows on an app with notifications, and is read out', (WidgetTester tester) async {
    await _start(tester, layout: const LauncherLayout(home: <String>['com.whatsapp'], dockChosen: false));
    await _systemKey(tester, 'badges:10:${jsonEncode(<String, int>{'com.whatsapp': 3})}');
    expect(find.bySemanticsLabel(RegExp(r'^WhatsApp, 3 notifications')), findsWidgets);
    await _systemKey(tester, 'badges:11:{}');
    expect(find.bySemanticsLabel(RegExp(r'^WhatsApp, 3 notifications')), findsNothing);
  });

  group('gestures on the home screen', () {
    testWidgets('a swipe down pulls the notification shade down', (WidgetTester tester) async {
      await _start(tester);
      await tester.flingFrom(const Offset(180, 330), const Offset(0, 250), 1500);
      await _settle(tester);
      await _real(tester);
      expect(_asked, contains('notifications.expand'));
    });

    testWidgets('a double tap on the clock locks the screen, or says how to let it', (WidgetTester tester) async {
      await _start(tester);
      final Finder clock = find.bySemanticsLabel(RegExp(r'^Dev Launcher, ')).first;
      await tester.tap(clock, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(clock, warnIfMissed: false);
      await _settle(tester);
      await _real(tester);
      await _settle(tester);
      expect(_asked, contains('screen.lock'));
      expect(find.textContaining('Accessibility'), findsWidgets, reason: 'the lock needs the opt-in service: the person is told where to turn it on');
    });

    testWidgets('a pinch opens the launcher settings', (WidgetTester tester) async {
      await _start(tester);
      final TestGesture first = await tester.startGesture(const Offset(100, 380), pointer: 7);
      final TestGesture second = await tester.startGesture(const Offset(260, 380), pointer: 8);
      for (int step = 0; step < 10; step++) {
        await first.moveBy(const Offset(6, 0));
        await second.moveBy(const Offset(-6, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await _settle(tester);
      expect(find.text('launcher settings'), findsOneWidget);
    });
  });

  testWidgets('the settings screen: wallpaper, hidden apps, badges, backup, the phone\'s settings; Back closes it', (WidgetTester tester) async {
    await _start(tester, layout: const LauncherLayout(hidden: <String>['com.slack'], dockChosen: false));
    await _openDrawer(tester);
    expect(find.bySemanticsLabel('Launcher settings'), findsOneWidget);
    await tester.tap(find.text('settings'));
    await _settle(tester);
    expect(find.text('launcher settings'), findsOneWidget);
    await tester.tap(find.text('change wallpaper'), warnIfMissed: false);
    await _real(tester);
    expect(_bridgeCalls, contains('wallpaper'));
    await tester.scrollUntilVisible(find.text('give notification access'), 200, scrollable: find.descendant(of: find.byType(LauncherSettings), matching: find.byType(Scrollable)).first);
    expect(find.text('give notification access'), findsOneWidget, reason: 'badges are on and access is not given yet');
    await tester.scrollUntilVisible(find.text('unhide'), 200, scrollable: find.descendant(of: find.byType(LauncherSettings), matching: find.byType(Scrollable)).first);
    expect(find.bySemanticsLabel(RegExp('Show Slack in the drawer again')), findsWidgets);
    for (final String below in <String>['copy layout', 'restore from clipboard']) {
      await tester.scrollUntilVisible(find.text(below), 200, scrollable: find.descendant(of: find.byType(LauncherSettings), matching: find.byType(Scrollable)).first);
      expect(find.text(below), findsOneWidget);
    }
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('launcher settings'), findsNothing, reason: 'Back closed the settings');
  });

  testWidgets('the search offers matching settings pages and the web as well as apps', (WidgetTester tester) async {
    await _start(tester);
    await _openDrawer(tester);
    await tester.enterText(find.bySemanticsLabel('Search apps').first, 'wifi');
    await _settle(tester);
    expect(find.text('Wi-Fi settings'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi settings'), warnIfMissed: false);
    await _real(tester);
    expect(_bridgeCalls, contains('settings wifi'));
    await tester.tap(find.textContaining('Search the web for'), warnIfMissed: false);
    await _real(tester);
    expect(_bridgeCalls, contains('link https://www.google.com/search?q=wifi'));
  });

  testWidgets('Home closes the launcher settings, an open folder and arranging, as it closes the drawer', (WidgetTester tester) async {
    await _start(tester, layout: const LauncherLayout(home: <String>['folder:1', 'com.termux'], folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'Tools', apps: <String>['com.slack', 'com.whatsapp'])], dockChosen: false));
    int stamp = 100;
    Future<void> home() async => _systemKey(tester, 'home:${stamp++}');

    await tester.enterText(find.bySemanticsLabel(RegExp('^Command')).first, 'settings');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.text('launcher settings'), findsOneWidget, reason: '"settings" on the prompt opens them');
    await home();
    expect(find.text('launcher settings'), findsNothing);

    await tester.tap(find.text('Tools').first);
    await _settle(tester);
    expect(find.bySemanticsLabel('Close folder'), findsOneWidget);
    await home();
    expect(find.bySemanticsLabel('Close folder'), findsNothing);

    await _longPress(tester, 'Termux', onHome: true);
    await tester.tap(find.text('arrange home'), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Done arranging'), findsOneWidget);
    await home();
    expect(find.text('Done arranging'), findsNothing);
  });
}
