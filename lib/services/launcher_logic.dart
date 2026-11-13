// What the prompt understands: fuzzy app matching and a handful of commands.
// Pure Dart, so it is tested without a phone.

import 'dart:convert';

/// An app as the launcher sees it.
class const LauncherApp({required final String packageName, required final String label});

enum LauncherAction { open, info, pin, unpin, uninstall, none }

/// What pressing Enter on the prompt does.
class const LauncherCommand({required final LauncherAction action, final LauncherApp? app, final String message = ''});

/// Apps whose name or package contains [query]'s letters in order, best first:
/// a name that starts with the query, then a word in the name that does, then
/// the letters anywhere in the name, then anywhere in the package.
List<LauncherApp> matchApps(List<LauncherApp> apps, String query) {
  final String wanted = query.trim().toLowerCase();
  if (wanted.isEmpty) return const <LauncherApp>[];
  final List<(int, LauncherApp)> scored = <(int, LauncherApp)>[];
  for (final LauncherApp app in apps) {
    final int score = _score(app, wanted);
    if (score > 0) scored.add((score, app));
  }
  scored.sort(((int, LauncherApp) a, (int, LauncherApp) b) =>
      b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.label.toLowerCase().compareTo(b.$2.label.toLowerCase()));
  return <LauncherApp>[for (final (int, LauncherApp) entry in scored) entry.$2];
}

int _score(LauncherApp app, String wanted) {
  final String label = app.label.toLowerCase();
  final String package = app.packageName.toLowerCase();
  if (label.startsWith(wanted)) return 400;
  if (label.split(RegExp(r'[\s\-_.]+')).any((String word) => word.startsWith(wanted))) return 300;
  if (label.contains(wanted)) return 250;
  if (package.contains(wanted)) return 200;
  if (_inOrder(label, wanted)) return 100;
  if (_inOrder(package, wanted)) return 50;
  return 0;
}

bool _inOrder(String text, String letters) {
  int at = 0;
  for (final int unit in letters.codeUnits) {
    at = text.indexOf(String.fromCharCode(unit), at);
    if (at < 0) return false;
    at++;
  }
  return true;
}

const Map<String, LauncherAction> _verbs = <String, LauncherAction>{
  'info': LauncherAction.info,
  'pin': LauncherAction.pin,
  'unpin': LauncherAction.unpin,
  'uninstall': LauncherAction.uninstall,
};

/// Reads what was typed: `<verb> <app>` for a command, anything else opens the
/// best match. A verb with nothing after it is a search, so "pin" still finds
/// Pinterest.
LauncherCommand parseCommand(String typed, List<LauncherApp> apps) {
  final String text = typed.trim();
  final int space = text.indexOf(' ');
  if (space > 0) {
    final LauncherAction? verb = _verbs[text.substring(0, space).toLowerCase()];
    if (verb != null) {
      final String target = text.substring(space + 1).trim();
      final List<LauncherApp> found = matchApps(apps, target);
      if (found.isEmpty) return LauncherCommand(action: LauncherAction.none, message: 'No app matches "$target".');
      return LauncherCommand(action: verb, app: found.first);
    }
  }
  final List<LauncherApp> found = matchApps(apps, text);
  if (found.isEmpty) return LauncherCommand(action: LauncherAction.none, message: text.isEmpty ? '' : 'No app matches "$text".');
  return LauncherCommand(action: LauncherAction.open, app: found.first);
}

/// Package prefixes of apps developers reach for: terminals, Git hosts,
/// editors, API clients, cloud consoles and the like.
const List<String> devToolPackages = <String>[
  'com.termux',
  'com.github.android',
  'com.gitlab',
  'com.microsoft.vscode',
  'com.jetbrains',
  'com.postman',
  'com.amazon.aws',
  'com.google.android.apps.cloudconsole',
  'com.vercel',
  'io.heroku',
  'com.digitalocean',
  'com.stackexchange',
  'com.slack',
  'com.discord',
  'com.atlassian',
  'com.linear',
  'org.connectbot',
  'com.server.auditor.ssh.client',
  'com.offsec.nethunter',
  'com.aide.ui',
  'io.spck',
  'com.foxdebug.acode',
  'ru.iiec.pydroid3',
  'com.cloudflare.onedotonedotonedotone',
];

/// Whether [packageName] is one of [devToolPackages].
bool isDevTool(String packageName) => devToolPackages.any(packageName.startsWith);

/// One letter of the A-Z list and its apps.
class const LetterSection({required final String letter, required final List<LauncherApp> apps});

const Map<String, String> _plainLetters = <String, String>{
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y',
};

/// The letter [label] is filed under: A-Z, accents aside, else '#'.
String letterOf(String label) {
  if (label.isEmpty) return '#';
  final String first = label.substring(0, 1).toUpperCase();
  final String plain = _plainLetters[first] ?? first;
  return RegExp('[A-Z]').hasMatch(plain) ? plain : '#';
}

/// [apps] in letter sections, '#' first, each sorted by name ignoring case.
List<LetterSection> letterSections(List<LauncherApp> apps) {
  final Map<String, List<LauncherApp>> byLetter = <String, List<LauncherApp>>{};
  for (final LauncherApp app in apps) {
    byLetter.putIfAbsent(letterOf(app.label), () => <LauncherApp>[]).add(app);
  }
  final List<String> letters = byLetter.keys.toList()..sort();
  return <LetterSection>[
    for (final String letter in letters)
      LetterSection(letter: letter, apps: byLetter[letter]!..sort((LauncherApp a, LauncherApp b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()))),
  ];
}

/// The phone's usual four, by role, each a list of the packages that fill it
/// on different phones (Google, AOSP, Tecno/Infinix/itel, Samsung, Xiaomi).
const List<List<String>> dockRoles = <List<String>>[
  <String>['com.google.android.dialer', 'com.android.dialer', 'com.transsion.dialer', 'com.samsung.android.dialer', 'com.android.contacts'],
  <String>['com.google.android.apps.messaging', 'com.android.mms', 'com.transsion.message', 'com.samsung.android.messaging', 'com.android.messaging'],
  <String>['com.transsion.camera', 'com.google.android.GoogleCamera', 'com.android.camera', 'com.sec.android.app.camera', 'com.android.camera2'],
  <String>['com.android.chrome', 'org.mozilla.firefox', 'com.opera.browser', 'com.sec.android.app.sbrowser', 'com.transsion.phoenix'],
];

/// The dock before the person has chosen one: the first installed package
/// for each role in [dockRoles].
List<String> defaultDock(List<String> installed) {
  final Set<String> have = installed.toSet();
  return <String>[
    for (final List<String> role in dockRoles)
      if (role.where(have.contains).firstOrNull case final String package) package,
  ];
}

/// What the person arranged: apps on the home screen, apps in the dock.
class const LauncherLayout({final List<String> home = const <String>[], final List<String> dock = const <String>[], final bool dockChosen = true}) {
  String encode() => jsonEncode(<String, Object?>{'home': home, 'dock': dock});

  /// Reads [encode]'s shape, and the first version's plain list of pins.
  static LauncherLayout decode(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is List) return LauncherLayout(home: <String>[for (final Object? item in decoded) '$item'], dockChosen: false);
      if (decoded is Map) {
        List<String> listOf(Object? value) => value is List ? <String>[for (final Object? item in value) '$item'] : <String>[];
        return LauncherLayout(home: listOf(decoded['home']), dock: listOf(decoded['dock']), dockChosen: decoded['dock'] is List);
      }
    } on FormatException {
      // An unreadable file is an empty layout.
    }
    return const LauncherLayout(dockChosen: false);
  }
}

/// The screens Dev Launcher lays out for.
enum ScreenKind { watch, phone, tablet, tv }

/// Which kind of screen [width] x [height] logical pixels is. A watch is
/// small and nearly square; a TV is wide and big; a Chromebook is a large
/// tablet.
ScreenKind screenKindFor({required double width, required double height}) {
  final double shortest = width < height ? width : height;
  final double longest = width < height ? height : width;
  if (shortest < 300 || (longest / shortest < 1.25 && longest < 500)) return ScreenKind.watch;
  if (shortest >= 1000 && width > height && width >= 1600) return ScreenKind.tv;
  if (shortest >= 600) return ScreenKind.tablet;
  return ScreenKind.phone;
}

/// The inset on each side that keeps a square of content inside the circle
/// of a round watch face [diameter] wide.
double roundSafeInset(double diameter) => (diameter - diameter / 1.4142135623730951) / 2;

/// How many app tiles fit across.
int gridColumns(ScreenKind kind, double width) => switch (kind) {
      ScreenKind.watch => 2,
      ScreenKind.phone => 4,
      ScreenKind.tablet => (width / 130).floor().clamp(5, 8),
      ScreenKind.tv => 8,
    };

/// Where the drawer's top edge is after the finger moved [deltaY] from
/// [top], between 0 (open) and [height] (closed). One to one with the finger.
double drawerTopAfterDrag(double top, double deltaY, {required double height}) => (top + deltaY).clamp(0, height).toDouble();

/// Whether a drawer let go at [top], moving at [velocity] pixels a second
/// (negative is up), settles open: a quick flick decides, else being past
/// halfway does.
bool drawerSettlesOpen({required double top, required double height, required double velocity}) {
  if (velocity <= -400) return true;
  if (velocity >= 400) return false;
  return top < height / 2;
}

/// How many recent apps are kept: a row on every screen, with room to spare
/// for an app that is uninstalled.
const int recentAppsKept = 12;

/// The recent apps after [package] was opened: it first, once, then the rest
/// newest first, the oldest dropped past [recentAppsKept].
List<String> recordLaunch(List<String> recents, String package) {
  if (package.isEmpty) return recents;
  return <String>[package, ...recents.where((String each) => each != package)].take(recentAppsKept).toList();
}

/// [packages] without the ones no longer [installed], in the same order.
List<String> keepInstalled(List<String> packages, Set<String> installed) => <String>[for (final String package in packages) if (installed.contains(package)) package];

/// The recent apps as their file holds them.
String encodeRecents(List<String> recents) => jsonEncode(recents);

/// [encodeRecents]'s list back; anything else (no file, a broken one) is no
/// recent apps rather than a crash.
List<String> decodeRecents(String text) {
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is! List) return const <String>[];
    return <String>[for (final Object? item in decoded) if (item is String && item.isNotEmpty) item].take(recentAppsKept).toList();
  } on FormatException {
    return const <String>[];
  }
}

/// What changed between two lists of installed packages.
class const AppListChange({required final List<String> added, required final List<String> removed}) {
  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

/// The apps installed and uninstalled between [before] and [after].
AppListChange appListChange({required List<String> before, required List<String> after}) {
  final Set<String> had = before.toSet();
  final Set<String> has = after.toSet();
  return AppListChange(added: <String>[for (final String package in after) if (!had.contains(package)) package], removed: <String>[for (final String package in before) if (!has.contains(package)) package]);
}
