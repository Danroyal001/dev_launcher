// The pieces every launcher screen uses: an app's icon, its tile (tap opens,
// long press offers the rest), and the sheet a long press opens.
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import 'theme.dart';

/// Opens [package], or says why it could not.
Future<String> openApp(String package) async {
  if (LauncherStore.instance.current.preview) return 'Preview: on your phone this opens the app.';
  try {
    await DV.Platform.apps.open(package);
    return '';
  } on Object catch (error) {
    return '$error'.replaceFirst('Bad state: ', '');
  }
}

/// An app's icon, or its first letter on a tile when it has none (yet).
@DVFunctionalWidget()
Widget _appIcon(BuildContext context, {required DVInstalledApp app, double size = 52}) {
  final List<int>? icon = app.icon;
  if (icon != null && icon.isNotEmpty) return DVBox.image(DVImage.memory(icon, alt: ''), width: size, height: size, fit: BoxFit.contain);
  return DVBox(
    DVText(app.label.isEmpty ? '?' : app.label.substring(0, 1).toUpperCase()).modifier(mono(size: size * 0.42, bold: true, color: LauncherColors.accent).align(Alignment.center)),
    DVModifier().width(size).height(size).backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(size * 0.28).centered(),
  );
}

/// An app: tap opens it, long press offers pin, dock, info and uninstall.
@DVFunctionalWidget()
Widget _appTile(BuildContext context, {required DVInstalledApp app, required VoidCallback onOpen, required VoidCallback onMore, double iconSize = 52, bool showLabel = true}) =>
    DVBox.list(<Widget>[
      AppIcon(app: app, size: iconSize),
      if (showLabel) DVText(app.label).modifier(mono(size: iconSize < 44 ? 11 : 13).maxLines(1).overflow(TextOverflow.ellipsis).align(Alignment.center)),
    ], spacing: 6, crossAlign: DVCrossAlign.center, modifier: DVModifier().padding(6).rounded(14).semanticLabel(app.label).tooltip('Open ${app.label}').onTap(onOpen).onLongPress(onMore));

/// What a long press on [app] offers.
@DVFunctionalWidget()
Widget _appSheet(BuildContext context, {required DVInstalledApp app, required LauncherSnapshot snapshot, required ValueChanged<String> onDone}) {
  final LauncherStore store = LauncherStore.instance;
  final bool onHome = snapshot.layout.home.contains(app.packageName);
  final bool inDock = snapshot.dock.contains(app.packageName);
  Widget action(String label, String hint, Future<String> Function() run, {Color color = LauncherColors.text}) => DVText(label).modifier(
        mono(size: 15, color: color).paddingSymmetric(horizontal: 16, vertical: 14).minimumTapTarget(width: 48, height: 48).tooltip(hint).onTap(() async => onDone(await run())),
      );
  Future<String> system(Future<void> Function(String) call) async {
    if (snapshot.preview) return 'Preview: on your phone this opens the system page.';
    try {
      await call(app.packageName);
      return '';
    } on Object catch (error) {
      return '$error'.replaceFirst('Bad state: ', '');
    }
  }

  return DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      AppIcon(app: app, size: 40),
      DVBox.list(<Widget>[
        DVText(app.label).modifier(mono(size: 16, bold: true).semanticHeading(2)),
        DVText(app.packageName).modifier(mono(size: 11, color: LauncherColors.muted)),
      ], spacing: 2),
    ], spacing: 12, crossAlign: DVCrossAlign.start),
    DVBox.wrapLine(<Widget>[
      action('open', 'Open ${app.label}', () => openApp(app.packageName), color: LauncherColors.accent),
      action(onHome ? 'off home' : 'to home', onHome ? 'Take ${app.label} off the home screen' : 'Put ${app.label} on the home screen', () => store.pinHome(app.packageName, pinned: !onHome)),
      action(inDock ? 'off dock' : 'to dock', inDock ? 'Take ${app.label} out of the dock' : 'Put ${app.label} in the dock', () => store.pinDock(app.packageName, pinned: !inDock)),
      action('info', 'The system page for ${app.label}', () => system(DV.Platform.apps.openSettings)),
      action('uninstall', 'Ask Android to uninstall ${app.label}', () => system(DV.Platform.apps.uninstall), color: LauncherColors.danger),
      action('close', 'Close this menu', () async => ''),
    ], spacing: 0),
  ], spacing: 10, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(18).padding(16).maxWidth(560).semanticRole('dialog'));
}

/// A labelled grid of apps.
@DVFunctionalWidget()
Widget _appSection(BuildContext context, {required String title, required List<DVInstalledApp> apps, required int columns, required ValueChanged<String> onOpen, required ValueChanged<String> onMore, double iconSize = 52}) =>
    DVBox.list(<Widget>[
      DVText('// $title').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(2)),
      if (apps.isNotEmpty)
        DVBox.grid(<Widget>[
          for (final DVInstalledApp app in apps) AppTile(app: app, iconSize: iconSize, onOpen: () => onOpen(app.packageName), onMore: () => onMore(app.packageName)),
        ], columns: columns, spacing: 4, responsive: false),
    ], spacing: 10);

/// [LauncherApp]s back to the [DVInstalledApp]s they came from.
List<DVInstalledApp> installedFor(LauncherSnapshot snapshot, List<LauncherApp> apps) => <DVInstalledApp>[for (final LauncherApp app in apps) if (snapshot.app(app.packageName) case final DVInstalledApp found) found];
