// What every screen of the launcher shares: the apps, their icons and the
// layout (home and dock). Loaded once per process, in the order that keeps
// the first frame instant: names, then icons saved on the phone, then the
// icons still missing, a few at a time between frames.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../dartvel_client/dartvel_client.dart';
import 'launcher_logic.dart';

const String layoutFile = 'dev-launcher/pins.json';
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
  final bool preview = false,
  final bool loading = true,
  final bool isDefault = true,
  final String problem = '',
}) {
  DVInstalledApp? app(String package) {
    for (final DVInstalledApp each in apps) {
      if (each.packageName == package) return each;
    }
    return null;
  }

  List<DVInstalledApp> appsFor(List<String> packages) => <DVInstalledApp>[for (final String package in packages) if (app(package) case final DVInstalledApp found) found];

  /// The dock: what the person chose, else the phone's usual four.
  List<String> get dock => layout.dockChosen ? layout.dock : defaultDock(<String>[for (final DVInstalledApp each in apps) each.packageName]);

  List<LauncherApp> get launcherApps => <LauncherApp>[for (final DVInstalledApp each in apps) LauncherApp(packageName: each.packageName, label: each.label)];

  LauncherSnapshot copyWith({List<DVInstalledApp>? apps, LauncherLayout? layout, bool? preview, bool? loading, bool? isDefault, String? problem}) => LauncherSnapshot(
        apps: apps ?? this.apps,
        layout: layout ?? this.layout,
        preview: preview ?? this.preview,
        loading: loading ?? this.loading,
        isDefault: isDefault ?? this.isDefault,
        problem: problem ?? this.problem,
      );
}

/// The one store, shared by the home page and the app drawer.
class LauncherStore {
  LauncherStore._();

  static final LauncherStore instance = LauncherStore._();

  final StreamController<LauncherSnapshot> _changes = StreamController<LauncherSnapshot>.broadcast();
  LauncherSnapshot _current = const LauncherSnapshot();
  bool _started = false;

  LauncherSnapshot get current => _current;
  Stream<LauncherSnapshot> get changes => _changes.stream;

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
      _emit(_current.copyWith(apps: previewApps, layout: layout, preview: true, loading: false, isDefault: true));
      return;
    }
    List<DVInstalledApp> apps;
    try {
      // Names only: one quick question to the system, so the first screen
      // has every app on it at once.
      apps = await platform.list(icons: false);
    } on Object catch (error) {
      _emit(_current.copyWith(apps: const <DVInstalledApp>[], layout: layout, loading: false, problem: 'Could not read your apps: $error'));
      return;
    }
    _emit(_current.copyWith(apps: apps, layout: layout, loading: false));
    unawaited(refreshDefault());
    await _fillIcons();
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

  Future<void> _fillIcons() async {
    final DVDeviceStorage storage = DV.Platform.fileStorage;
    // Icons saved on an earlier start: no drawing at all.
    final Map<String, Uint8List> icons = <String, Uint8List>{};
    for (final DVInstalledApp app in _current.apps) {
      try {
        if (await storage.exists(_iconPath(app.packageName))) icons[app.packageName] = Uint8List.fromList(await storage.get(_iconPath(app.packageName)));
      } on Object {
        // A broken cached icon is drawn again below.
      }
    }
    if (icons.isNotEmpty) _emit(_current.copyWith(apps: _withIcons(_current.apps, icons)));

    // The rest, a few at a time with a frame between, so scrolling and typing
    // never wait for icons.
    final List<String> missing = <String>[for (final DVInstalledApp app in _current.apps) if (!icons.containsKey(app.packageName)) app.packageName];
    const int batch = 6;
    for (int start = 0; start < missing.length; start += batch) {
      for (final String package in missing.skip(start).take(batch)) {
        try {
          final Uint8List? png = await DV.Platform.apps.icon(package);
          if (png == null) continue;
          icons[package] = png;
          unawaited(storage.put(_iconPath(package), png).catchError((Object _) {}));
        } on Object {
          // An app whose icon will not draw keeps its letter tile.
        }
      }
      _emit(_current.copyWith(apps: _withIcons(_current.apps, icons)));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  List<DVInstalledApp> _withIcons(List<DVInstalledApp> apps, Map<String, Uint8List> icons) => <DVInstalledApp>[
        for (final DVInstalledApp app in apps)
          if (app.icon == null && icons[app.packageName] != null) DVInstalledApp(packageName: app.packageName, label: app.label, icon: icons[app.packageName]) else app,
      ];

  Future<LauncherLayout> _readLayout() async {
    try {
      final DVDeviceStorage storage = DV.Platform.fileStorage;
      if (!await storage.exists(layoutFile)) return const LauncherLayout(dockChosen: false);
      return LauncherLayout.decode(utf8.decode(await storage.get(layoutFile)));
    } on Object {
      return const LauncherLayout(dockChosen: false);
    }
  }

  /// Keeps [layout] and shows it at once.
  Future<String> saveLayout(LauncherLayout layout) async {
    _emit(_current.copyWith(layout: layout));
    try {
      await DV.Platform.fileStorage.put(layoutFile, utf8.encode(layout.encode()));
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
    final List<String> dock = _current.dock;
    final List<String> next = pinned ? <String>[...dock.where((String p) => p != package), package].take(5).toList() : dock.where((String p) => p != package).toList();
    return saveLayout(LauncherLayout(home: _current.layout.home, dock: next, dockChosen: true));
  }
}
