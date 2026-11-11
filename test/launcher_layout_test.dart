// What a home screen needs besides a prompt: apps in A-Z sections with a
// letter index, a dock that starts with the phone's usual four, and a layout
// (home and dock) kept on the phone.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter_test/flutter_test.dart';

const List<LauncherApp> _apps = <LauncherApp>[
  LauncherApp(packageName: 'com.whatsapp', label: 'WhatsApp'),
  LauncherApp(packageName: 'com.android.chrome', label: 'Chrome'),
  LauncherApp(packageName: 'com.google.android.calendar', label: 'Calendar'),
  LauncherApp(packageName: 'org.example.weird', label: '1Password'),
  LauncherApp(packageName: 'com.android.camera', label: 'camera'),
  LauncherApp(packageName: 'com.example.emoji', label: 'Éclair'),
];

void main() {
  group('A to Z', () {
    test('apps fall into letter sections, in order, case and accents aside', () {
      final List<LetterSection> sections = letterSections(_apps);
      expect(sections.map((LetterSection s) => s.letter), ['#', 'C', 'E', 'W']);
      expect(sections[1].apps.map((LauncherApp a) => a.label), ['Calendar', 'camera', 'Chrome']);
      expect(sections[2].apps.single.label, 'Éclair');
    });

    test('no apps, no sections', () {
      expect(letterSections(const <LauncherApp>[]), isEmpty);
    });
  });

  group('the dock', () {
    test('starts with phone, messages, camera and browser, from what is installed', () {
      final List<String> dock = defaultDock(<String>[
        'com.whatsapp',
        'com.android.chrome',
        'com.transsion.camera',
        'com.google.android.apps.messaging',
        'com.google.android.dialer',
        'com.termux',
      ]);
      expect(dock, ['com.google.android.dialer', 'com.google.android.apps.messaging', 'com.transsion.camera', 'com.android.chrome']);
    });

    test('a role with nothing installed is skipped, and the dock holds four at most', () {
      expect(defaultDock(<String>['com.android.chrome']), ['com.android.chrome']);
      expect(defaultDock(const <String>[]), isEmpty);
    });
  });

  group('the saved layout', () {
    test('home and dock round-trip', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['com.termux'], dock: <String>['com.android.chrome']);
      final LauncherLayout back = LauncherLayout.decode(layout.encode());
      expect(back.home, ['com.termux']);
      expect(back.dock, ['com.android.chrome']);
      expect(back.dockChosen, isTrue);
    });

    test('the old pins file (a plain list) becomes the home row, with no dock chosen yet', () {
      final LauncherLayout old = LauncherLayout.decode('["com.termux","com.github.android"]');
      expect(old.home, ['com.termux', 'com.github.android']);
      expect(old.dockChosen, isFalse);
    });

    test('anything unreadable is an empty layout, not a crash', () {
      expect(LauncherLayout.decode('not json').home, isEmpty);
      expect(LauncherLayout.decode('').dockChosen, isFalse);
    });
  });

  group('every screen, watch to TV', () {
    test('the kind of screen comes from its size', () {
      expect(screenKindFor(width: 240, height: 240), ScreenKind.watch);
      expect(screenKindFor(width: 454, height: 454), ScreenKind.watch, reason: 'a large round watch is still a watch');
      expect(screenKindFor(width: 360, height: 800), ScreenKind.phone);
      expect(screenKindFor(width: 800, height: 1280), ScreenKind.tablet);
      expect(screenKindFor(width: 1366, height: 768), ScreenKind.tablet, reason: 'a Chromebook lays out as a big tablet');
      expect(screenKindFor(width: 1920, height: 1080), ScreenKind.tv);
    });

    test('a watch keeps everything inside the circle a round face shows', () {
      // A square inside a circle of diameter d has side d / sqrt(2): about
      // 15% of the width is lost on each side.
      expect(roundSafeInset(240), closeTo(35.1, 0.1));
      expect(roundSafeInset(454), closeTo(66.5, 0.1));
    });

    test('columns grow with the width and stay readable', () {
      expect(gridColumns(ScreenKind.watch, 240), 2);
      expect(gridColumns(ScreenKind.phone, 360), 4);
      expect(gridColumns(ScreenKind.phone, 412), 4);
      expect(gridColumns(ScreenKind.tablet, 800), 6);
      expect(gridColumns(ScreenKind.tablet, 1366), 8);
      expect(gridColumns(ScreenKind.tv, 1920), 8, reason: 'a TV is read from across a room: fewer, larger tiles');
    });
  });

  group('the drawer follows the finger', () {
    test('it moves exactly as far as the finger, and never past open or closed', () {
      expect(drawerTopAfterDrag(800, -120, height: 800), 680);
      expect(drawerTopAfterDrag(100, -300, height: 800), 0);
      expect(drawerTopAfterDrag(700, 300, height: 800), 800);
    });

    test('let go, it settles by how fast it was moving, else by where it is', () {
      expect(drawerSettlesOpen(top: 700, height: 800, velocity: -900), isTrue, reason: 'a quick flick up opens it from anywhere');
      expect(drawerSettlesOpen(top: 100, height: 800, velocity: 900), isFalse, reason: 'a quick flick down closes it');
      expect(drawerSettlesOpen(top: 300, height: 800, velocity: 0), isTrue, reason: 'past halfway, it opens');
      expect(drawerSettlesOpen(top: 500, height: 800, velocity: 0), isFalse, reason: 'short of halfway, it falls back');
    });
  });
}
