// Owner, 18 Nov (Tecno, 0.1.10 -> 0.1.11): after the update the dock showed
// only its two round buttons and the home screen said "Long-press any app",
// his Phone, Camera and Chrome gone. What 0.1.10 saved on the phone must
// still show after an update, whatever Android answers on the first start.
import 'dart:convert';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _installed = <String, String>{
  'com.transsion.phonemaster': 'Phone Master',
  'com.google.android.dialer': 'Phone',
  'com.transsion.camera': 'Camera',
  'com.android.chrome': 'Chrome',
  'com.termux': 'Termux',
};

/// The files 0.1.10 left on the phone, byte for byte as it wrote them.
Future<void> _savedBy0110(DVMemoryFileStorageAdapter files) async {
  await files.put(layoutFile, utf8.encode('{"home":["com.termux"],"dock":["com.google.android.dialer","com.transsion.camera","com.android.chrome"],"recentsSide":"left"}'));
  await files.put(appsFile, utf8.encode(jsonEncode(<Object?>[for (final MapEntry<String, String> app in _installed.entries) <String, Object?>{'package': app.key, 'label': app.value}])));
}

void _phoneAnswers(Object? Function() list) {
  DVNativeBridge.register('apps.list', (Object? _) => list());
  DVNativeBridge.register('apps.icon', (Object? _) => null);
  DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
  DVNativeBridge.register('apps.defaultFor', (Object? _) => null);
}

List<Object?> _listed() => <Object?>[for (final MapEntry<String, String> app in _installed.entries) <String, Object?>{'package': app.key, 'label': app.value}];

void main() {
  late DVMemoryFileStorageAdapter files;

  setUp(() async {
    files = DVMemoryFileStorageAdapter();
    DVDeviceStorage.useAdapters(files);
    await _savedBy0110(files);
  });

  tearDown(() {
    for (final String binding in <String>['apps.list', 'apps.icon', 'apps.isDefaultLauncher', 'apps.defaultFor']) {
      DVNativeBridge.unregister(binding);
    }
    DVDeviceStorage.reset();
  });

  void expectKept(LauncherStore store) {
    expect(store.current.appsFor(store.current.dock).map((DVInstalledApp app) => app.label), <String>['Phone', 'Camera', 'Chrome'], reason: 'the dock 0.1.10 saved');
    expect(store.current.appsFor(store.current.layout.home).map((DVInstalledApp app) => app.label), <String>['Termux'], reason: 'the home row 0.1.10 saved');
  }

  test('the dock and home row saved by 0.1.10 show after the update', () async {
    _phoneAnswers(_listed);
    final LauncherStore store = LauncherStore();
    await store.start();
    expectKept(store);
    expect(store.current.problem, isEmpty);
  });

  test('if Android will not list the apps, the saved ones stay and the home screen says why', () async {
    _phoneAnswers(() => throw StateError('No Android Context in this isolate'));
    final LauncherStore store = LauncherStore();
    await store.start();
    expectKept(store);
    expect(store.current.problem, contains('Could not read your apps'));
  });

  test('if Android answers with no apps at all, the saved ones stay and nothing is overwritten', () async {
    // A home screen always has apps to list (Settings at least, and this
    // launcher itself): an empty answer is a failed question, not a phone
    // with nothing on it.
    _phoneAnswers(() => <Object?>[]);
    final LauncherStore store = LauncherStore();
    await store.start();
    expectKept(store);
    expect(store.current.problem, isNotEmpty, reason: 'the person is told the list could not be read');

    // The saved names are not replaced by the empty answer.
    _phoneAnswers(_listed);
    final LauncherStore restarted = LauncherStore();
    await restarted.start();
    expectKept(restarted);
  });
}
