// The pieces every launcher screen uses: an app's icon (with its badge), its
// tile (tap opens, long press offers the rest), the menu a long press opens
// (the app's own shortcuts first, as on every launcher), folder tiles, the
// home grid that can be rearranged by dragging, and what the search offers
// besides apps.
import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import 'theme.dart';

/// Opens [package] and adds it to the recent apps, or says why it could not.
Future<String> openApp(String package) => LauncherStore.instance.open(package);

/// An app's icon, or its first letter on a tile when it has none (yet).
@DVFunctionalWidget()
Widget _appIcon(BuildContext context, {required DVInstalledApp app, double size = 52}) {
  final List<int>? icon = app.icon;
  if (icon != null && icon.isNotEmpty) return DVBox.image(DVImage.memory(icon, alt: ''), width: size, height: size, fit: BoxFit.contain);
  return DVBox(
    DVText(app.label.isEmpty ? '?' : app.label.substring(0, 1).toUpperCase()).modifier(mono(size: size * 0.42, bold: true, color: LauncherColors.accent).align(Alignment.center)),
    DVModifier().width(size).height(size).backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(size * 0.28).align(Alignment.center),
  );
}

/// [icon] with a badge on its top right corner when [count] is above 0: the
/// number of notifications, 99+ past that.
@DVFunctionalWidget()
Widget _badged(BuildContext context, {required Widget icon, required int count, required double size}) {
  if (count <= 0) return icon;
  final double dot = (size * 0.36).clamp(14.0, 22.0);
  return DVBox.stack(<Widget>[
    icon,
    DVBox(
      DVText(count > 99 ? '99+' : '$count').modifier(mono(size: dot * 0.55, bold: true, color: LauncherColors.page).align(Alignment.center)),
      DVModifier().width(dot).height(dot).backgroundColor(LauncherColors.accent).rounded(dot / 2).border(Border.all(color: LauncherColors.page, width: 1.5)).offset(size - dot * 0.75, -dot * 0.25),
    ),
  ]);
}

/// An app: tap opens it, long press offers the rest. [badge] is how many
/// notifications it shows.
@DVFunctionalWidget()
Widget _appTile(BuildContext context, {required DVInstalledApp app, required VoidCallback onOpen, required VoidCallback onMore, double iconSize = 52, bool showLabel = true, int badge = 0, bool onWallpaper = false}) =>
    DVBox.list(<Widget>[
      Badged(icon: AppIcon(app: app, size: iconSize), count: badge, size: iconSize),
      if (showLabel) DVText(app.label).modifier(mono(size: iconSize < 44 ? 11 : 13, color: onWallpaper ? WallpaperColors.text : null).maxLines(1).overflow(TextOverflow.ellipsis).align(Alignment.center)),
    ], spacing: 6, crossAlign: DVCrossAlign.center, modifier: DVModifier().padding(6).rounded(14).semanticLabel(badge > 0 ? '${app.label}, $badge ${badge == 1 ? 'notification' : 'notifications'}' : app.label).tooltip('Open ${app.label}').onTap(onOpen).onLongPress(onMore));

/// A folder on the home screen: up to four of its apps' icons in a square,
/// its name under it. Tap opens it.
@DVFunctionalWidget()
Widget _folderTile(BuildContext context, {required LauncherFolder folder, required LauncherSnapshot snapshot, required VoidCallback onOpen, double iconSize = 52}) {
  final List<DVInstalledApp> apps = snapshot.appsFor(folder.apps);
  final double mini = (iconSize - 14) / 2;
  final Widget square = DVBox(
    DVBox.grid(<Widget>[for (final DVInstalledApp app in apps.take(4)) AppIcon(app: app, size: mini)], columns: 2, spacing: 3, responsive: false),
    DVModifier().width(iconSize).height(iconSize).padding(4).backgroundColor(const Color(0x66151B23)).border(Border.all(color: WallpaperColors.rule)).rounded(iconSize * 0.28),
  );
  final int badge = snapshot.folderBadge(folder);
  return DVBox.list(<Widget>[
    Badged(icon: square, count: badge, size: iconSize),
    DVText(folder.name).modifier(mono(size: iconSize < 44 ? 11 : 13, color: WallpaperColors.text).maxLines(1).overflow(TextOverflow.ellipsis).align(Alignment.center)),
  ], spacing: 6, crossAlign: DVCrossAlign.center, modifier: DVModifier().padding(6).rounded(14).semanticLabel('Folder ${folder.name}, ${apps.length} apps${badge > 0 ? ', $badge notifications' : ''}').tooltip('Open folder ${folder.name}').onTap(onOpen).onLongPress(onOpen));
}

/// What a long press on [app] offers: the app's own shortcuts (LauncherApps),
/// then open, home, dock, folder, hide, arrange, info and uninstall.
/// [folderId] is the folder it was pressed in, if any; [onArrange] starts
/// rearranging the home screen (offered for an app that is on it).
@DVFunctionalWidget()
Widget _appSheet(BuildContext context, {required DVInstalledApp app, required LauncherSnapshot snapshot, required ValueChanged<String> onDone, String folderId = '', VoidCallback? onArrange}) {
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<List<DVInstalledAppShortcut>> shortcuts = context.signal(const <DVInstalledAppShortcut>[]);
  final DVSignal<String> shortcutNote = context.signal('');
  final DVSignal<bool> choosingFolder = context.signal(false);
  final DVSignal<bool> started = context.signal(false);
  if (!started.read()) {
    started.value = true;
    // Asked once the menu is up: the menu never waits for them.
    unawaited(Future<void>.microtask(() async {
      try {
        final List<DVInstalledAppShortcut> found = await DV.Platform.apps.shortcuts(app.packageName);
        if (context.mounted) shortcuts.value = found;
      } on UnsupportedError {
        // A browser preview, or a phone build without them: no shortcuts row.
      } on StateError {
        if (context.mounted && !snapshot.isDefault) shortcutNote.value = 'The app\'s shortcuts show here once Dev Launcher is your home app.';
      } on Object {
        // An app whose shortcuts cannot be read shows none.
      }
    }));
  }

  final bool onHome = snapshot.layout.home.contains(app.packageName);
  final bool inDock = snapshot.dock.contains(app.packageName);
  final bool hidden = snapshot.layout.hidden.contains(app.packageName);
  Widget action(String label, String hint, Future<String> Function() run, {Color? color}) => DVText(label).modifier(
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

  Widget shortcutRow(DVInstalledAppShortcut shortcut) {
    final Uint8List? icon = shortcut.icon;
    return DVBox.row(<Widget>[
      if (icon != null) DVBox.image(DVImage.memory(icon, alt: ''), width: 28, height: 28, fit: BoxFit.contain) else DVText('›').modifier(mono(size: 18, color: LauncherColors.accent).width(28).align(Alignment.center)),
      DVBox(DVText(shortcut.label).modifier(mono(size: 15).maxLines(1).overflow(TextOverflow.ellipsis)), DVModifier().fill()),
    ], spacing: 12, crossAlign: DVCrossAlign.center, modifier: DVModifier().paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).rounded(10).semanticLabel('${shortcut.label}, ${app.label} shortcut').tooltip('${shortcut.label} in ${app.label}').onTap(() async {
          try {
            await DV.Platform.apps.openShortcut(shortcut);
            onDone('');
          } on Object catch (error) {
            onDone('$error'.replaceFirst('Bad state: ', ''));
          }
        }));
  }

  final Widget folderChoice = DVBox.list(<Widget>[
    DVText('put ${app.label} in').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(3)),
    DVBox.wrapLine(<Widget>[
      for (final LauncherFolder folder in snapshot.layout.folders)
        if (folder.id != folderId) action(folder.name, 'Put ${app.label} in folder ${folder.name}', () => store.putInFolder(app.packageName, folderId: folder.id)),
      action('new folder', 'Make a new folder on the home screen with ${app.label} in it', () => store.putInFolder(app.packageName), color: LauncherColors.accent),
    ], spacing: 0),
  ], spacing: 4);

  return DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      AppIcon(app: app, size: 40),
      // The name and package take what the icon leaves: a column left to its
      // own width inside a row has none to give its text.
      DVBox(
        DVBox.list(<Widget>[
          DVText(app.label).modifier(mono(size: 16, bold: true).semanticHeading(2)),
          DVText(app.packageName).modifier(mono(size: 11, color: LauncherColors.muted)),
        ], spacing: 2),
        DVModifier().fill(),
      ),
    ], spacing: 12, crossAlign: DVCrossAlign.start),
    if (shortcuts.value.isNotEmpty) DVBox.list(<Widget>[for (final DVInstalledAppShortcut shortcut in shortcuts.value) shortcutRow(shortcut)], spacing: 0),
    if (shortcutNote.value.isNotEmpty) DVText(shortcutNote.value).modifier(mono(size: 12, color: LauncherColors.muted)),
    if (choosingFolder.value)
      folderChoice
    else
      DVBox.wrapLine(<Widget>[
        action('open', 'Open ${app.label}', () => openApp(app.packageName), color: LauncherColors.accent),
        if (folderId.isNotEmpty) action('out of folder', 'Take ${app.label} out of this folder', () => store.takeOutOfFolder(folderId, app.packageName)),
        if (folderId.isEmpty) action(onHome ? 'off home' : 'to home', onHome ? 'Take ${app.label} off the home screen' : 'Put ${app.label} on the home screen', () => store.pinHome(app.packageName, pinned: !onHome)),
        action(inDock ? 'off dock' : 'to dock', inDock ? 'Take ${app.label} out of the dock' : 'Put ${app.label} in the dock', () => store.pinDock(app.packageName, pinned: !inDock)),
        DVText('to folder').modifier(mono(size: 15).paddingSymmetric(horizontal: 16, vertical: 14).minimumTapTarget(width: 48, height: 48).tooltip('Put ${app.label} in a folder on the home screen').onTap(() => choosingFolder.value = true)),
        if (onHome && onArrange != null)
          DVText('arrange home').modifier(mono(size: 15).paddingSymmetric(horizontal: 16, vertical: 14).minimumTapTarget(width: 48, height: 48).tooltip('Drag the home screen\'s apps into a new order').onTap(() {
                onDone('');
                onArrange();
              })),
        action(hidden ? 'unhide' : 'hide', hidden ? 'Show ${app.label} in all apps again' : 'Hide ${app.label} from all apps and the search', () => store.hideApp(app.packageName, hidden: !hidden)),
        action('info', 'The system page for ${app.label}', () => system(DV.Platform.apps.openSettings)),
        action('uninstall', 'Ask Android to uninstall ${app.label}', () => system(DV.Platform.apps.uninstall), color: LauncherColors.danger),
        action('close', 'Close this menu', () async => ''),
      ], spacing: 0),
  ], spacing: 10, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(18).padding(16).maxWidth(560).semanticRole('dialog'));
}

/// A labelled grid of apps.
@DVFunctionalWidget()
Widget _appSection(BuildContext context, {required String title, required List<DVInstalledApp> apps, required int columns, required ValueChanged<String> onOpen, required ValueChanged<String> onMore, double iconSize = 52, Map<String, int> badges = const <String, int>{}, bool onWallpaper = false}) =>
    DVBox.list(<Widget>[
      DVText('// $title').modifier(mono(size: 13, color: onWallpaper ? WallpaperColors.accent : LauncherColors.accent).semanticHeading(2)),
      if (apps.isNotEmpty)
        DVBox.grid(<Widget>[
          for (final DVInstalledApp app in apps) AppTile(app: app, iconSize: iconSize, badge: badges[app.packageName] ?? 0, onWallpaper: onWallpaper, onOpen: () => onOpen(app.packageName), onMore: () => onMore(app.packageName)),
        ], columns: columns, spacing: 4, responsive: false),
    ], spacing: 10);

/// The home screen's own apps and folders, in the person's order. While
/// [arranging], a finger drags any tile to another cell and the others move
/// along; "Done arranging" ends it.
@DVFunctionalWidget()
Widget _homeGrid(BuildContext context, {required LauncherSnapshot snapshot, required int columns, required double width, required bool arranging, required ValueChanged<String> onOpen, required ValueChanged<String> onMore, required ValueChanged<String> onFolder, required VoidCallback onDoneArranging, double iconSize = 52}) {
  final DVSignal<int> dragging = context.signal(-1);
  final DVSignal<Offset> moved = context.signal(Offset.zero);
  final List<String> items = <String>[
    for (final String item in snapshot.layout.home)
      if (item.startsWith(folderPrefix) ? snapshot.layout.folder(item.substring(folderPrefix.length)) != null : snapshot.app(item) != null) item,
  ];
  const double spacing = 4;
  // A cell, worked out from the sizes the tile itself uses: its padding, its
  // icon, the gap and one line of its label at the phone's font size.
  final double cellWidth = (width + spacing) / columns;
  final double labelLine = MediaQuery.textScalerOf(context).scale(iconSize < 44 ? 11 : 13) * 1.32;
  final double cellHeight = 12 + iconSize + 6 + labelLine + spacing;

  Widget tile(int index, String item) {
    final Widget shown;
    if (item.startsWith(folderPrefix)) {
      final LauncherFolder folder = snapshot.layout.folder(item.substring(folderPrefix.length))!;
      shown = FolderTile(folder: folder, snapshot: snapshot, iconSize: iconSize, onOpen: arranging ? () {} : () => onFolder(folder.id));
    } else {
      final DVInstalledApp app = snapshot.app(item)!;
      shown = AppTile(app: app, iconSize: iconSize, badge: snapshot.badgeFor(item), onWallpaper: true, onOpen: arranging ? () {} : () => onOpen(item), onMore: arranging ? () {} : () => onMore(item));
    }
    if (!arranging) return shown;
    final bool lifted = dragging.value == index;
    return DVBox(
      shown,
      DVModifier()
          .rounded(14)
          .border(Border.all(color: lifted ? WallpaperColors.accent : WallpaperColors.rule))
          .offset(lifted ? moved.value.dx : 0, lifted ? moved.value.dy : 0)
          .onGesture(DVGesture(
            onStart: (ScaleStartDetails details) {
              dragging.value = index;
              moved.value = Offset.zero;
            },
            onUpdate: (ScaleUpdateDetails details) => moved.value = moved.read() + details.focalPointDelta,
            onEnd: (ScaleEndDetails details) {
              final Offset by = moved.read();
              final int to = dropIndex(from: index, dx: by.dx, dy: by.dy, columns: columns, cellWidth: cellWidth, cellHeight: cellHeight, count: items.length);
              dragging.value = -1;
              moved.value = Offset.zero;
              final int from = snapshot.layout.home.indexOf(item);
              final int target = snapshot.layout.home.indexOf(items[to]);
              if (from >= 0 && target >= 0 && from != target) unawaited(LauncherStore.instance.moveHomeItem(from, target));
            },
          )),
    );
  }

  return DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      DVBox(DVText('// home').modifier(mono(size: 13, color: WallpaperColors.accent).semanticHeading(2)), DVModifier().fill()),
      if (arranging)
        DVText('Done arranging').modifier(mono(size: 13, bold: true, color: WallpaperColors.page).backgroundColor(WallpaperColors.accent).rounded(8).paddingSymmetric(horizontal: 12, vertical: 8).minimumTapTarget(width: 48, height: 48).tooltip('Keep this order').onTap(onDoneArranging)),
    ], spacing: 8, crossAlign: DVCrossAlign.center),
    if (arranging) DVText('Drag an app or folder to its new place.').modifier(mono(size: 12, color: WallpaperColors.text)),
    DVBox.grid(<Widget>[for (int index = 0; index < items.length; index++) tile(index, items[index])], columns: columns, spacing: spacing, responsive: false),
  ], spacing: 10);
}

/// An open folder: its name (edited in place) and its apps.
@DVFunctionalWidget()
Widget _folderView(BuildContext context, {required LauncherFolder folder, required LauncherSnapshot snapshot, required int columns, required ValueChanged<String> onOpen, required ValueChanged<String> onMore, required VoidCallback onClose, double iconSize = 52}) =>
    DVBox.list(<Widget>[
      DVBox.row(<Widget>[
        DVBox(
          DVText(folder.name).modifier(mono(size: 18, bold: true).input(
                label: 'Folder name',
                hint: 'Folder',
                onChanged: (String name) => unawaited(LauncherStore.instance.nameFolder(folder.id, name)),
              )),
          DVModifier().fill(),
        ),
        DVText('×').modifier(mono(size: 22, color: LauncherColors.muted).centered().minimumTapTarget(width: 48, height: 48).semanticLabel('Close folder').tooltip('Close folder').onTap(onClose)),
      ], spacing: 8, crossAlign: DVCrossAlign.center),
      DVBox.grid(<Widget>[
        for (final DVInstalledApp app in snapshot.appsFor(folder.apps)) AppTile(app: app, iconSize: iconSize, badge: snapshot.badgeFor(app.packageName), onOpen: () => onOpen(app.packageName), onMore: () => onMore(app.packageName)),
      ], columns: columns, spacing: 4, responsive: false),
    ], spacing: 12, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(18).padding(16).maxWidth(560).semanticRole('dialog'));

/// What a search offers besides apps: the phone's settings pages that match,
/// contacts (when chosen in the settings) and the web.
@DVFunctionalWidget()
Widget _searchExtras(BuildContext context, {required String query, required LauncherSnapshot snapshot, required ValueChanged<String> onDone, bool onWallpaper = false}) {
  final DVSignal<List<LauncherContact>> contacts = context.signal(const <LauncherContact>[]);
  final DVSignal<bool> asked = context.signal(false);
  final String wanted = query.trim();
  if (wanted.isEmpty) return DVBox.list(const <Widget>[]);
  final LauncherOptions options = snapshot.layout.options;
  if (options.searchContacts && !asked.read()) {
    asked.value = true;
    unawaited(LauncherStore.instance.contacts().then((List<LauncherContact> found) {
      if (context.mounted) contacts.value = found;
    }));
  }
  final List<DVSystemSettingsPage> pages = matchKeywords(DVSystemSettingsPage.values, wanted, (DVSystemSettingsPage page) => <String>[page.title, ...page.keywords]).take(4).toList();
  final List<LauncherContact> people = options.searchContacts ? matchContacts(contacts.value, wanted).take(4).toList() : const <LauncherContact>[];
  Widget row(String label, String hint, Future<String> Function() run) => DVText(label).modifier(
        mono(size: 14, color: onWallpaper ? WallpaperColors.text : null).paddingSymmetric(horizontal: 12, vertical: 12).minimumTapTarget(width: 48, height: 48).backgroundColor(onWallpaper ? WallpaperColors.panel : LauncherColors.surface).rounded(10).maxLines(1).overflow(TextOverflow.ellipsis).tooltip(hint).onTap(() async => onDone(await run())),
      );
  Future<String> attempt(Future<void> Function() call) async {
    try {
      await call();
      return '';
    } on Object catch (error) {
      return '$error'.replaceFirst('Bad state: ', '').replaceFirst('Unsupported operation: ', '');
    }
  }

  return DVBox.list(<Widget>[
    if (pages.isNotEmpty) DVText('settings').modifier(mono(size: 13, bold: true, color: onWallpaper ? WallpaperColors.accent : LauncherColors.accent).semanticHeading(2)),
    for (final DVSystemSettingsPage page in pages) row('${page.title} settings', 'Open ${page.title} in the phone\'s settings', () => attempt(() => DV.Platform.apps.openSystemSettings(page))),
    if (people.isNotEmpty) DVText('contacts').modifier(mono(size: 13, bold: true, color: onWallpaper ? WallpaperColors.accent : LauncherColors.accent).semanticHeading(2)),
    for (final LauncherContact person in people) row('${person.name} · ${person.phone}', 'Call ${person.name} (opens the dialer)', () => attempt(() async => DVLinkOpener.open('tel:${person.phone.replaceAll(' ', '')}'))),
    if (options.searchWeb) row('Search the web for "$wanted"', 'Open the browser on a search for $wanted', () => attempt(() async => DVLinkOpener.open(webSearchUrl(wanted)))),
  ], spacing: 6);
}

/// [LauncherApp]s back to the [DVInstalledApp]s they came from.
List<DVInstalledApp> installedFor(LauncherSnapshot snapshot, List<LauncherApp> apps) => <DVInstalledApp>[for (final LauncherApp app in apps) if (snapshot.app(app.packageName) case final DVInstalledApp found) found];
