// Owner, 21 Nov (Tecno, 0.1.12): the app list is back (48 apps) but the
// dock and the home row are empty: the layout saved by 0.1.10 was written
// over. A layout that could not be read must never be saved over, and a dock
// that holds no installed app shows the phone's own apps.
import 'dart:convert';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _installed = <String, String>{
  'com.transsion.phonemaster': 'Phone Master',
  'com.android.dialer': 'Phone',
  'com.transsion.camera': 'Camera',
  'com.android.chrome': 'Chrome',
  'com.google.android.apps.messaging': 'Messages',
  'com.termux': 'Termux',
};

List<Object?> _listed() => <Object?>[for (final MapEntry<String, String> app in _installed.entries) <String, Object?>{'package': app.key, 'label': app.value}];

void _phoneAnswers({Map<String, String?> defaults = const <String, String?>{}}) {
  DVNativeBridge.register('apps.list', (Object? _) => _listed());
  DVNativeBridge.register('apps.icon', (Object? _) => null);
  DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
  DVNativeBridge.register('apps.defaultFor', (Object? arguments) => defaults[(arguments as Map<Object?, Object?>)['role']]);
}

/// Storage whose reads of [failing] throw, as a phone's storage can at boot.
class _FlakyStorage extends DVMemoryFileStorageAdapter {
  _FlakyStorage(this.failing);
  final Set<String> failing;
  @override
  Future<List<int>> get(String path) async {
    if (failing.contains(path)) throw StateError('storage not ready');
    return super.get(path);
  }
}

const String _savedBy0110 = '{"home":["com.termux"],"dock":["com.android.dialer","com.transsion.camera","com.android.chrome"]}';

void main() {
  tearDown(() {
    for (final String binding in <String>['apps.list', 'apps.icon', 'apps.isDefaultLauncher', 'apps.defaultFor']) {
      DVNativeBridge.unregister(binding);
    }
    DVDeviceStorage.reset();
  });

  test('a layout that could not be read is not saved over by the next change', () async {
    final _FlakyStorage files = _FlakyStorage(<String>{layoutFile});
    DVDeviceStorage.useAdapters(files);
    await files.put(layoutFile, utf8.encode(_savedBy0110));
    _phoneAnswers();
    final LauncherStore store = LauncherStore(retryDelays: const <Duration>[]);
    await store.start();
    expect(store.current.problem, contains('home screen'), reason: 'the person is told the saved layout could not be read');

    final String result = await store.setIndexSide(IndexSide.left);
    expect(result, isNotEmpty, reason: 'the change is refused, with a reason');
    files.failing.clear();
    expect(utf8.decode(await files.get(layoutFile)), _savedBy0110, reason: 'what 0.1.10 saved is still there');
  });

  test('the layout is read again on the next return to the front, and then shows', () async {
    final _FlakyStorage files = _FlakyStorage(<String>{layoutFile});
    DVDeviceStorage.useAdapters(files);
    await files.put(layoutFile, utf8.encode(_savedBy0110));
    _phoneAnswers();
    final LauncherStore store = LauncherStore(retryDelays: const <Duration>[]);
    await store.start();
    files.failing.clear();
    await store.refreshApps();
    expect(store.current.appsFor(store.current.layout.home).map((DVInstalledApp app) => app.label), <String>['Termux']);
    expect(store.current.appsFor(store.current.dock).map((DVInstalledApp app) => app.label), <String>['Phone', 'Camera', 'Chrome']);
  });

  test('a chosen dock with no installed app in it shows the phone\'s own apps', () async {
    final DVMemoryFileStorageAdapter files = DVMemoryFileStorageAdapter();
    DVDeviceStorage.useAdapters(files);
    // What 0.1.11 left on the owner's phone: an empty dock, marked as chosen.
    await files.put(layoutFile, utf8.encode('{"home":[],"dock":[]}'));
    _phoneAnswers(defaults: <String, String?>{
      'phone': 'com.android.dialer',
      'messages': 'com.google.android.apps.messaging',
      'camera': 'com.transsion.camera',
      'browser': 'com.android.chrome',
    });
    final LauncherStore store = LauncherStore(retryDelays: const <Duration>[]);
    await store.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.current.appsFor(store.current.dock).map((DVInstalledApp app) => app.label), <String>['Phone', 'Messages', 'Camera', 'Chrome']);
  });
}
