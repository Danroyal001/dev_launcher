// What the prompt understands: fuzzy app matching and a handful of commands.
// Pure Dart, so it is tested without a phone.

import 'dart:convert';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

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

/// A folder on the home screen: a name and the apps in it, in order.
class const LauncherFolder({required final String id, required final String name, final List<String> apps = const <String>[]}) {
  /// How the folder is named in the home screen's list of items.
  String get homeItem => '$folderPrefix$id';

  LauncherFolder copyWith({String? name, List<String>? apps}) => LauncherFolder(id: id, name: name ?? this.name, apps: apps ?? this.apps);

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'apps': apps};
}

/// What a home-screen item naming a folder starts with: `folder:<id>`.
const String folderPrefix = 'folder:';

/// Light or dark for the drawer, menus and settings: the phone's dark theme, or
/// always one of them. What sits on the wallpaper stays light over its scrim.
enum LauncherTheme { device, dark, light }

/// The launcher's own settings. Every standard launcher's gestures are on by
/// default; reading contacts asks for a permission, so it waits to be chosen.
class const LauncherOptions({final bool swipeDownShade = true, final bool doubleTapLock = true, final bool pinchSettings = true, final bool badges = true, final bool searchWeb = true, final bool searchContacts = false, final LauncherTheme theme = LauncherTheme.device}) {
  LauncherOptions copyWith({bool? swipeDownShade, bool? doubleTapLock, bool? pinchSettings, bool? badges, bool? searchWeb, bool? searchContacts, LauncherTheme? theme}) => LauncherOptions(
        theme: theme ?? this.theme,
        swipeDownShade: swipeDownShade ?? this.swipeDownShade,
        doubleTapLock: doubleTapLock ?? this.doubleTapLock,
        pinchSettings: pinchSettings ?? this.pinchSettings,
        badges: badges ?? this.badges,
        searchWeb: searchWeb ?? this.searchWeb,
        searchContacts: searchContacts ?? this.searchContacts,
      );

  Map<String, Object?> toJson() => <String, Object?>{'swipeDownShade': swipeDownShade, 'doubleTapLock': doubleTapLock, 'pinchSettings': pinchSettings, 'badges': badges, 'searchWeb': searchWeb, 'searchContacts': searchContacts, if (theme != LauncherTheme.device) 'theme': theme.name};

  static LauncherOptions fromJson(Object? value) {
    if (value is! Map) return const LauncherOptions();
    bool flag(String name, bool fallback) => value[name] is bool ? value[name] as bool : fallback;
    return LauncherOptions(
      swipeDownShade: flag('swipeDownShade', true),
      doubleTapLock: flag('doubleTapLock', true),
      pinchSettings: flag('pinchSettings', true),
      badges: flag('badges', true),
      searchWeb: flag('searchWeb', true),
      searchContacts: flag('searchContacts', false),
      theme: LauncherTheme.values.where((LauncherTheme each) => each.name == value['theme']).firstOrNull ?? LauncherTheme.device,
    );
  }
}

/// What the person arranged: apps and folders on the home screen, apps in the
/// dock, apps hidden from the drawer, and the launcher's settings.
class const LauncherLayout({
  final List<String> home = const <String>[],
  final List<String> dock = const <String>[],
  final bool dockChosen = true,
  final RecentsSide recentsSide = RecentsSide.device,
  final IndexSide indexSide = IndexSide.device,
  final List<String> hidden = const <String>[],
  final List<LauncherFolder> folders = const <LauncherFolder>[],
  final LauncherOptions options = const LauncherOptions(),
}) {
  String encode() => jsonEncode(<String, Object?>{
        'home': home,
        'dock': dock,
        if (recentsSide != RecentsSide.device) 'recentsSide': recentsSide.name,
        if (indexSide != IndexSide.device) 'indexSide': indexSide.name,
        if (hidden.isNotEmpty) 'hidden': hidden,
        if (folders.isNotEmpty) 'folders': <Object?>[for (final LauncherFolder folder in folders) folder.toJson()],
        'options': options.toJson(),
      });

  LauncherLayout copyWith({List<String>? home, List<String>? dock, bool? dockChosen, RecentsSide? recentsSide, IndexSide? indexSide, List<String>? hidden, List<LauncherFolder>? folders, LauncherOptions? options}) => LauncherLayout(
        home: home ?? this.home,
        dock: dock ?? this.dock,
        dockChosen: dockChosen ?? this.dockChosen,
        recentsSide: recentsSide ?? this.recentsSide,
        indexSide: indexSide ?? this.indexSide,
        hidden: hidden ?? this.hidden,
        folders: folders ?? this.folders,
        options: options ?? this.options,
      );

  /// The folder [id], or null.
  LauncherFolder? folder(String id) => folders.where((LauncherFolder each) => each.id == id).firstOrNull;

  /// Reads [encode]'s shape, and the first version's plain list of pins.
  static LauncherLayout decode(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is List) return LauncherLayout(home: <String>[for (final Object? item in decoded) '$item'], dockChosen: false);
      if (decoded is Map) {
        List<String> listOf(Object? value) => value is List ? <String>[for (final Object? item in value) '$item'] : <String>[];
        final List<LauncherFolder> folders = <LauncherFolder>[
          if (decoded['folders'] case final List<Object?> list)
            for (final Object? item in list)
              if (item is Map && '${item['id'] ?? ''}'.isNotEmpty) LauncherFolder(id: '${item['id']}', name: '${item['name'] ?? 'Folder'}', apps: listOf(item['apps'])),
        ];
        final Set<String> folderItems = <String>{for (final LauncherFolder folder in folders) folder.homeItem};
        return LauncherLayout(
          // A folder named on home with nothing behind it would be a blank tile.
          home: <String>[for (final String item in listOf(decoded['home'])) if (!item.startsWith(folderPrefix) || folderItems.contains(item)) item],
          dock: listOf(decoded['dock']),
          dockChosen: decoded['dock'] is List,
          recentsSide: RecentsSide.values.where((RecentsSide side) => side.name == decoded['recentsSide']).firstOrNull ?? RecentsSide.device,
          indexSide: IndexSide.values.where((IndexSide side) => side.name == decoded['indexSide']).firstOrNull ?? IndexSide.device,
          hidden: listOf(decoded['hidden']),
          folders: folders,
          options: LauncherOptions.fromJson(decoded['options']),
        );
      }
    } on FormatException {
      // An unreadable file is an empty layout.
    }
    return const LauncherLayout(dockChosen: false);
  }
}

/// [layout] with [package] in a folder: [folderId]'s, else a new folder
/// called [folderName] that takes the app's place on the home screen (or goes
/// at its end). The app leaves the home screen and every other folder.
LauncherLayout addToFolder(LauncherLayout layout, String package, {String? folderId, String folderName = 'Folder'}) {
  final LauncherFolder? existing = folderId == null ? null : layout.folder(folderId);
  final String id = existing?.id ?? _newFolderId(layout);
  final List<LauncherFolder> folders = <LauncherFolder>[
    for (final LauncherFolder folder in layout.folders)
      if (folder.id == id) folder.copyWith(apps: <String>[...folder.apps.where((String app) => app != package), package]) else folder.copyWith(apps: folder.apps.where((String app) => app != package).toList()),
    if (existing == null) LauncherFolder(id: id, name: folderName.trim().isEmpty ? 'Folder' : folderName.trim(), apps: <String>[package]),
  ];
  final int at = layout.home.indexOf(package);
  final List<String> home = <String>[for (final String item in layout.home) if (item != package) item];
  if (existing == null) home.insert(at < 0 ? home.length : at, '$folderPrefix$id');
  return _tidyFolders(layout.copyWith(home: home, folders: folders), keep: id);
}

/// [layout] with [package] out of folder [folderId]. A folder left with one
/// app gives it back to the home screen in the folder's place.
LauncherLayout removeFromFolder(LauncherLayout layout, String folderId, String package) => _tidyFolders(layout.copyWith(folders: <LauncherFolder>[
      for (final LauncherFolder folder in layout.folders) folder.id == folderId ? folder.copyWith(apps: folder.apps.where((String app) => app != package).toList()) : folder,
    ]));

/// [layout] with folder [folderId] called [name] ("Folder" when blank).
LauncherLayout renameFolder(LauncherLayout layout, String folderId, String name) => layout.copyWith(folders: <LauncherFolder>[
      for (final LauncherFolder folder in layout.folders) folder.id == folderId ? folder.copyWith(name: name.trim().isEmpty ? 'Folder' : name.trim()) : folder,
    ]);

/// Folders with one app become that app, empty ones go (except [keep], just made).
LauncherLayout _tidyFolders(LauncherLayout layout, {String? keep}) {
  final List<String> home = <String>[];
  final List<LauncherFolder> folders = <LauncherFolder>[];
  final Map<String, LauncherFolder> byItem = <String, LauncherFolder>{for (final LauncherFolder folder in layout.folders) folder.homeItem: folder};
  for (final String item in layout.home) {
    final LauncherFolder? folder = byItem[item];
    if (folder == null) {
      home.add(item);
    } else if (folder.apps.length >= 2 || folder.id == keep) {
      home.add(item);
    } else if (folder.apps.length == 1) {
      home.add(folder.apps.single);
    }
  }
  for (final LauncherFolder folder in layout.folders) {
    if (folder.apps.length >= 2 || folder.id == keep) folders.add(folder);
  }
  return layout.copyWith(home: home, folders: folders);
}

String _newFolderId(LauncherLayout layout) {
  int next = 1;
  final Set<String> used = <String>{for (final LauncherFolder folder in layout.folders) folder.id};
  while (used.contains('$next')) {
    next++;
  }
  return '$next';
}

/// Where a home tile dragged by ([dx], [dy]) from slot [from] lands, in a grid
/// of [columns] cells [cellWidth] x [cellHeight], among [count] items: the
/// nearest cell, held to the first and last.
int dropIndex({required int from, required double dx, required double dy, required int columns, required double cellWidth, required double cellHeight, required int count}) {
  if (count <= 0) return 0;
  final int row = from ~/ columns + (dy / cellHeight).round();
  final int column = (from % columns + (dx / cellWidth).round()).clamp(0, columns - 1);
  return (row * columns + column).clamp(0, count - 1);
}

/// [items] with the one at [from] moved to [to], the rest shifting along.
List<String> moveItem(List<String> items, int from, int to) {
  if (from == to || from < 0 || from >= items.length) return List<String>.of(items);
  final List<String> out = List<String>.of(items);
  final String moved = out.removeAt(from);
  out.insert(to.clamp(0, out.length), moved);
  return out;
}

/// What a layout backup starts with, so a paste of anything else is refused.
const String layoutBackupHeader = 'dev-launcher-layout:';

/// [layout] as text to keep: copy it somewhere, paste it back to restore.
String layoutBackup(LauncherLayout layout) => '$layoutBackupHeader${layout.encode()}';

/// [layoutBackup]'s text back, or null when [text] is not one: a bad paste
/// must never write an empty layout over the person's.
LauncherLayout? restoreLayout(String text) {
  final String trimmed = text.trim();
  if (!trimmed.startsWith(layoutBackupHeader)) return null;
  try {
    final Object? decoded = jsonDecode(trimmed.substring(layoutBackupHeader.length));
    if (decoded is! Map) return null;
  } on FormatException {
    return null;
  }
  return LauncherLayout.decode(trimmed.substring(layoutBackupHeader.length));
}

/// [items] whose words (from [words]) start with, or contain, [query]; two
/// letters at least, since one is an app search.
List<T> matchKeywords<T>(List<T> items, String query, List<String> Function(T item) words) {
  final String wanted = query.trim().toLowerCase();
  if (wanted.length < 2) return <T>[];
  final List<T> starts = <T>[];
  final List<T> contains = <T>[];
  for (final T item in items) {
    final List<String> lower = <String>[for (final String word in words(item)) word.toLowerCase()];
    if (lower.any((String word) => word.startsWith(wanted) || word.split(RegExp(r'[\s\-&]+')).any((String part) => part.startsWith(wanted)))) {
      starts.add(item);
    } else if (lower.any((String word) => word.contains(wanted))) {
      contains.add(item);
    }
  }
  return <T>[...starts, ...contains];
}

/// The phone's browser on a search page for [query].
String webSearchUrl(String query) => 'https://www.google.com/search?q=${Uri.encodeComponent(query.trim())}';

/// A contact the search can offer: a name and a number to dial.
class const LauncherContact({required final String name, final String phone = ''});

/// [contacts] whose name has a word starting with [query], or whose number
/// holds its digits; two characters at least.
List<LauncherContact> matchContacts(List<LauncherContact> contacts, String query) {
  final String wanted = query.trim().toLowerCase();
  if (wanted.length < 2) return const <LauncherContact>[];
  final String digits = wanted.replaceAll(RegExp(r'[^0-9]'), '');
  return <LauncherContact>[
    for (final LauncherContact contact in contacts)
      if (contact.name.toLowerCase().split(RegExp(r'\s+')).any((String word) => word.startsWith(wanted)) || contact.name.toLowerCase().startsWith(wanted) || (digits.length >= 3 && digits.length == wanted.replaceAll(' ', '').length && contact.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits))) contact,
  ];
}

/// [apps] without the [hidden] ones.
List<LauncherApp> visibleApps(List<LauncherApp> apps, List<String> hidden) {
  if (hidden.isEmpty) return apps;
  final Set<String> out = hidden.toSet();
  return <LauncherApp>[for (final LauncherApp app in apps) if (!out.contains(app.packageName)) app];
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

/// The recent apps without [package], the order of the rest kept.
List<String> forgetRecent(List<String> recents, String package) => <String>[for (final String each in recents) if (each != package) each];

/// What each signal on the Recents diagnostics screen means, in plain words.
String describeSignal(String name, String detail) => switch (name) {
      'home' => 'Home pressed',
      'homeByService' => 'Recents service pressed Home to close the phone\'s Recents',
      'started' => 'Home screen started ($detail)',
      'back' => 'Back pressed',
      'backHandled' => 'Dev Launcher answered Back (closed $detail)',
      'recents' => 'Recents pressed (the phone said "recentapps")',
      'recentsReplaced' => 'Recents service showed our Recents (saw the $detail)',
      'closeSystemDialogs' => 'Phone closed its panels (reason: ${detail.isEmpty ? 'none given' : detail})',
      'pause' => 'Dev Launcher paused',
      'stop' => 'Dev Launcher went out of sight',
      'userLeaveHint' => 'Leaving Dev Launcher by a key or button',
      'focus' => detail == 'gained' ? 'Dev Launcher is in front again' : 'Something covered Dev Launcher',
      'window' => 'A window opened: $detail',
      'click' => 'A system button was pressed: $detail',
      _ => detail.isEmpty ? name : '$name: $detail',
    };

/// Seconds between two signal stamps (milliseconds), as the diagnostics
/// screen shows them: +0.4 s.
String sinceLabel(int at, int first) => '+${((at - first) / 1000).toStringAsFixed(1)} s';

/// The letters of the drawer's index, top to bottom: '#' (names that do not
/// start with a letter), then A to Z.
const List<String> indexLetters = <String>['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

/// The section a finger on [letter] in the index brings up: [letter]'s own
/// when it has apps, else the next letter down that has some, else the last
/// one above it; null when there are no apps at all.
String? sectionFor(String letter, Map<String, int> appsPerLetter) {
  bool has(String candidate) => (appsPerLetter[candidate] ?? 0) > 0;
  final int at = indexLetters.indexOf(letter);
  if (at < 0) return null;
  for (int next = at; next < indexLetters.length; next++) {
    if (has(indexLetters[next])) return indexLetters[next];
  }
  for (int previous = at - 1; previous >= 0; previous--) {
    if (has(indexLetters[previous])) return indexLetters[previous];
  }
  return null;
}

/// Where the dock's Recents button goes: where the phone's navigation bar
/// puts Recents ([device], the default), or a side the person chose.
enum RecentsSide { device, left, right }

/// The Recents glyph a phone's navigation bar draws: three lines (Tecno,
/// Infinix, itel, Xiaomi, and the fallback) or three upright bars (Samsung).
/// Never Android's square: people read the bar they know.
enum RecentsGlyph { lines, bars }

/// How the phone's own navigation bar shows Recents.
class const NavBarStyle({required final RecentsSide recentsSide, required final RecentsGlyph glyph});

/// The navigation bar of the phone whose launchable apps are [packages].
///
/// Android has no public call for the navigation bar's order, so the maker is
/// read from the apps it ships: HiOS/XOS (Tecno, Infinix, itel), One UI
/// (Samsung) and MIUI/HyperOS (Xiaomi, Redmi, POCO) put Recents on the left by
/// default; Android itself (Pixel and most others) on the right. A person who
/// swapped the buttons picks the side in Recents button settings.
NavBarStyle navBarStyleFor(Iterable<String> packages) {
  bool any(List<String> prefixes) => packages.any((String package) => prefixes.any(package.startsWith));
  if (any(const <String>['com.samsung.', 'com.sec.android.'])) return const NavBarStyle(recentsSide: RecentsSide.left, glyph: RecentsGlyph.bars);
  if (any(const <String>['com.transsion.', 'com.tecno.', 'com.infinix.', 'com.itel.', 'com.miui.', 'com.xiaomi.'])) return const NavBarStyle(recentsSide: RecentsSide.left, glyph: RecentsGlyph.lines);
  return const NavBarStyle(recentsSide: RecentsSide.right, glyph: RecentsGlyph.lines);
}

/// The side the Recents button takes: the [setting], or the phone's own
/// [style] when the setting is "follow device".
RecentsSide recentsSideFor(RecentsSide setting, NavBarStyle style) => setting == RecentsSide.device ? style.recentsSide : setting;

bool _dateDataReady = false;

/// [locale] as intl knows it: the full tag, else its language, else English.
String _dateLocale(String locale) {
  if (!_dateDataReady) {
    // Bundled with intl, so ready as soon as this returns.
    initializeDateFormatting();
    _dateDataReady = true;
  }
  return Intl.verifiedLocale(locale, DateFormat.localeExists, onFailure: (_) => 'en')!;
}

/// The time on the clock: 6:49 PM on a 12-hour phone, 18:49 on a 24-hour one,
/// with the phone's language for AM/PM and digits.
String clockText(DateTime time, {required bool use24, required String locale}) {
  final String known = _dateLocale(locale);
  return (use24 ? DateFormat.Hm(known) : DateFormat('h:mm a', known)).format(time);
}

/// The day and date under the clock, in the phone's language and order:
/// Sun, Nov 15 (US English), Sun 15 Nov (British English), dim. 15 nov.
String dayLine(DateTime time, {required String locale}) => DateFormat.MMMEd(_dateLocale(locale)).format(time);

/// Which edge of the drawer the letter index takes: the end of the phone's
/// reading direction ([device], the default), or a side the person chose.
enum IndexSide { device, left, right }

/// Whether the letter index goes on the left: the chosen [side], else the
/// end of the reading direction (left on a [rightToLeft] phone).
bool indexOnLeft(IndexSide side, {required bool rightToLeft}) => switch (side) {
      IndexSide.left => true,
      IndexSide.right => false,
      IndexSide.device => rightToLeft,
    };
