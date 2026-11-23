// Updates: the launcher says which version this phone has, asks GitHub for
// the newest release, and offers the APK for this phone's processor (32-bit
// ARM on the owner's Tecno). Asked by the owner as "an in-app downloads page".
import 'dart:convert';
import 'dart:io';

import 'package:dev_launcher/services/launcher_store.dart';
import 'package:dev_launcher/services/updates.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

const String _releaseJson = '''{
  "tag_name": "v0.1.99",
  "html_url": "https://github.com/Danroyal001/dev_launcher/releases/tag/v0.1.99",
  "published_at": "2026-11-24T10:00:00Z",
  "prerelease": false,
  "body": "- Faster start.\\n- Folders.",
  "assets": [
    {"name": "dev-launcher-0.1.99-arm64-v8a.apk", "size": 18948910, "browser_download_url": "https://github.com/Danroyal001/dev_launcher/releases/download/v0.1.99/dev-launcher-0.1.99-arm64-v8a.apk"},
    {"name": "dev-launcher-0.1.99-armeabi-v7a.apk", "size": 16406776, "browser_download_url": "https://github.com/Danroyal001/dev_launcher/releases/download/v0.1.99/dev-launcher-0.1.99-armeabi-v7a.apk"},
    {"name": "checksums.txt", "size": 200, "browser_download_url": "https://example.com/checksums.txt"}
  ]
}''';

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
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('versions', () {
    test('the version in the app is the one in pubspec.yaml', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final String version = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
      expect(launcherVersion, version);
    });

    test('compares numerically, ignores the v, and puts a pre-release below its release', () {
      expect(compareVersions('0.1.14', '0.1.9'), greaterThan(0));
      expect(compareVersions('v0.1.14', '0.1.14'), 0);
      expect(compareVersions('0.1.13-rc1', '0.1.13'), lessThan(0));
      expect(compareVersions('0.2.0', '0.1.99'), greaterThan(0));
      expect(compareVersions('0.1.12', '0.1.14'), lessThan(0));
    });
  });

  group('the release GitHub answers', () {
    final LauncherRelease release = parseRelease(jsonDecode(_releaseJson) as Map<String, Object?>)!;

    test('reads version, page, date, notes and only the APKs', () {
      expect(release.version, '0.1.99');
      expect(release.pageUrl, 'https://github.com/Danroyal001/dev_launcher/releases/tag/v0.1.99');
      expect(release.published, DateTime.utc(2026, 11, 24, 10));
      expect(release.notes, contains('Folders'));
      expect(release.apks.map((ReleaseApk apk) => apk.abi), <String>['arm64-v8a', 'armeabi-v7a']);
    });

    test('picks the APK for this phone, and none for an unknown processor', () {
      expect(apkForAbi(release, 'armeabi-v7a')!.name, 'dev-launcher-0.1.99-armeabi-v7a.apk');
      expect(apkForAbi(release, 'arm64-v8a')!.bytes, 18948910);
      expect(apkForAbi(release, ''), isNull);
    });

    test('an answer that is not a release is null, not a crash', () {
      expect(parseRelease(<String, Object?>{'message': 'API rate limit exceeded'}), isNull);
    });

    test('says plainly whether this phone is up to date', () {
      expect(updateHeadline('0.1.14', release), 'Dev Launcher 0.1.99 is out. This phone has 0.1.14.');
      expect(updateHeadline('0.1.99', release), 'This phone has the newest version, 0.1.99.');
      expect(sizeText(16406776), '15.6 MB');
      expect(abiName('armeabi-v7a'), contains('32-bit'));
      expect(abiName('arm64-v8a'), contains('64-bit'));
    });
  });

  group('the updates screen', () {
    setUp(() => LauncherUpdates.instance.fetch = (Uri uri) async => _releaseJson);
    tearDown(LauncherUpdates.instance.reset);

    testWidgets('opens from the drawer, shows this version, the newest one and its downloads; Back closes it', (WidgetTester tester) async {
      await startApp(tester);
      await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
      await settle(tester);
      final Finder link = find.bySemanticsLabel(RegExp('^Updates'));
      expect(link, findsWidgets, reason: 'the drawer has an Updates link');
      await tester.tap(link.first, warnIfMissed: false);
      await settle(tester);

      expect(find.text('updates'), findsOneWidget, reason: 'the updates screen is up');
      expect(find.textContaining('This phone: Dev Launcher $launcherVersion'), findsOneWidget);
      expect(find.text('Dev Launcher 0.1.99 is out. This phone has $launcherVersion.'), findsOneWidget);
      expect(find.textContaining('dev-launcher-0.1.99-armeabi-v7a.apk'), findsOneWidget);
      expect(find.textContaining('dev-launcher-0.1.99-arm64-v8a.apk'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Share the download link')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('^Copy the download link')), findsWidgets);
      expect(find.bySemanticsLabel('Check for updates again'), findsOneWidget);

      final bool handled = await tester.binding.handlePopRoute();
      await settle(tester);
      expect(handled, isTrue);
      expect(find.text('updates'), findsNothing, reason: 'Back closed it');
    });

    testWidgets('a failed check says why and offers to try again', (WidgetTester tester) async {
      LauncherUpdates.instance.fetch = (Uri uri) async => throw const SocketException('no network');
      await startApp(tester);
      await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Updates')).first, warnIfMissed: false);
      await settle(tester);
      expect(find.textContaining('Could not check for updates'), findsOneWidget);
      expect(find.bySemanticsLabel('Check for updates again'), findsOneWidget);
    });

    testWidgets('the home screen says when a newer version is out, and the note opens the updates screen', (WidgetTester tester) async {
      LauncherUpdates.instance.autoCheck = true;
      await startApp(tester);
      await settle(tester);
      final Finder note = find.bySemanticsLabel(RegExp('^Dev Launcher 0.1.99 is out'));
      expect(note, findsOneWidget);
      await tester.tap(note, warnIfMissed: false);
      await settle(tester);
      expect(find.text('updates'), findsOneWidget);
    });

    testWidgets('no note on the home screen when this phone is up to date', (WidgetTester tester) async {
      LauncherUpdates.instance.fetch = (Uri uri) async => _releaseJson.replaceAll('0.1.99', launcherVersion);
      LauncherUpdates.instance.autoCheck = true;
      await startApp(tester);
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('is out')), findsNothing);
      expect(LauncherStore.instance.current.apps, isNotEmpty);
    });
  });
}
