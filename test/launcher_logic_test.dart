// The prompt is the launcher: what you type picks an app or runs a command.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter_test/flutter_test.dart';

const List<LauncherApp> _apps = <LauncherApp>[
  LauncherApp(packageName: 'com.termux', label: 'Termux'),
  LauncherApp(packageName: 'com.github.android', label: 'GitHub'),
  LauncherApp(packageName: 'com.android.chrome', label: 'Chrome'),
  LauncherApp(packageName: 'com.google.android.gm', label: 'Gmail'),
  LauncherApp(packageName: 'com.postman.app', label: 'Postman'),
];

void main() {
  group('matching', () {
    test('an exact start of the name wins over letters scattered through it', () {
      expect(matchApps(_apps, 'gm').map((LauncherApp a) => a.label).first, 'Gmail');
      expect(matchApps(_apps, 'git').first.label, 'GitHub');
    });

    test('letters in order anywhere still match, case ignored', () {
      expect(matchApps(_apps, 'TRX').map((LauncherApp a) => a.label), ['Termux']);
    });

    test('the package name is searched too', () {
      expect(matchApps(_apps, 'postman.app').single.label, 'Postman');
    });

    test('an empty query matches nothing rather than everything', () {
      expect(matchApps(_apps, '   '), isEmpty);
    });

    test('a query nothing contains matches nothing', () {
      expect(matchApps(_apps, 'zzz'), isEmpty);
    });
  });

  group('commands', () {
    test('a bare query opens the best match', () {
      final LauncherCommand command = parseCommand('term', _apps);
      expect(command.action, LauncherAction.open);
      expect(command.app?.packageName, 'com.termux');
    });

    test('info, pin, unpin and uninstall take an app after them', () {
      expect(parseCommand('info chrome', _apps).action, LauncherAction.info);
      expect(parseCommand('info chrome', _apps).app?.label, 'Chrome');
      expect(parseCommand('pin git', _apps).action, LauncherAction.pin);
      expect(parseCommand('unpin git', _apps).action, LauncherAction.unpin);
      expect(parseCommand('uninstall postman', _apps).action, LauncherAction.uninstall);
    });

    test('a command word on its own is a search, not a command with no app', () {
      // Someone looking for an app called "Pinterest" types "pin".
      const List<LauncherApp> withPinterest = <LauncherApp>[..._apps, LauncherApp(packageName: 'com.pinterest', label: 'Pinterest')];
      final LauncherCommand command = parseCommand('pin', withPinterest);
      expect(command.action, LauncherAction.open);
      expect(command.app?.label, 'Pinterest');
    });

    test('a command whose app is not installed says so', () {
      final LauncherCommand command = parseCommand('info nothing-like-this', _apps);
      expect(command.action, LauncherAction.none);
      expect(command.message, contains('nothing-like-this'));
    });
  });

  group('dev tools', () {
    test('developer apps are recognised by package', () {
      expect(isDevTool('com.termux'), isTrue);
      expect(isDevTool('com.github.android'), isTrue);
      expect(isDevTool('com.google.android.gm'), isFalse);
    });
  });
}
