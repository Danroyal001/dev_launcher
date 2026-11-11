// The home screen, over the phone's wallpaper: the clock, a prompt that
// opens apps and runs commands, the apps put on the home screen, the dev
// tools, and the dock. Swipe up, or the apps button, opens every app A to Z.
// The same screen lays out for a round watch, a phone, a tablet or
// Chromebook, and a TV across a room.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import 'app_drawer.dart';
import 'app_tiles.dart';
import 'theme.dart';

const Set<String> commandWords = <String>{'info', 'pin', 'unpin', 'uninstall'};

/// The day and date under the clock: Tue 10 Nov.
String dayLine(DateTime now) {
  const List<String> days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

/// Follows the store from the first frame: names at once, icons as they come.
void followStore(BuildContext context, DVSignal<LauncherSnapshot> snapshot) {
  late final StreamSubscription<LauncherSnapshot> subscription;
  subscription = LauncherStore.instance.changes.listen((LauncherSnapshot next) {
    if (!context.mounted) {
      subscription.cancel();
      return;
    }
    snapshot.value = next;
  });
  snapshot.value = LauncherStore.instance.current;
}

/// Back closes the drawer while it is open. A plain observer of the system's
/// back request: the launcher itself is never closed by Back (the generated
/// activity keeps it), so this only ever closes what is on top.
class DrawerBack(
  /// True when it handled Back.
  final bool Function() onBack,
) with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async => onBack();
}

@DVFunctionalWidget()
Widget _launcherHome(BuildContext context) {
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> typed = context.signal('');
  final DVSignal<String> status = context.signal('');
  final DVSignal<String> selected = context.signal('');
  final DVSignal<DateTime> now = context.signal(DateTime.now());
  final DVSignal<bool> started = context.signal(false);
  // The drawer's top edge: the screen height when closed, 0 when open, and
  // anywhere between while a finger drags it.
  final DVSignal<double?> drawerTop = context.signal<double?>(null);
  final DVSignal<bool> dragging = context.signal(false);
  final double screenHeight = MediaQuery.sizeOf(context).height;
  double topNow() => drawerTop.read() ?? screenHeight;
  void openDrawer() {
    dragging.value = false;
    drawerTop.value = 0;
  }

  void closeDrawer() {
    dragging.value = false;
    drawerTop.value = screenHeight;
  }

  void dragDrawer(double deltaY) {
    dragging.value = true;
    drawerTop.value = drawerTopAfterDrag(topNow(), deltaY, height: screenHeight);
  }

  void releaseDrawer(double velocity) => drawerSettlesOpen(top: topNow(), height: screenHeight, velocity: velocity) ? openDrawer() : closeDrawer();

  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      followStore(context, snapshot);
      store.start();
      late final DrawerBack back;
      back = DrawerBack(() {
        if (!context.mounted) {
          WidgetsBinding.instance.removeObserver(back);
          return false;
        }
        if (topNow() >= screenHeight) return false;
        closeDrawer();
        return true;
      });
      WidgetsBinding.instance.addObserver(back);
      // Back from Settings (after choosing the home app) or from any app:
      // ask again whether Dev Launcher is the home app.
      late final StreamSubscription<DVAppLifecycle> lifecycle;
      lifecycle = DV.lifecycle.app.changes.listen((DVAppLifecycle state) {
        if (!context.mounted) {
          lifecycle.cancel();
          return;
        }
        if (state == DVAppLifecycle.ready) store.refreshDefault();
        // An app opened from the drawer: home shows the home screen again.
        if (state == DVAppLifecycle.backgrounded) closeDrawer();
      });
      // The clock: a minute is the finest it shows.
      Timer.periodic(const Duration(seconds: 15), (Timer timer) {
        if (!context.mounted) {
          timer.cancel();
          return;
        }
        now.value = DateTime.now();
      });
    });
  }

  final LauncherSnapshot current = snapshot.value;
  final Size size = MediaQuery.sizeOf(context);
  final ScreenKind kind = screenKindFor(width: size.width, height: size.height);
  final bool watch = kind == ScreenKind.watch;
  launcherTextScale = kind == ScreenKind.tv ? 1.5 : 1;
  final double side = watch ? roundSafeInset(size.shortestSide) : (kind == ScreenKind.tv ? 56 : 20);
  final int columns = gridColumns(kind, size.width - side * 2);
  final double iconSize = switch (kind) { ScreenKind.watch => 40, ScreenKind.phone => 52, ScreenKind.tablet => 60, ScreenKind.tv => 72 };
  final double clockSize = switch (kind) { ScreenKind.watch => 34, ScreenKind.phone => 64, ScreenKind.tablet => 80, ScreenKind.tv => 96 };
  final DateTime time = now.value;

  Future<void> open(String package) async {
    final String problem = await openApp(package);
    status.value = problem;
    if (problem.isEmpty) typed.value = '';
  }

  Future<void> act(LauncherAction action, String package) async {
    final DVInstalledApp? app = current.app(package);
    if (app == null) return;
    switch (action) {
      case .open:
        await open(package);
      case .pin:
        status.value = await store.pinHome(package, pinned: true);
        if (status.read().isEmpty) status.value = '${app.label} is on the home screen.';
        typed.value = '';
      case .unpin:
        status.value = await store.pinHome(package, pinned: false);
        if (status.read().isEmpty) status.value = '${app.label} is off the home screen.';
        typed.value = '';
      case .info:
      case .uninstall:
        selected.value = package;
      case .none:
        break;
    }
  }

  void submit() {
    final LauncherCommand command = parseCommand(typed.read(), current.launcherApps);
    if (command.action == LauncherAction.none) {
      status.value = command.message;
      return;
    }
    act(command.action, command.app!.packageName);
  }

  final String query = typed.value;
  final List<String> words = query.trim().split(' ');
  final String search = words.length > 1 && commandWords.contains(words.first.toLowerCase()) ? query.substring(query.indexOf(' ') + 1) : query;
  final List<DVInstalledApp> matches = installedFor(current, matchApps(current.launcherApps, search));
  final List<DVInstalledApp> home = current.appsFor(current.layout.home);
  final List<DVInstalledApp> devTools = current.apps.where((DVInstalledApp app) => isDevTool(app.packageName)).toList();
  final List<DVInstalledApp> dock = current.appsFor(current.dock);
  final DVInstalledApp? sheetApp = selected.value.isEmpty ? null : current.app(selected.value);

  final Widget appsButton = DVBox(
    DVText('⋮⋮').modifier(mono(size: watch ? 18 : 22, bold: true, color: LauncherColors.text).align(Alignment.center)),
    DVModifier().width(iconSize).height(iconSize).backgroundColor(const Color(0x33FFFFFF)).rounded(iconSize * 0.5).centered().tooltip('All apps').semanticLabel('All apps').onTap(openDrawer),
  );

  final Widget content = DVBox.list(<Widget>[
    if (current.preview)
      DVText('Preview: Dev Launcher is an Android home screen. Here it shows example apps.').modifier(mono(size: 13, color: LauncherColors.muted).backgroundColor(LauncherColors.surface).rounded(10).padding(12)),
    DVBox.list(<Widget>[
      DVText('${twoDigits(time.hour)}:${twoDigits(time.minute)}').modifier(mono(size: clockSize, bold: true).lineHeight(1).semanticHeading(1).semanticLabel('Dev Launcher, ${twoDigits(time.hour)}:${twoDigits(time.minute)}').align(watch ? Alignment.center : Alignment.centerLeft)),
      DVText(watch ? dayLine(time) : '${dayLine(time)} · ${current.apps.length} apps').modifier(mono(size: watch ? 12 : 15, color: LauncherColors.text).align(watch ? Alignment.center : Alignment.centerLeft)),
    ], spacing: 6),
    if (!current.isDefault && !current.preview)
      DVBox.list(<Widget>[
        DVText('Dev Launcher is not your home app yet.').modifier(mono(size: 14)),
        DVText('Make it my home app').modifier(
          mono(size: 14, bold: true, color: LauncherColors.page).backgroundColor(LauncherColors.accent).rounded(10).paddingSymmetric(horizontal: 16, vertical: 12).minimumTapTarget(width: 48, height: 48).tooltip('Ask Android to make Dev Launcher the home app').onTap(() async {
            status.value = await store.askToBeDefault();
          }),
        ),
      ], spacing: 10, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.accent)).rounded(14).padding(14)),
    if (!watch)
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
      ], spacing: 10, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(const Color(0xCC151B23)).border(Border.all(color: LauncherColors.rule)).rounded(12).paddingSymmetric(horizontal: 14, vertical: 4).maxWidth(720)),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13, color: LauncherColors.text).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (query.trim().isNotEmpty) ...<Widget>[
      AppSection(title: 'matches', apps: matches.take(columns * 2).toList(), columns: columns, iconSize: iconSize, onOpen: open, onMore: (String package) => selected.value = package),
      if (matches.isEmpty) DVText('Enter runs it. Try: info, pin, unpin, uninstall + an app.').modifier(mono(size: 13, color: LauncherColors.muted)),
    ],
    if (home.isNotEmpty)
      AppSection(title: 'home', apps: home, columns: columns, iconSize: iconSize, onOpen: open, onMore: (String package) => selected.value = package)
    else if (!current.loading && !watch)
      DVText('Long-press any app to put it here or in the dock.').modifier(mono(size: 13, color: LauncherColors.text).backgroundColor(const Color(0x99151B23)).rounded(8).padding(10)),
    if (devTools.isNotEmpty && !watch) AppSection(title: 'dev tools', apps: devTools, columns: columns, iconSize: iconSize, onOpen: open, onMore: (String package) => selected.value = package),
    if (watch) DVBox(appsButton, DVModifier().centered()),
  ], spacing: watch ? 14 : 22, modifier: DVModifier().paddingOnly(left: side, right: side, top: watch ? side * 0.6 : 28, bottom: 24)).scrollable();

  final Widget dockRow = DVBox.row(<Widget>[
    for (final DVInstalledApp app in dock.take(dock.length > 2 ? 2 : dock.length)) AppTile(app: app, iconSize: iconSize, showLabel: false, onOpen: () => open(app.packageName), onMore: () => selected.value = app.packageName),
    appsButton,
    for (final DVInstalledApp app in dock.skip(2)) AppTile(app: app, iconSize: iconSize, showLabel: false, onOpen: () => open(app.packageName), onMore: () => selected.value = app.packageName),
  ], spacing: 0, align: DVAlign.spaceEvenly, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(const Color(0x40FFFFFF)).rounded(28).paddingSymmetric(horizontal: 4, vertical: 6).maxWidth(kind == ScreenKind.phone ? double.infinity : 640));

  // Drag up from the dock (or the handle above it) and the drawer follows the
  // finger, one to one; let go and it settles open or closed.
  final DVModifier dragUp = DVModifier().onGesture(DVGesture(
    onUpdate: (ScaleUpdateDetails details) => dragDrawer(details.focalPointDelta.dy),
    onEnd: (ScaleEndDetails details) => releaseDrawer(details.velocity.pixelsPerSecond.dy),
  ));
  final double top = drawerTop.value ?? size.height;
  final Widget drawer = DVBox(
    AppDrawer(onClose: closeDrawer, onDrag: dragDrawer, onDragEnd: releaseDrawer),
    DVModifier().marginOnly(top: top).height(size.height).merge(dragging.value ? DVModifier() : DVModifier().animate(const Duration(milliseconds: 220))),
  );
  final Widget dragHandle = DVBox(
    DVText('').modifier(DVModifier().width(44).height(5).backgroundColor(const Color(0x88FFFFFF)).rounded(3)),
    DVModifier().centered().paddingSymmetric(vertical: 8).tooltip('Drag up, or tap, for all apps').onTap(openDrawer).merge(dragUp),
  );

  // A browser has no wallpaper to show: the preview sits on the dark page.
  return DVBox(DVBox.stack(<Widget>[
    DVBox.list(<Widget>[
      DVBox(content, DVModifier().height(size.height - (watch ? 0 : iconSize + 85))),
      if (!watch) DVBox(DVBox.list(<Widget>[dragHandle, dockRow], spacing: 0), DVModifier().paddingOnly(left: side, right: side, bottom: 16).centered().merge(dragUp)),
    ], spacing: 0),
    drawer,
    if (sheetApp != null)
      DVBox(
        AppSheet(app: sheetApp, snapshot: current, onDone: (String problem) {
          status.value = problem;
          selected.value = '';
        }),
        DVModifier().align(Alignment.bottomCenter).padding(watch ? side * 0.5 : 16),
      ),
  ], modifier: DVModifier().gradient(wallpaperScrim).minHeight(size.height).clipContent()), DVModifier().backgroundColor(current.preview ? LauncherColors.page : const Color(0x00000000)));
}
