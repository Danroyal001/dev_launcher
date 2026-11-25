// What every screen of the launcher shares: the apps, their icons, the
// layout (home and dock) and the recent apps. Loaded once per process, in
// the order that keeps the first frame instant: the names saved by the last
// start, then Android's own list, then icons saved on the phone, then the
// icons still missing, a few at a time between frames. Apps installed or
// uninstalled while the launcher runs are picked up when it comes back to the
// front ([refreshApps]) and when a tap finds an app gone.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../dartvel_client/dartvel_client.dart';
import 'launcher_logic.dart';

const String layoutFile = 'dev-launcher/pins.json';
const String recentsFile = 'dev-launcher/recents.json';
const String appsFile = 'dev-launcher/apps.json';
const String iconFolder = 'dev-launcher/icons';

/// What the home screen says when Android answers that no app is installed.
const String emptyAppListProblem = 'Could not read your apps: Android listed none. The apps from the last start are shown.';

/// Shown where the device cannot list apps (a browser), clearly as examples.
const List<DVInstalledApp> previewApps = <DVInstalledApp>[
  DVInstalledApp(packageName: 'com.termux', label: 'Termux'),
  DVInstalledApp(packageName: 'com.github.android', label: 'GitHub'),
  DVInstalledApp(packageName: 'com.postman.app', label: 'Postman'),
  DVInstalledApp(packageName: 'com.android.chrome', label: 'Chrome'),
  DVInstalledApp(packageName: 'com.google.android.gm', label: 'Gmail'),
  DVInstalledApp(packageName: 'com.slack', label: 'Slack'),
  DVInstalledApp(packageName: 'com.spotify.music', label: 'Spotify'),
  DVInstalledApp(packageName: 'com.whatsapp', label: 'WhatsApp'),
  DVInstalledApp(packageName: 'com.google.android.dialer', label: 'Phone'),
  DVInstalledApp(packageName: 'com.google.android.apps.messaging', label: 'Messages'),
  DVInstalledApp(packageName: 'com.android.camera', label: 'Camera'),
  DVInstalledApp(packageName: 'com.android.calendar', label: 'Calendar'),
];

/// One moment of the launcher's state.
class const LauncherSnapshot({
  final List<DVInstalledApp> apps = const <DVInstalledApp>[],
  final LauncherLayout layout = const LauncherLayout(dockChosen: false),
  final List<String> recents = const <String>[],
  final bool preview = false,
  final bool loading = true,
  final bool isDefault = true,
  final String problem = '',
  final List<String> systemDock = const <String>[],
  final Map<String, int> badges = const <String, int>{},
}) {
  DVInstalledApp? app(String package) {
    for (final DVInstalledApp each in apps) {
      if (each.packageName == package) return each;
    }
    return null;
  }

  List<DVInstalledApp> appsFor(List<String> packages) => <DVInstalledApp>[for (final String package in packages) if (app(package) case final DVInstalledApp found) found];

  /// The apps opened last, newest first, that are still installed.
  List<DVInstalledApp> get recentApps => appsFor(recents);

  /// The dock: what the person chose; else the phone's own default phone,
  /// messages, camera and browser apps ([systemDock], from Android); else, where
  /// the phone cannot say, the usual packages for those roles.
  List<String> get dock {
    // A chosen dock with none of its apps installed (0.1.11 saved an empty
    // one on the owner's phone, 21 Nov) shows the phone's own apps instead.
    if (layout.dockChosen && appsFor(layout.dock).isNotEmpty) return layout.dock;
    if (systemDock.isNotEmpty) return systemDock;
    return defaultDock(<String>[for (final DVInstalledApp each in apps) each.packageName]);
  }

  List<LauncherApp> get launcherApps => <LauncherApp>[for (final DVInstalledApp each in apps) LauncherApp(packageName: each.packageName, label: each.label)];

  /// The apps the drawer and its search show: every app but the hidden ones.
  List<LauncherApp> get visibleLauncherApps => visibleApps(launcherApps, layout.hidden);

  /// How many notifications [package] is showing, when badges are on.
  int badgeFor(String package) => layout.options.badges ? (badges[package] ?? 0) : 0;

  /// How many notifications the apps in [folder] are showing between them.
  int folderBadge(LauncherFolder folder) => <int>[for (final String package in folder.apps) badgeFor(package)].fold(0, (int sum, int each) => sum + each);

  LauncherSnapshot copyWith({List<DVInstalledApp>? apps, LauncherLayout? layout, List<String>? recents, bool? preview, bool? loading, bool? isDefault, String? problem, List<String>? systemDock, Map<String, int>? badges}) => LauncherSnapshot(
        apps: apps ?? this.apps,
        layout: layout ?? this.layout,
        recents: recents ?? this.recents,
        preview: preview ?? this.preview,
        loading: loading ?? this.loading,
        isDefault: isDefault ?? this.isDefault,
        problem: problem ?? this.problem,
        systemDock: systemDock ?? this.systemDock,
        badges: badges ?? this.badges,
      );
}

/// The names of [apps] as the next start reads them before Android answers.
String encodeAppNames(List<DVInstalledApp> apps) => jsonEncode(<Object?>[
      for (final DVInstalledApp app in apps) <String, String>{'package': app.packageName, 'label': app.label},
    ]);

/// [encodeAppNames] back; anything unreadable is no apps.
List<DVInstalledApp> decodeAppNames(String text) {
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is! List) return const <DVInstalledApp>[];
    return <DVInstalledApp>[
      for (final Object? item in decoded)
        if (item is Map && item['package'] is String && '${item['package']}'.isNotEmpty) DVInstalledApp(packageName: '${item['package']}', label: '${item['label'] ?? item['package']}'),
    ];
  } on FormatException {
    return const <DVInstalledApp>[];
  }
}

/// The one store, shared by the home page and the app drawer.
class LauncherStore {
  /// A store of its own; the app uses [instance].
  LauncherStore({this.retryDelays = const <Duration>[Duration(milliseconds: 1500), Duration(seconds: 4)]});

  /// How long to wait before asking Android for the apps again when an answer
  /// was empty or failed. A home app starts with the phone, often before
  /// Android can list anything (owner, 18 Nov: empty home screen on 0.1.11).
  final List<Duration> retryDelays;

  static final LauncherStore instance = LauncherStore();

  final StreamController<LauncherSnapshot> _changes = StreamController<LauncherSnapshot>.broadcast();
  LauncherSnapshot _current = const LauncherSnapshot();
  bool _started = false;
  bool _listed = false;
  Future<void>? _refreshing;
  DateTime _listedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _soon;

  /// Why the saved layout could not be read, or null when it was. While it is
  /// set nothing saves the layout: saving would write the defaults over the
  /// person's pins (0.1.11 did, owner's Tecno, 21 Nov).
  String? _layoutUnreadable;

  String get _layoutProblem => _layoutUnreadable == null ? '' : 'Could not read your saved home screen ($_layoutUnreadable), so it is not changed until it can be.';

  LauncherSnapshot get current => _current;
  Stream<LauncherSnapshot> get changes => _changes.stream;

  DVDeviceStorage get _storage => DV.Platform.fileStorage;

  void _emit(LauncherSnapshot next) {
    _current = next;
    _changes.add(next);
  }

  /// Loads everything once; later calls only refresh the home-app check.
  Future<void> start() async {
    if (_started) {
      await refreshDefault();
      return;
    }
    _started = true;
    final DVApps platform = DV.Platform.apps;
    final LauncherLayout layout = await _readLayout();
    if (!platform.isSupported) {
      // A browser preview: example apps, and recents kept for this visit only.
      _emit(_current.copyWith(apps: previewApps, layout: layout, preview: true, loading: false, isDefault: true));
      return;
    }
    final List<String> recents = decodeRecents(await _readText(recentsFile));
    // The names the last start saw: the screen is full at once, even while a
    // phone with many apps is still answering.
    final List<DVInstalledApp> remembered = decodeAppNames(await _readText(appsFile));
    _emit(_current.copyWith(layout: layout, recents: recents, apps: remembered, loading: remembered.isEmpty));
    _followSystem();
    await _listOrRetry();
  }

  /// Asks Android for the apps, again after each of [retryDelays] while the
  /// answer is empty or an error. When none works the apps from the last
  /// start stay, the home screen says why, and [refreshApps] (each return to
  /// the front) asks again.
  Future<void> _listOrRetry() async {
    String? problem;
    for (int attempt = 0; attempt <= retryDelays.length; attempt += 1) {
      if (attempt > 0) await Future<void>.delayed(retryDelays[attempt - 1]);
      try {
        // Names only: one quick question to the system.
        final List<DVInstalledApp> apps = await DV.Platform.apps.list(icons: false);
        // A phone always has apps to open (Settings, and this launcher
        // itself): an empty answer is a question that failed, not a phone
        // with nothing on it.
        if (apps.isNotEmpty) {
          await _applyFirstList(apps);
          return;
        }
        problem = emptyAppListProblem;
      } on Object catch (error) {
        problem = 'Could not read your apps: $error';
      }
    }
    // Keep the names from the last start rather than wiping the home row and
    // the dock, and say so.
    _emit(_current.copyWith(loading: false, problem: _layoutUnreadable == null ? problem : '$problem $_layoutProblem'));
  }

  Future<void> _applyFirstList(List<DVInstalledApp> apps) async {
    _listed = true;
    _listedAt = DateTime.now();
    _emit(_current.copyWith(apps: apps, loading: false, problem: _layoutProblem));
    await _forgetUninstalled();
    unawaited(_writeText(appsFile, encodeAppNames(apps)));
    unawaited(refreshDefault());
    unawaited(_readSystemDock());
    await _fillIcons();
  }

  /// Asks Android for the apps again and applies what changed: new apps
  /// appear (only their icons are drawn), uninstalled ones leave the list,
  /// the recents and the icon cache. Called when the launcher comes back to
  /// the front, which is when an install or uninstall can have happened.
  Future<void> refreshApps() async {
    if (_current.preview || !_started) return;
    // A start that could not read the saved layout reads it again first.
    if (_layoutUnreadable != null) await _retryLayout();
    // The first start never got the list: ask for it again, as start does.
    if (!_listed) return _refreshing ??= _listOrRetry().whenComplete(() => _refreshing = null);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  /// [refreshApps] for the moment the launcher is back in front: after
  /// [delay], once the home screen is drawn and answering, and only when the
  /// last look is older than [freshFor]. Asking Android for every app takes
  /// seconds on a slow phone; doing it in the moment of returning, on every
  /// return, froze the home screen (owner's Tecno, 0.1.7).
  void refreshAppsSoon({Duration delay = const Duration(seconds: 2), Duration freshFor = const Duration(seconds: 30)}) {
    _soon?.cancel();
    _soon = Timer(delay, () {
      if (DateTime.now().difference(_listedAt) < freshFor) return;
      unawaited(refreshApps());
    });
  }

  Future<void> _refresh() async {
    final List<DVInstalledApp> fresh;
    try {
      fresh = await DV.Platform.apps.list(icons: false);
      _listedAt = DateTime.now();
    } on Object {
      return;
    }
    if (fresh.isEmpty) return;
    final AppListChange change = appListChange(
      before: <String>[for (final DVInstalledApp app in _current.apps) app.packageName],
      after: <String>[for (final DVInstalledApp app in fresh) app.packageName],
    );
    final bool renamed = !change.isEmpty || fresh.any((DVInstalledApp app) => _current.app(app.packageName)?.label != app.label);
    if (!renamed) return;
    final Map<String, Uint8List> icons = <String, Uint8List>{
      for (final DVInstalledApp app in _current.apps)
        if (app.icon case final Uint8List icon) app.packageName: icon,
    };
    _emit(_current.copyWith(apps: _withIcons(fresh, icons)));
    unawaited(_writeText(appsFile, encodeAppNames(fresh)));
    for (final String package in change.removed) {
      unawaited(_storage.delete(_iconPath(package)).catchError((Object _) {}));
    }
    await _forgetUninstalled();
    for (final String package in change.added) {
      final Uint8List? png = await _drawIcon(package);
      if (png != null) icons[package] = png;
    }
    if (change.added.isNotEmpty) _emit(_current.copyWith(apps: _withIcons(_current.apps, icons)));
  }

  /// Drops uninstalled apps from the recents, and saves the list if it changed.
  Future<void> _forgetUninstalled() async {
    final List<String> kept = keepInstalled(_current.recents, <String>{for (final DVInstalledApp app in _current.apps) app.packageName});
    if (kept.length == _current.recents.length) return;
    _emit(_current.copyWith(recents: kept));
    await _writeText(recentsFile, encodeRecents(kept));
  }

  /// Opens [package] and puts it first in the recent apps; or says why it
  /// could not, and checks whether the app is gone.
  Future<String> open(String package) async {
    if (_current.preview) {
      _emit(_current.copyWith(recents: recordLaunch(_current.recents, package)));
      return 'Preview: on your phone this opens the app.';
    }
    final String label = _current.app(package)?.label ?? package;
    try {
      await DV.Platform.apps.open(package);
    } on Object catch (error) {
      // Most often the app was uninstalled: the tile goes with the message.
      await refreshApps();
      if (_listed && _current.app(package) == null) return '$label is no longer installed.';
      return '$error'.replaceFirst('Bad state: ', '');
    }
    final List<String> recents = recordLaunch(_current.recents, package);
    _emit(_current.copyWith(recents: recents));
    unawaited(_writeText(recentsFile, encodeRecents(recents)));
    return '';
  }

  /// Takes [package] out of the recent apps (it stays installed).
  Future<void> forgetRecentApp(String package) => _saveRecents(forgetRecent(_current.recents, package));

  /// Empties the recent apps.
  Future<void> clearRecents() => _saveRecents(const <String>[]);

  Future<void> _saveRecents(List<String> recents) async {
    _emit(_current.copyWith(recents: recents));
    if (!_current.preview) await _writeText(recentsFile, encodeRecents(recents));
  }

  /// The phone's own default apps for the dock's four roles, in dock order.
  Future<void> _readSystemDock() async {
    final List<String> dock = <String>[];
    for (final DVAppRole role in const <DVAppRole>[DVAppRole.phone, DVAppRole.messages, DVAppRole.camera, DVAppRole.browser]) {
      try {
        final String? package = await DV.Platform.apps.defaultFor(role);
        if (package != null && !dock.contains(package) && _current.app(package) != null) dock.add(package);
      } on Object {
        // A phone that cannot say keeps the usual packages for that role.
      }
    }
    if (dock.isNotEmpty) _emit(_current.copyWith(systemDock: dock));
  }

  /// Whether Dev Launcher is the phone's home app now.
  Future<void> refreshDefault() async {
    if (_current.preview) return;
    try {
      final bool isDefault = await DV.Platform.apps.isDefaultLauncher();
      if (isDefault != _current.isDefault) _emit(_current.copyWith(isDefault: isDefault));
    } on Object {
      // A phone that cannot say is treated as already the home app: no
      // banner nagging about something it cannot change.
    }
  }

  /// Asks Android to make Dev Launcher the home app.
  Future<String> askToBeDefault() async {
    try {
      await DV.Platform.apps.requestDefaultLauncher();
      return '';
    } on Object catch (error) {
      return '$error'.replaceFirst('Bad state: ', '');
    }
  }

  String _iconPath(String package) => '$iconFolder/$package.png';

  /// [package]'s icon from Android, saved for the next start.
  Future<Uint8List?> _drawIcon(String package) async {
    try {
      final Uint8List? png = await DV.Platform.apps.icon(package);
      if (png != null) unawaited(_storage.put(_iconPath(package), png).catchError((Object _) {}));
      return png;
    } on Object {
      // An app whose icon will not draw keeps its letter tile.
      return null;
    }
  }

  Future<Uint8List?> _savedIcon(String package) async {
    try {
      if (!await _storage.exists(_iconPath(package))) return null;
      return Uint8List.fromList(await _storage.get(_iconPath(package)));
    } on Object {
      // A broken saved icon is drawn again.
      return null;
    }
  }

  Future<void> _fillIcons() async {
    // Icons saved on an earlier start: read together, no drawing at all.
    final List<String> packages = <String>[for (final DVInstalledApp app in _current.apps) app.packageName];
    final List<Uint8List?> saved = await Future.wait(packages.map(_savedIcon));
    final Map<String, Uint8List> icons = <String, Uint8List>{
      for (int index = 0; index < packages.length; index++)
        if (saved[index] case final Uint8List icon) packages[index]: icon,
    };
    if (icons.isNotEmpty) _emit(_current.copyWith(apps: _withIcons(_current.apps, icons)));

    // The rest, a few at a time with a frame between, so scrolling and typing
    // never wait for icons.
    final List<String> missing = <String>[for (final String package in packages) if (!icons.containsKey(package)) package];
    const int batch = 6;
    for (int start = 0; start < missing.length; start += batch) {
      for (final String package in missing.skip(start).take(batch)) {
        final Uint8List? png = await _drawIcon(package);
        if (png != null) icons[package] = png;
      }
      _emit(_current.copyWith(apps: _withIcons(_current.apps, icons)));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  List<DVInstalledApp> _withIcons(List<DVInstalledApp> apps, Map<String, Uint8List> icons) => <DVInstalledApp>[
        for (final DVInstalledApp app in apps)
          if (app.icon == null && icons[app.packageName] != null) DVInstalledApp(packageName: app.packageName, label: app.label, icon: icons[app.packageName]) else app,
      ];

  Future<String> _readText(String file) async {
    try {
      if (!await _storage.exists(file)) return '';
      return utf8.decode(await _storage.get(file));
    } on Object {
      return '';
    }
  }

  Future<void> _writeText(String file, String text) async {
    try {
      await _storage.put(file, utf8.encode(text));
    } on Object {
      // Not kept this time; the next change tries again.
    }
  }

  Future<LauncherLayout> _readLayout() async {
    try {
      final String text = await _storage.exists(layoutFile) ? utf8.decode(await _storage.get(layoutFile)) : '';
      _layoutUnreadable = null;
      return text.isEmpty ? const LauncherLayout(dockChosen: false) : LauncherLayout.decode(text);
    } on Object catch (error) {
      // Not "nothing saved": something is saved and could not be read.
      _layoutUnreadable = '$error';
      return const LauncherLayout(dockChosen: false);
    }
  }

  /// Reads the saved layout again after a start that could not, and shows it.
  Future<void> _retryLayout() async {
    final LauncherLayout layout = await _readLayout();
    if (_layoutUnreadable != null) return;
    final bool layoutProblem = _current.problem.startsWith('Could not read your saved home screen');
    _emit(_current.copyWith(layout: layout, problem: layoutProblem ? '' : _current.problem));
  }

  /// Keeps [layout] and shows it at once.
  Future<String> saveLayout(LauncherLayout layout) async {
    if (_layoutUnreadable != null) return _layoutProblem;
    _emit(_current.copyWith(layout: layout));
    try {
      await _storage.put(layoutFile, utf8.encode(layout.encode()));
      return '';
    } on Object catch (error) {
      return 'Could not save: $error';
    }
  }

  Future<String> pinHome(String package, {required bool pinned}) {
    final LauncherLayout layout = _current.layout;
    final List<String> home = pinned ? <String>[...layout.home.where((String p) => p != package), package] : layout.home.where((String p) => p != package).toList();
    return saveLayout(_current.layout.copyWith(home: home, dock: _current.dock, dockChosen: true));
  }

  Future<String> pinDock(String package, {required bool pinned}) {
    // The first change to the dock starts from what it shows now.
    final List<String> dock = _current.dock;
    final List<String> next = pinned ? <String>[...dock.where((String p) => p != package), package].take(5).toList() : dock.where((String p) => p != package).toList();
    return saveLayout(_current.layout.copyWith(dock: next, dockChosen: true));
  }

  /// Puts the dock's Recents button on [side], or back where the phone's
  /// navigation bar has Recents ([RecentsSide.device]). The dock itself is
  /// left as it is (still the phone's defaults if never edited).
  Future<String> setRecentsSide(RecentsSide side) => saveLayout(_current.layout.copyWith(recentsSide: side));

  /// Puts the drawer's letter index on [side], or back on the end of the
  /// phone's reading direction ([IndexSide.device]).
  Future<String> setIndexSide(IndexSide side) => saveLayout(_current.layout.copyWith(indexSide: side));

  StreamSubscription<DVPackageChange>? _packageChanges;
  StreamSubscription<Map<String, int>>? _badgeCounts;

  /// Installs, uninstalls and updates as Android broadcasts them, and the
  /// notification counts for badges, for as long as the launcher runs.
  void _followSystem() {
    _packageChanges ??= DV.Platform.apps.packageChanges.listen((DVPackageChange change) {
      // Asked now, not on the next return to the front: the drawer is open
      // while an app installs from the Play Store.
      unawaited(refreshApps());
    }, onError: (Object _) {});
    _badgeCounts ??= DV.Platform.apps.notificationCounts.listen((Map<String, int> counts) {
      _emit(_current.copyWith(badges: counts));
    }, onError: (Object _) {});
  }

  /// [package] off the drawer and its search ([hidden]), or back on. Its
  /// place on the home screen or in the dock is kept.
  Future<String> hideApp(String package, {required bool hidden}) {
    final List<String> next = hidden ? <String>[..._current.layout.hidden.where((String each) => each != package), package] : _current.layout.hidden.where((String each) => each != package).toList();
    return saveLayout(_current.layout.copyWith(hidden: next, dock: _current.dock, dockChosen: true));
  }

  /// [package] into folder [folderId], or a new folder called [name].
  Future<String> putInFolder(String package, {String? folderId, String name = 'Folder'}) =>
      saveLayout(addToFolder(_current.layout.copyWith(dock: _current.dock, dockChosen: true), package, folderId: folderId, folderName: name));

  /// [package] out of folder [folderId], onto the home screen if the folder
  /// is left with one app.
  Future<String> takeOutOfFolder(String folderId, String package) => saveLayout(removeFromFolder(_current.layout, folderId, package));

  /// Folder [folderId] called [name].
  Future<String> nameFolder(String folderId, String name) => saveLayout(renameFolder(_current.layout, folderId, name));

  /// The home screen item at [from] moved to [to].
  Future<String> moveHomeItem(int from, int to) => saveLayout(_current.layout.copyWith(home: moveItem(_current.layout.home, from, to), dock: _current.dock, dockChosen: true));

  /// The launcher's own settings.
  Future<String> setOptions(LauncherOptions options) => saveLayout(_current.layout.copyWith(options: options));

  /// A layout from a backup, in place of this one.
  Future<String> restore(LauncherLayout layout) => saveLayout(layout);

  /// The phone's contacts, for the search (asks for the permission the first
  /// time). Empty when the person said no or the phone cannot say.
  Future<List<LauncherContact>> contacts() async {
    if (_contacts != null) return _contacts!;
    if (_current.preview) return const <LauncherContact>[];
    try {
      final List<Map<String, String>> found = await DV.Platform.contacts.getContacts();
      _contacts = <LauncherContact>[for (final Map<String, String> each in found) if ((each['name'] ?? '').isNotEmpty) LauncherContact(name: each['name']!, phone: each['phone'] ?? '')];
    } on Object {
      return const <LauncherContact>[];
    }
    return _contacts!;
  }

  List<LauncherContact>? _contacts;
}
