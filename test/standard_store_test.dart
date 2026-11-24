// The store with the standard launcher features, against a phone stand-in:
// installs heard as Android broadcasts them (not only on the next return to
// the front), notification counts for badges, and hidden apps, folders and a
// rearranged home screen kept across a restart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Map<String, String> installed = <String, String>{};
  int listCalls = 0;
  late DVMemoryFileStorageAdapter files;

  Future<void> systemKey(String message) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage(message), (ByteData? _) {});
    for (int turn = 0; turn < 20; turn++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() {
    installed
      ..clear()
      ..addAll(<String, String>{'com.termux': 'Termux', 'com.android.chrome': 'Chrome', 'com.whatsapp': 'WhatsApp', 'com.slack': 'Slack'});
    listCalls = 0;
    DVNativeBridge.register('apps.list', (Object? _) {
      listCalls++;
      return <Object?>[for (final MapEntry<String, String> app in installed.entries) <String, Object?>{'package': app.key, 'label': app.value}];
    });
    DVNativeBridge.register('apps.icon', (Object? _) => Uint8List.fromList(<int>[1, 2, 3]));
    DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
    DVNativeBridge.register('apps.defaultFor', (Object? _) => null);
    // A home app, so the system keys reach it.
    DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', (ByteData? message) async {
      final String? question = const StringCodec().decodeMessage(message);
      return const StringCodec().encodeMessage(question == 'badges.current' ? jsonEncode(<String, int>{'com.whatsapp': 2}) : null);
    });
    files = DVMemoryFileStorageAdapter();
    DVDeviceStorage.useAdapters(files);
  });

  tearDown(() {
    for (final String binding in <String>['apps.list', 'apps.icon', 'apps.isDefaultLauncher', 'apps.defaultFor', 'apps.homePressedAt']) {
      DVNativeBridge.unregister(binding);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', null);
    DVDeviceStorage.reset();
  });

  test('an app installed while the launcher is open appears when Android says so, with no return to the front', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    final int before = listCalls;
    installed['com.github.android'] = 'GitHub';
    await systemKey('package:100:added:com.github.android');
    expect(listCalls, greaterThan(before), reason: 'the broadcast asked Android for the apps again');
    expect(store.current.app('com.github.android'), isNotNull);
    installed.remove('com.slack');
    await systemKey('package:101:removed:com.slack');
    expect(store.current.app('com.slack'), isNull);
  });

  test('notification counts reach the snapshot, and badges off shows none', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    await systemKey('badges:1:{}');
    await systemKey('badges:2:${jsonEncode(<String, int>{'com.whatsapp': 3, 'com.slack': 1})}');
    expect(store.current.badgeFor('com.whatsapp'), 3);
    expect(store.current.badgeFor('com.termux'), 0);
    await store.setOptions(store.current.layout.options.copyWith(badges: false));
    expect(store.current.badgeFor('com.whatsapp'), 0);
  });

  test('hidden apps, a folder and a rearranged home screen are kept across a restart', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    await store.pinHome('com.termux', pinned: true);
    await store.pinHome('com.android.chrome', pinned: true);
    await store.pinHome('com.slack', pinned: true);
    await store.hideApp('com.whatsapp', hidden: true);
    expect(store.current.visibleLauncherApps.map((LauncherApp app) => app.packageName), isNot(contains('com.whatsapp')));
    await store.putInFolder('com.slack', name: 'Work');
    final String folderItem = store.current.layout.home.last;
    expect(folderItem, startsWith(folderPrefix));
    await store.putInFolder('com.whatsapp', folderId: folderItem.substring(folderPrefix.length));
    await store.moveHomeItem(2, 0);
    expect(store.current.layout.home, <String>[folderItem, 'com.termux', 'com.android.chrome']);

    final LauncherStore restarted = LauncherStore();
    await restarted.start();
    expect(restarted.current.layout.home, <String>[folderItem, 'com.termux', 'com.android.chrome']);
    expect(restarted.current.layout.hidden, <String>['com.whatsapp']);
    expect(restarted.current.layout.folders.single.name, 'Work');
    expect(restarted.current.layout.folders.single.apps, <String>['com.slack', 'com.whatsapp']);
  });

  test('a restored backup replaces the layout; a bad paste changes nothing', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    await store.pinHome('com.termux', pinned: true);
    final String backup = layoutBackup(store.current.layout);
    await store.pinHome('com.termux', pinned: false);
    expect(store.current.layout.home, isEmpty);
    await store.restore(restoreLayout(backup)!);
    expect(store.current.layout.home, <String>['com.termux']);
  });
}
