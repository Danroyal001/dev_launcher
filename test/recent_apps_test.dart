// Recent apps: the apps the person opened last, newest first, kept on the
// phone across restarts, and never an app that is no longer installed.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recording a launch', () {
    test('the app just opened goes first', () {
      expect(recordLaunch(<String>['com.termux', 'com.android.chrome'], 'com.whatsapp'), <String>['com.whatsapp', 'com.termux', 'com.android.chrome']);
    });

    test('opening an app already in the list moves it to the front, once', () {
      expect(recordLaunch(<String>['com.termux', 'com.android.chrome', 'com.whatsapp'], 'com.whatsapp'), <String>['com.whatsapp', 'com.termux', 'com.android.chrome']);
    });

    test('the list keeps the newest few and forgets the oldest', () {
      final List<String> many = <String>[for (int index = 0; index < recentAppsKept; index++) 'app.$index'];
      final List<String> next = recordLaunch(many, 'app.new');
      expect(next.length, recentAppsKept);
      expect(next.first, 'app.new');
      expect(next, isNot(contains('app.${recentAppsKept - 1}')), reason: 'the oldest falls off the end');
    });

    test('a blank package records nothing', () {
      expect(recordLaunch(<String>['com.termux'], ''), <String>['com.termux']);
    });
  });

  group('installed apps only', () {
    test('an uninstalled app leaves the list, the order of the rest kept', () {
      expect(keepInstalled(<String>['com.gone', 'com.termux', 'com.android.chrome'], <String>{'com.android.chrome', 'com.termux'}), <String>['com.termux', 'com.android.chrome']);
    });
  });

  group('kept on the phone', () {
    test('the list round-trips through its file', () {
      const List<String> recents = <String>['com.whatsapp', 'com.termux'];
      expect(decodeRecents(encodeRecents(recents)), recents);
    });

    test('a missing, broken or foreign file is an empty list, not a crash', () {
      expect(decodeRecents(''), isEmpty);
      expect(decodeRecents('not json'), isEmpty);
      expect(decodeRecents('{"home": []}'), isEmpty);
      expect(decodeRecents('[1, "com.termux", null, ""]'), <String>['com.termux']);
    });

    test('a file longer than the list keeps is cut to it', () {
      final String long = encodeRecents(<String>[for (int index = 0; index < 40; index++) 'app.$index']);
      expect(decodeRecents(long).length, recentAppsKept);
    });
  });

  group('installs and uninstalls while open', () {
    test('the difference between two app lists names what came and what went', () {
      final AppListChange change = appListChange(before: <String>['com.termux', 'com.gone'], after: <String>['com.termux', 'com.new']);
      expect(change.added, <String>['com.new']);
      expect(change.removed, <String>['com.gone']);
      expect(change.isEmpty, isFalse);
      expect(appListChange(before: <String>['a', 'b'], after: <String>['b', 'a']).isEmpty, isTrue);
    });
  });
}
