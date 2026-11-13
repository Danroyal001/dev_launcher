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
    if (layout.dockChosen) return layout.dock;
    if (systemDock.isNotEmpty) return systemDock;
    return defaultDock(<String>[for (final DVInstalledApp each in apps) each.packageName]);
  }

  List<LauncherApp> get launcherApps => <LauncherApp>[for (final DVInstalledApp each in apps) LauncherApp(packageName: each.packageName, label: each.label)];

  LauncherSnapshot copyWith({List<DVInstalledApp>? apps, LauncherLayout? layout, List<String>? recents, bool? preview, bool? loading, bool? isDefault, String? problem, List<String>? systemDock}) => LauncherSnapshot(
        apps: apps ?? this.apps,
        layout: layout ?? this.layout,
        recents: recents ?? this.recents,
        preview: preview ?? this.preview,
        loading: loading ?? this.loading,
        isDefault: isDefault ?? this.isDefault,
        problem: problem ?? this.problem,
        systemDock: systemDock ?? this.systemDock,
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
  LauncherStore();

  static final LauncherStore instance = LauncherStore();

  final StreamController<LauncherSnapshot> _changes = StreamController<LauncherSnapshot>.broadcast();
  LauncherSnapshot _current = const LauncherSnapshot();
  bool _started = false;
  bool _listed = false;
  Future<void>? _refreshing;

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
    List<DVInstalledApp> apps;
    try {
      // Names only: one quick question to the system.
      apps = await platform.list(icons: false);
    } on Object catch (error) {
      _emit(_current.copyWith(loading: false, problem: 'Could not read your apps: $error'));
      return;
    }
    _listed = true;
    _emit(_current.copyWith(apps: apps, loading: false));
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
  Future<void> refreshApps() {
    if (!_listed || _current.preview) return Future<void>.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final List<DVInstalledApp> fresh;
    try {
      fresh = await DV.Platform.apps.list(icons: false);
    } on Object {
      return;
    }
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
    final String text = await _readText(layoutFile);
    return text.isEmpty ? const LauncherLayout(dockChosen: false) : LauncherLayout.decode(text);
  }

  /// Keeps [layout] and shows it at once.
  Future<String> saveLayout(LauncherLayout layout) async {
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
    return saveLayout(LauncherLayout(home: home, dock: _current.dock, dockChosen: true));
  }

  Future<String> pinDock(String package, {required bool pinned}) {
    // The first change to the dock starts from what it shows now.
    final List<String> dock = _current.dock;
    final List<String> next = pinned ? <String>[...dock.where((String p) => p != package), package].take(5).toList() : dock.where((String p) => p != package).toList();
    return saveLayout(LauncherLayout(home: _current.layout.home, dock: next, dockChosen: true));
  }
}
