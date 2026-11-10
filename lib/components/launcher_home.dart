// The home screen: a clock, a prompt that opens apps and runs commands,
// pinned apps, the developer's tools, and every app A to Z.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import 'theme.dart';

const String pinsFile = 'dev-launcher/pins.json';

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
];

const Set<String> commandWords = <String>{'info', 'pin', 'unpin', 'uninstall'};

/// What a launcher screen knows: the apps, the pins, and whether the apps
/// are examples because this device cannot list its own.
class const LauncherState({
  final List<DVInstalledApp> apps = const <DVInstalledApp>[],
  final List<String> pins = const <String>[],
  final bool preview = false,
  final bool loading = true,
});

DVInstalledApp? appByPackage(List<DVInstalledApp> apps, String package) {
  for (final DVInstalledApp app in apps) {
    if (app.packageName == package) return app;
  }
  return null;
}

Future<List<String>> readPins() async {
  try {
    final DVDeviceStorage storage = DV.Platform.fileStorage;
    if (!await storage.exists(pinsFile)) return <String>[];
    final Object? decoded = jsonDecode(utf8.decode(await storage.get(pinsFile)));
    return decoded is List ? <String>[for (final Object? item in decoded) '$item'] : <String>[];
  } on Object {
    return <String>[];
  }
}

/// Keeps [pins] on the phone.
Future<void> writePins(List<String> pins) => DV.Platform.fileStorage.put(pinsFile, utf8.encode(jsonEncode(pins)));

/// The day and date under the clock: Tue 10 Nov.
String dayLine(DateTime now) {
  const List<String> days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

@DVFunctionalWidget()
Widget _launcherHome(BuildContext context) {
  final DVSignal<LauncherState> state = context.signal(const LauncherState());
  final DVSignal<String> typed = context.signal('');
  final DVSignal<String> status = context.signal('');
  final DVSignal<DateTime> now = context.signal(DateTime.now());
  final DVSignal<bool> started = context.signal(false);

  Future<void> load() async {
    final DVApps platformApps = DV.Platform.apps;
    List<DVInstalledApp> found = previewApps;
    bool preview = true;
    if (platformApps.isSupported) {
      preview = false;
      try {
        found = await platformApps.list();
      } on Object catch (error) {
        found = const <DVInstalledApp>[];
        status.value = 'Could not read your apps: $error';
      }
    }
    final List<String> pins = await readPins();
    state.value = LauncherState(
      apps: found,
      preview: preview,
      loading: false,
      pins: pins.where((String package) => appByPackage(found, package) != null).toList(),
    );
  }

  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      load();
      // The clock: a minute is the finest the screen shows. The timer stops
      // itself once this screen is gone.
      Timer.periodic(const Duration(seconds: 15), (Timer timer) {
        if (!context.mounted) {
          timer.cancel();
          return;
        }
        now.value = DateTime.now();
      });
    });
  }

  Future<void> savePins(List<String> pins) async {
    state.value = LauncherState(apps: state.read().apps, preview: state.read().preview, loading: false, pins: pins);
    try {
      await writePins(pins);
    } on Object catch (error) {
      status.value = 'Could not save pins: $error';
    }
  }

  Future<void> act(LauncherAction action, String package) async {
    final LauncherState current = state.read();
    final DVInstalledApp? app = appByPackage(current.apps, package);
    if (app == null) return;
    if (current.preview && action != LauncherAction.pin && action != LauncherAction.unpin) {
      status.value = 'Preview: on your phone this would ${action.name} ${app.label}.';
      return;
    }
    try {
      switch (action) {
        case .open:
          await DV.Platform.apps.open(package);
          typed.value = '';
        case .info:
          await DV.Platform.apps.openSettings(package);
        case .uninstall:
          await DV.Platform.apps.uninstall(package);
        case .pin:
          if (!current.pins.contains(package)) await savePins(<String>[...current.pins, package]);
          status.value = 'Pinned ${app.label}.';
        case .unpin:
          await savePins(current.pins.where((String pinned) => pinned != package).toList());
          status.value = 'Unpinned ${app.label}.';
        case .none:
          break;
      }
    } on Object catch (error) {
      status.value = '$error'.replaceFirst('Bad state: ', '');
    }
  }

  List<LauncherApp> launcherApps() => <LauncherApp>[for (final DVInstalledApp app in state.read().apps) LauncherApp(packageName: app.packageName, label: app.label)];

  void submit() {
    final LauncherCommand command = parseCommand(typed.read(), launcherApps());
    if (command.action == LauncherAction.none) {
      status.value = command.message;
      return;
    }
    act(command.action, command.app!.packageName);
    if (command.action == LauncherAction.pin || command.action == LauncherAction.unpin) typed.value = '';
  }

  final LauncherState current = state.value;
  final String query = typed.value;
  final List<String> words = query.trim().split(' ');
  final String search = words.length > 1 && commandWords.contains(words.first.toLowerCase()) ? query.substring(query.indexOf(' ') + 1) : query;
  final List<DVInstalledApp> matches = <DVInstalledApp>[
    for (final LauncherApp app in matchApps(<LauncherApp>[for (final DVInstalledApp each in current.apps) LauncherApp(packageName: each.packageName, label: each.label)], search))
      if (appByPackage(current.apps, app.packageName) case final DVInstalledApp found) found,
  ];
  final List<DVInstalledApp> pinned = <DVInstalledApp>[for (final String package in current.pins) if (appByPackage(current.apps, package) case final DVInstalledApp app) app];
  final List<DVInstalledApp> devTools = current.apps.where((DVInstalledApp app) => isDevTool(app.packageName)).toList();
  final double width = MediaQuery.sizeOf(context).width;
  final int columns = ((width - 24) / 96).floor().clamp(3, 10);
  final DateTime time = now.value;

  return DVBox.list(<Widget>[
    if (current.preview)
      DVText('Preview. Dev Launcher is an Android home screen; here it shows example apps. Install it on Android to see yours.').modifier(
        mono(size: 13, color: LauncherColors.muted).backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(10).padding(14),
      ),
    DVBox.list(<Widget>[
      DVText('${twoDigits(time.hour)}:${twoDigits(time.minute)}').modifier(mono(size: 64, bold: true).lineHeight(1).semanticHeading(1).semanticLabel('Dev Launcher, ${twoDigits(time.hour)}:${twoDigits(time.minute)}')),
      DVText('${dayLine(time)} · ${current.apps.length} apps').modifier(mono(size: 15, color: LauncherColors.muted)),
    ], spacing: 8),
    DVBox.row(<Widget>[
      DVText('❯').modifier(mono(size: 18, bold: true, color: LauncherColors.accent)),
      DVText(query).modifier(
        mono(size: 16).input(
          label: 'Command',
          hint: 'open an app or run a command',
          onChanged: (String value) {
            typed.value = value;
            status.value = '';
          },
          onSubmitted: submit,
        ),
      ),
    ], spacing: 10, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(10).paddingSymmetric(horizontal: 14, vertical: 4)),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13, color: LauncherColors.muted).semanticRole('status')),
    if (query.trim().isNotEmpty) ...<Widget>[
      for (final DVInstalledApp app in matches.take(6)) MatchRow(app: app, pinned: current.pins.contains(app.packageName), onAction: (LauncherAction action) => act(action, app.packageName)),
      if (matches.isEmpty) DVText('Enter runs it. Try: info, pin, unpin, uninstall + an app.').modifier(mono(size: 13, color: LauncherColors.muted)),
    ],
    if (pinned.isNotEmpty) AppSection(title: 'pinned', apps: pinned, columns: columns, onOpen: (String package) => act(.open, package)),
    if (devTools.isNotEmpty) AppSection(title: 'dev tools', apps: devTools, columns: columns, onOpen: (String package) => act(.open, package)),
    AppSection(title: current.loading ? 'reading apps…' : 'all apps · ${current.apps.length}', apps: current.apps, columns: columns, onOpen: (String package) => act(.open, package)),
  ], spacing: 24, modifier: DVModifier().backgroundColor(LauncherColors.page).paddingOnly(left: 20, right: 20, top: 28, bottom: 32).minHeight(MediaQuery.sizeOf(context).height)).scrollable();
}

/// A labelled group of app tiles.
@DVFunctionalWidget()
Widget _appSection(BuildContext context, {required String title, required List<DVInstalledApp> apps, required int columns, required ValueChanged<String> onOpen}) =>
    DVBox.list(<Widget>[
      DVText('// $title').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(2)),
      if (apps.isNotEmpty)
        DVBox.grid(<Widget>[for (final DVInstalledApp app in apps) AppTile(app: app, onOpen: () => onOpen(app.packageName))], columns: columns, spacing: 4, responsive: false),
    ], spacing: 10);

/// An app's icon, or its first letter on a tile when it has none.
@DVFunctionalWidget()
Widget _appIcon(BuildContext context, {required DVInstalledApp app, double size = 52}) {
  final List<int>? icon = app.icon;
  if (icon != null && icon.isNotEmpty) return DVBox.image(DVImage.memory(icon, alt: ''), width: size, height: size, fit: BoxFit.contain);
  return DVBox(
    DVText(app.label.isEmpty ? '?' : app.label.substring(0, 1).toUpperCase()).modifier(mono(size: size * 0.42, bold: true, color: LauncherColors.accent).align(Alignment.center)),
    DVModifier().width(size).height(size).backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(size * 0.28).centered(),
  );
}

@DVFunctionalWidget()
Widget _appTile(BuildContext context, {required DVInstalledApp app, required VoidCallback onOpen}) => DVBox.list(<Widget>[
      AppIcon(app: app),
      DVText(app.label).modifier(mono(size: 12).maxLines(1).overflow(TextOverflow.ellipsis)),
    ], spacing: 6, crossAlign: DVCrossAlign.center, modifier: DVModifier().padding(6).rounded(12).semanticLabel(app.label).tooltip('Open ${app.label}').onTap(onOpen));

/// A search result: the app, its package, and what can be done with it.
@DVFunctionalWidget()
Widget _matchRow(BuildContext context, {required DVInstalledApp app, required bool pinned, required ValueChanged<LauncherAction> onAction}) {
  Widget action(String label, LauncherAction what, String hint, {Color color = LauncherColors.muted}) => DVText(label).modifier(
        mono(size: 13, color: color).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 44, height: 44).tooltip(hint).onTap(() => onAction(what)),
      );
  return DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      AppIcon(app: app, size: 32),
      DVBox.list(<Widget>[
        DVText(app.label).modifier(mono(size: 15)),
        DVText(app.packageName).modifier(mono(size: 11, color: LauncherColors.muted)),
      ], spacing: 2),
    ], spacing: 12, crossAlign: DVCrossAlign.start, modifier: DVModifier().paddingSymmetric(vertical: 4).semanticLabel(app.label).tooltip('Open ${app.label}').onTap(() => onAction(.open))),
    DVBox.wrapLine(<Widget>[
      action('open', .open, 'Open ${app.label}', color: LauncherColors.accent),
      action(pinned ? 'unpin' : 'pin', pinned ? .unpin : .pin, pinned ? 'Take ${app.label} off the pinned row' : 'Pin ${app.label} to the home screen'),
      action('info', .info, 'The system page for ${app.label}'),
      action('uninstall', .uninstall, 'Ask Android to uninstall ${app.label}', color: LauncherColors.danger),
    ], spacing: 4),
  ], spacing: 0, modifier: DVModifier().border(Border(bottom: BorderSide(color: LauncherColors.rule))).paddingOnly(bottom: 6));
}
