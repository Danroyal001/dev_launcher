// The store against a phone stand-in: Android's app list, icons and launches
// answered by fake bindings, the phone's files kept in memory. Covers what
// the person sees change: recents after a launch, across a restart, and apps
// installed or uninstalled while the launcher is open.
import 'dart:typed_data';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone: which apps are installed, and what was opened.
class FakePhone {
  FakePhone(this.installed);

  final Map<String, String> installed;
  final List<String> opened = <String>[];
  int listCalls = 0;
  int iconCalls = 0;

  void install() {
    DVNativeBridge.register('apps.list', (Object? _) {
      listCalls++;
      return <Object?>[for (final MapEntry<String, String> app in installed.entries) <String, Object?>{'package': app.key, 'label': app.value}];
    });
    DVNativeBridge.register('apps.icon', (Object? arguments) {
      iconCalls++;
      final String package = '${(arguments as Map)['package']}';
      return installed.containsKey(package) ? Uint8List.fromList(<int>[1, 2, 3]) : null;
    });
    DVNativeBridge.register('apps.open', (Object? arguments) {
      final String package = '${(arguments as Map)['package']}';
      if (!installed.containsKey(package)) return false;
      opened.add(package);
      return true;
    });
    DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
    DVNativeBridge.register('apps.defaultFor', (Object? _) => null);
  }

  void uninstall() {
    for (final String binding in <String>['apps.list', 'apps.icon', 'apps.open', 'apps.isDefaultLauncher', 'apps.defaultFor']) {
      DVNativeBridge.unregister(binding);
    }
  }
}

void main() {
  late FakePhone phone;
  late DVMemoryFileStorageAdapter files;

  setUp(() {
    phone = FakePhone(<String, String>{'com.termux': 'Termux', 'com.android.chrome': 'Chrome', 'com.whatsapp': 'WhatsApp'})..install();
    files = DVMemoryFileStorageAdapter();
    DVDeviceStorage.useAdapters(files);
  });

  tearDown(() {
    phone.uninstall();
    DVDeviceStorage.reset();
  });

  test('opening an app puts it first in recents, and recents survive a restart', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    expect(store.current.recents, isEmpty);

    expect(await store.open('com.termux'), '');
    expect(await store.open('com.whatsapp'), '');
    expect(phone.opened, <String>['com.termux', 'com.whatsapp']);
    expect(store.current.recents, <String>['com.whatsapp', 'com.termux']);
    expect(store.current.recentApps.map((DVInstalledApp app) => app.label), <String>['WhatsApp', 'Termux']);

    final LauncherStore restarted = LauncherStore();
    await restarted.start();
    expect(restarted.current.recents, <String>['com.whatsapp', 'com.termux'], reason: 'kept on the phone');
  });

  test('an app uninstalled while the launcher is open leaves the list, recents and its icon file', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    await store.open('com.whatsapp');
    expect(await files.exists('dev-launcher/icons/com.whatsapp.png'), isTrue);

    phone.installed.remove('com.whatsapp');
    await store.refreshApps();
    expect(store.current.app('com.whatsapp'), isNull);
    expect(store.current.recents, isEmpty);
    expect(await files.exists('dev-launcher/icons/com.whatsapp.png'), isFalse);

    final LauncherStore restarted = LauncherStore();
    await restarted.start();
    expect(restarted.current.recents, isEmpty, reason: 'the pruned list was saved');
  });

  test('an app installed while open appears with its icon; the others are not drawn again', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    final int iconsBefore = phone.iconCalls;

    phone.installed['com.github.android'] = 'GitHub';
    await store.refreshApps();
    expect(store.current.app('com.github.android')?.icon, isNotNull);
    expect(phone.iconCalls - iconsBefore, 1, reason: 'only the new app is drawn');
    expect(store.current.app('com.termux')?.icon, isNotNull, reason: 'icons already shown stay');
  });

  test('tapping an app that is already gone says so and drops it', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    phone.installed.remove('com.android.chrome');
    expect(await store.open('com.android.chrome'), isNotEmpty);
    expect(store.current.app('com.android.chrome'), isNull);
  });

  test('a second start shows the apps from the last one at once, before Android answers', () async {
    final LauncherStore first = LauncherStore();
    await first.start();

    final LauncherStore second = LauncherStore();
    final List<LauncherSnapshot> seen = <LauncherSnapshot>[];
    second.changes.listen(seen.add);
    DVNativeBridge.register('apps.list', (Object? _) async {
      // Android is slow to answer: the cached names must already be up.
      expect(seen.any((LauncherSnapshot snapshot) => snapshot.apps.length == 3 && !snapshot.loading), isTrue);
      return <Object?>[for (final MapEntry<String, String> app in phone.installed.entries) <String, Object?>{'package': app.key, 'label': app.value}];
    });
    await second.start();
    expect(second.current.apps.length, 3);
  });

  // Owner, 13 Nov (Tecno, Android 12): back on the home screen from an app,
  // the launcher froze for seconds and then "isn't responding". 0.1.7 asked
  // Android for every app on each return. Returning now asks at most once a
  // while, after the home screen is back on screen, never in the moment of
  // returning.
  test('returning to the home screen does not re-list the apps at once, and not twice in a row', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    final int before = phone.listCalls;

    store.refreshAppsSoon(delay: const Duration(milliseconds: 50), freshFor: Duration.zero);
    expect(phone.listCalls, before, reason: 'nothing asked in the moment of returning');
    store.refreshAppsSoon(delay: const Duration(milliseconds: 50), freshFor: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(phone.listCalls, before + 1, reason: 'two returns close together are one look');

    store.refreshAppsSoon(delay: const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(phone.listCalls, before + 1, reason: 'a look a moment ago is fresh enough');
  });

  test('an app installed while away still shows up on a later return', () async {
    final LauncherStore store = LauncherStore();
    await store.start();
    phone.installed['com.github.android'] = 'GitHub';
    store.refreshAppsSoon(delay: const Duration(milliseconds: 10), freshFor: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(store.current.app('com.github.android'), isNotNull);
  });
}
