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
import '../services/signal_log.dart';
import '../services/updates.dart';
import 'app_tiles.dart';
import 'launcher_settings.dart';
import 'recents_screen.dart';
import 'recents_settings.dart';
import 'theme.dart';
import 'updates_screen.dart';

const Set<String> commandWords = <String>{'info', 'pin', 'unpin', 'uninstall'};

/// The phone's language, as intl names it (en_US, ar, fr_FR).
String deviceLocale() => WidgetsBinding.instance.platformDispatcher.locale.toString();

/// Three bars drawn as boxes, never a font glyph that a phone's font may lack
/// (and show as an empty square): three lines across (Tecno, Xiaomi, and the
/// fallback) or three upright bars (Samsung), as the phone's navigation bar
/// draws Recents.
@DVFunctionalWidget()
Widget _recentsButtonIcon(BuildContext context, {required RecentsGlyph glyph, double size = 22}) {
  final double thick = (size / 9).clamp(2.0, 4.0);
  final Widget bar = DVText('').modifier(glyph == RecentsGlyph.lines ? DVModifier().width(size * 0.82).height(thick).backgroundColor(WallpaperColors.text).rounded(thick) : DVModifier().width(thick).height(size * 0.72).backgroundColor(WallpaperColors.text).rounded(thick));
  final Widget bars = glyph == RecentsGlyph.lines
      ? DVBox.list(<Widget>[bar, bar, bar], spacing: size * 0.18, crossAlign: DVCrossAlign.center)
      : DVBox.row(<Widget>[bar, bar, bar], spacing: size * 0.2, crossAlign: DVCrossAlign.center);
  // In the middle of the button, at its own size.
  return DVBox(DVBox(bars, DVModifier().width(size).height(size).align(Alignment.center)), DVModifier().align(Alignment.center));
}

/// The apps button's grid of nine dots, drawn as boxes for the same reason.
@DVFunctionalWidget()
Widget _appsButtonIcon(BuildContext context, {double size = 22}) {
  final double dot = size / 5;
  final Widget row = DVBox.row(<Widget>[for (int column = 0; column < 3; column++) DVText('').modifier(DVModifier().width(dot).height(dot).backgroundColor(WallpaperColors.text).rounded(dot / 2))], spacing: dot, crossAlign: DVCrossAlign.center);
  return DVBox(DVBox(DVBox.list(<Widget>[row, row, row], spacing: dot, crossAlign: DVCrossAlign.center), DVModifier().width(size).height(size).align(Alignment.center)), DVModifier().align(Alignment.center));
}

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

@DVFunctionalWidget()
Widget _launcherHome(BuildContext context) {
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> typed = context.signal('');
  final DVSignal<String> status = context.signal('');
  final DVSignal<String> selected = context.signal('');
  final DVSignal<DateTime> now = context.signal(DateTime.now());
  final DVSignal<bool> started = context.signal(false);
  // The newest release, once asked: a note on the home screen when it is
  // newer than this phone's.
  final DVSignal<UpdateCheck> updateCheck = context.signal(LauncherUpdates.instance.current);
  // The drawer's top edge: null when closed, 0 when open, and anywhere
  // between while a finger drags it.
  final DVSignal<double?> drawerTop = context.signal<double?>(null);
  final DVSignal<bool> dragging = context.signal(false);
  // While the drawer is open, Back closes it (DV.Navigation.onBack); this is
  // the call that stops that when it closes.
  final DVSignal<VoidCallback?> stopBack = context.signal<VoidCallback?>(null);
  // The height now, asked each time: these calls outlive the build they were
  // made in (Home, Back and leaving for an app run the ones from the first
  // frame, which Android can lay out before it knows the screen: height 0).
  // Remembering that height put the "closed" drawer at 0, fully open, and
  // let go of Back.
  double screenHeight() => MediaQuery.sizeOf(context).height;
  double topNow() => drawerTop.read() ?? screenHeight();
  // What is over the home screen besides the drawer: nothing, Dev Launcher's
  // Recents ('recents'), the Recents button settings ('settings'), the
  // launcher settings ('launcher-settings') or an open folder ('folder:<id>').
  final DVSignal<String> overlay = context.signal('');
  // Where the Recents button settings were opened from: Back returns there.
  final DVSignal<String> settingsFrom = context.signal('recents');
  // Dragging the home screen's tiles into a new order.
  final DVSignal<bool> arranging = context.signal(false);
  // The folder an app's menu was opened in, if any.
  final DVSignal<String> sheetFolder = context.signal('');
  // The smallest scale a two-finger pinch reached.
  final DVSignal<double> pinch = context.signal(1.0);

  // Back stops being Dev Launcher's once nothing is open.
  void releaseBackWhenIdle() {
    if (overlay.read().isNotEmpty || arranging.read() || topNow() < screenHeight()) return;
    stopBack.read()?.call();
    stopBack.value = null;
  }

  void closeDrawer() {
    // The search field goes with the drawer: no keyboard left over the home screen.
    putKeyboardAway(context);
    dragging.value = false;
    drawerTop.value = null;
    releaseBackWhenIdle();
  }

  late final void Function(String name) show;
  // Back closes what is on top: the settings back to Recents, Recents back
  // to home, then the drawer whenever any of it is showing (settled open, or
  // dragged part way by a finger whose release never arrives: the system's
  // gesture area at the bottom of the screen can swallow it).
  void claimBack() {
    stopBack.value ??= DV.Navigation.onBack(() {
      // A home screen that is gone (rebuilt from scratch) answers nothing.
      if (!context.mounted) return false;
      // The keyboard first: Back puts it away and leaves the drawer open, as
      // Android does when Back reaches the keyboard before the app.
      if (putKeyboardAway(context)) {
        SignalLog.instance.note('backHandled', 'the keyboard');
        return true;
      }
      if (overlay.read() == 'settings') {
        SignalLog.instance.note('backHandled', 'Recents settings');
        show(settingsFrom.read());
      } else if (arranging.read() && overlay.read().isEmpty) {
        SignalLog.instance.note('backHandled', 'arranging');
        arranging.value = false;
        releaseBackWhenIdle();
      } else if (overlay.read().isNotEmpty) {
        SignalLog.instance.note('backHandled', 'Recents');
        show('');
      } else {
        SignalLog.instance.note('backHandled', 'the app drawer');
        closeDrawer();
      }
      return true;
    });
  }

  show = (String name) {
    overlay.value = name;
    name.isEmpty ? releaseBackWhenIdle() : claimBack();
  };

  void openDrawer() {
    dragging.value = false;
    drawerTop.value = 0;
    claimBack();
  }

  void dragDrawer(double deltaY) {
    dragging.value = true;
    drawerTop.value = drawerTopAfterDrag(topNow(), deltaY, height: screenHeight());
    if (topNow() < screenHeight()) claimBack();
  }

  // A tap inside a drag area can end a gesture that never moved; only a real
  // drag settles the drawer, or a tap on the apps button would close it again.
  void releaseDrawer(double velocity) {
    if (!dragging.read()) return;
    drawerSettlesOpen(top: topNow(), height: screenHeight(), velocity: velocity) ? openDrawer() : closeDrawer();
  }

  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      followStore(context, snapshot);
      late final StreamSubscription<UpdateCheck> updatesSubscription;
      updatesSubscription = LauncherUpdates.instance.changes.listen((UpdateCheck next) {
        if (!context.mounted) {
          updatesSubscription.cancel();
          return;
        }
        updateCheck.value = next;
      });
      // Once the apps are in (never competing with the first screen), ask
      // GitHub once whether a newer Dev Launcher is out. Not in the browser
      // preview.
      store.start().then((_) {
        if (!context.mounted) return;
        if (LauncherUpdates.instance.autoCheck ?? !store.current.preview) unawaited(LauncherUpdates.instance.checkOnce());
      });
      SignalLog.instance.start();
      SignalLog.instance.note('started', 'screen height ${screenHeight().round()}');
      // Back from Settings (after choosing the home app) or from any app:
      // ask again whether Dev Launcher is the home app.
      late final StreamSubscription<DVAppLifecycle> lifecycle;
      lifecycle = DV.lifecycle.app.changes.listen((DVAppLifecycle state) {
        if (!context.mounted) {
          lifecycle.cancel();
          return;
        }
        // Apps installed or uninstalled meanwhile show up, or go, too.
        if (state == DVAppLifecycle.ready) {
          store.refreshDefault();
          store.refreshAppsSoon();
        }
        // An app opened from the drawer: home shows the home screen again.
        if (state == DVAppLifecycle.backgrounded) closeDrawer();
      });
      // Home pressed while the launcher is in front (or bringing it back):
      // the home screen, as it is after a fresh start, with nothing open.
      late final StreamSubscription<void> home;
      home = DV.Platform.apps.homePresses.listen((_) {
        if (!context.mounted) {
          home.cancel();
          return;
        }
        closeDrawer();
        arranging.value = false;
        show('');
        selected.value = '';
        sheetFolder.value = '';
        status.value = '';
      });
      // The phone's Recents button, wherever Dev Launcher hears it: the
      // phone said so and showed nothing of its own (HiOS hosts Recents in
      // its own launcher), or the Recents service saw it. Dev Launcher's
      // Recents opens; a second press closes it, as Recents does.
      late final StreamSubscription<void> recents;
      recents = DV.Platform.apps.recentsPresses.listen((_) {
        if (!context.mounted) {
          recents.cancel();
          return;
        }
        selected.value = '';
        if (overlay.read() == 'recents') {
          show('');
        } else {
          closeDrawer();
          show('recents');
        }
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
  followLauncherTheme(context, current.layout.options);
  final double side = watch ? roundSafeInset(size.shortestSide) : (kind == ScreenKind.tv ? 56 : 20);
  final int columns = gridColumns(kind, size.width - side * 2);
  final double iconSize = switch (kind) { ScreenKind.watch => 40, ScreenKind.phone => 52, ScreenKind.tablet => 60, ScreenKind.tv => 72 };
  final double clockSize = switch (kind) { ScreenKind.watch => 34, ScreenKind.phone => 64, ScreenKind.tablet => 80, ScreenKind.tv => 96 };
  final DateTime time = now.value;
  // The phone's own 12/24-hour setting and language, never a fixed format.
  final String locale = deviceLocale();
  final bool use24 = MediaQuery.alwaysUse24HourFormatOf(context) || WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
  final String clock = clockText(time, use24: use24, locale: locale);
  final String date = dayLine(time, locale: locale);

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
    if (typed.read().trim().toLowerCase() == 'settings') {
      typed.value = '';
      show('launcher-settings');
      return;
    }
    final LauncherCommand command = parseCommand(typed.read(), current.visibleLauncherApps);
    if (command.action == LauncherAction.none) {
      status.value = command.message;
      return;
    }
    act(command.action, command.app!.packageName);
  }

  final String query = typed.value;
  final List<String> words = query.trim().split(' ');
  final String search = words.length > 1 && commandWords.contains(words.first.toLowerCase()) ? query.substring(query.indexOf(' ') + 1) : query;
  final List<DVInstalledApp> matches = installedFor(current, matchApps(current.visibleLauncherApps, search));
  // The home screen's items still there: apps installed, folders that exist.
  final bool hasHome = current.layout.home.any((String item) => item.startsWith(folderPrefix) ? current.layout.folder(item.substring(folderPrefix.length)) != null : current.app(item) != null);
  final Map<String, int> badges = current.layout.options.badges ? current.badges : const <String, int>{};
  final LauncherFolder? openFolder = overlay.value.startsWith(folderPrefix) ? current.layout.folder(overlay.value.substring(folderPrefix.length)) : null;

  // A double tap on the clock: the screen locks, through the opt-in
  // accessibility service; while it is off the person is told where it is.
  Future<void> lockScreen() async {
    if (!current.layout.options.doubleTapLock) return;
    if (await DV.Platform.apps.lockScreen()) return;
    status.value = 'To lock with a double tap, turn on "Dev Launcher Recents" under Accessibility (launcher settings, gestures).';
  }

  // A swipe down: the notification shade, as on every launcher.
  Future<void> pullShade() async {
    if (!current.layout.options.swipeDownShade || current.preview) return;
    if (!await DV.Platform.apps.expandNotifications()) status.value = 'This phone did not let Dev Launcher pull the notifications down.';
  }

  final List<DVInstalledApp> devTools = current.apps.where((DVInstalledApp app) => isDevTool(app.packageName)).toList();
  final List<DVInstalledApp> dock = current.appsFor(current.dock);
  final DVInstalledApp? sheetApp = selected.value.isEmpty ? null : current.app(selected.value);
  final LauncherRelease? newerRelease = switch (updateCheck.value.release) { final LauncherRelease release when isNewer(release) => release, _ => null };

  // Every dock slot (its apps and the apps button) fits across the dock on
  // the narrowest phone: icons shrink rather than push past the edge.
  final double dockWidth = (kind == ScreenKind.phone ? size.width - side * 2 : (size.width - side * 2).clamp(0, 640).toDouble()) - 8;
  final double dockIcon = watch ? iconSize : (dockWidth / (dock.length + 2) - 12).clamp(32, iconSize).toDouble();
  final Widget appsButton = DVBox(
    AppsButtonIcon(size: watch ? 18 : 22),
    DVModifier().width(dockIcon).height(dockIcon).backgroundColor(const Color(0x33FFFFFF)).rounded(dockIcon * 0.5).align(Alignment.center).tooltip('All apps').semanticLabel('All apps').onTap(openDrawer),
  );

  // The Recents button as the phone's navigation bar has it: its glyph, and
  // its side unless the person chose one in Recents button settings.
  final NavBarStyle navBar = navBarStyleFor(current.apps.map((DVInstalledApp app) => app.packageName));
  final bool recentsFirst = recentsSideFor(current.layout.recentsSide, navBar) == RecentsSide.left;
  final Widget recentsButton = DVBox(
    RecentsButtonIcon(glyph: navBar.glyph),
    DVModifier().width(dockIcon).height(dockIcon).backgroundColor(const Color(0x33FFFFFF)).rounded(dockIcon * 0.5).align(Alignment.center).tooltip('Recent apps').semanticLabel('Recent apps').onTap(() => show('recents')),
  );

  final Widget content = DVBox.list(<Widget>[
    if (current.preview)
      DVText('Preview: Dev Launcher is an Android home screen. Here it shows example apps.').modifier(wallMono(size: 13, color: WallpaperColors.muted).backgroundColor(WallpaperColors.surface).rounded(10).padding(12)),
    DVBox.list(<Widget>[
      DVText(clock).modifier(wallMono(size: clockSize, bold: true).lineHeight(1).semanticHeading(1).semanticLabel('Dev Launcher, $clock').align(watch ? Alignment.center : Alignment.centerLeft)),
      DVText(watch ? date : '$date · ${current.apps.length} apps').modifier(wallMono(size: watch ? 12 : 15, color: WallpaperColors.text).align(watch ? Alignment.center : Alignment.centerLeft)),
    ], spacing: 6, modifier: DVModifier().onDoubleTap(lockScreen).onLongPress(() => show('launcher-settings')).tooltip('Double-tap to lock the screen; long-press for launcher settings')),
    if (!current.isDefault && !current.preview)
      DVBox.list(<Widget>[
        DVText('Dev Launcher is not your home app yet.').modifier(wallMono(size: 14)),
        DVText('Make it my home app').modifier(
          wallMono(size: 14, bold: true, color: WallpaperColors.page).backgroundColor(WallpaperColors.accent).rounded(10).paddingSymmetric(horizontal: 16, vertical: 12).minimumTapTarget(width: 48, height: 48).tooltip('Ask Android to make Dev Launcher the home app').onTap(() async {
            status.value = await store.askToBeDefault();
          }),
        ),
      ], spacing: 10, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(WallpaperColors.surface).border(Border.all(color: WallpaperColors.accent)).rounded(14).padding(14)),
    if (!watch)
      DVBox.row(<Widget>[
        DVText('❯').modifier(wallMono(size: 18, bold: true, color: WallpaperColors.accent)),
        DVText(query).modifier(
          // No floating label: it reserves a line above the text, which pushed
          // the typed text below the prompt sign. The hint says it in the field
          // and the semantic label names it for a screen reader.
          wallMono(size: 16).semanticLabel('Command').input(
            hint: 'type an app or a command',
            onChanged: (String value) {
              typed.value = value;
              status.value = '';
            },
            onSubmitted: submit,
          ),
        ),
      ], spacing: 10, crossAlign: DVCrossAlign.center, modifier: DVModifier().backgroundColor(const Color(0xCC151B23)).border(Border.all(color: WallpaperColors.rule)).rounded(12).paddingSymmetric(horizontal: 14, vertical: 4).maxWidth(720)),
    // Why the apps could not be read, rather than an empty screen that only
    // says to long-press an app.
    if (current.problem.isNotEmpty) DVText(current.problem).modifier(wallMono(size: 13, color: WallpaperColors.text).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (status.value.isNotEmpty) DVText(status.value).modifier(wallMono(size: 13, color: WallpaperColors.text).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (newerRelease != null && !watch)
      DVText('Dev Launcher ${newerRelease.version} is out · tap to download').modifier(
        wallMono(size: 13, bold: true, color: WallpaperColors.page).backgroundColor(WallpaperColors.accent).rounded(10).paddingSymmetric(horizontal: 14, vertical: 12).minimumTapTarget(width: 48, height: 48)
            .semanticLabel('Dev Launcher ${newerRelease.version} is out. This phone has $launcherVersion. Open updates')
            .tooltip('See what is new and download it')
            .onTap(() => show('updates')),
      ),
    if (query.trim().isNotEmpty) ...<Widget>[
      AppSection(title: 'matches', onWallpaper: true, apps: matches.take(columns * 2).toList(), columns: columns, iconSize: iconSize, badges: badges, onOpen: open, onMore: (String package) => selected.value = package),
      if (matches.isEmpty) DVText('Enter runs it. Try: info, pin, unpin, uninstall + an app, or settings.').modifier(wallMono(size: 13, color: WallpaperColors.muted)),
      SearchExtras(query: search, snapshot: current, onWallpaper: true, onDone: (String problem) {
        status.value = problem;
        if (problem.isEmpty) typed.value = '';
      }),
    ],
    if (hasHome)
      HomeGrid(
        snapshot: current,
        columns: columns,
        width: (size.width - side * 2).clamp(0, 720).toDouble(),
        iconSize: iconSize,
        arranging: arranging.value,
        onOpen: open,
        onMore: (String package) {
          sheetFolder.value = '';
          selected.value = package;
        },
        onFolder: (String id) => show('$folderPrefix$id'),
        onDoneArranging: () {
          arranging.value = false;
          releaseBackWhenIdle();
        },
      )
    else if (!current.loading && !watch)
      DVText('Long-press any app to put it here or in the dock.').modifier(wallMono(size: 13, color: WallpaperColors.text).backgroundColor(const Color(0x99151B23)).rounded(8).padding(10)),
    if (devTools.isNotEmpty && !watch) AppSection(title: 'dev tools', onWallpaper: true, apps: devTools, columns: columns, iconSize: iconSize, badges: badges, onOpen: open, onMore: (String package) => selected.value = package),
    if (watch) DVBox(appsButton, DVModifier().centered()),
  // Scrolls when it is taller than the room above the dock (a small phone,
  // large text, many apps on home): nothing is cut off out of reach.
  ], spacing: watch ? 14 : 22, modifier: DVModifier().paddingOnly(left: side, right: side, top: watch ? side * 0.6 : 28, bottom: 24)).scrollable();

  // Every dock item sits in the same slot, an app tile's size (its icon and
  // the tile's padding), with the item in the middle of it; the row spaces
  // the slots evenly and centres them on one line.
  final double dockSlot = dockIcon + 12;
  Widget slot(Widget item) => DVBox(item, DVModifier().width(dockSlot).height(dockSlot).align(Alignment.center));
  final Widget dockRow = DVBox.row(<Widget>[
    if (recentsFirst) slot(recentsButton),
    for (final DVInstalledApp app in dock.take(dock.length > 2 ? 2 : dock.length)) slot(AppTile(app: app, iconSize: dockIcon, showLabel: false, badge: current.badgeFor(app.packageName), onOpen: () => open(app.packageName), onMore: () => selected.value = app.packageName)),
    slot(appsButton),
    for (final DVInstalledApp app in dock.skip(2)) slot(AppTile(app: app, iconSize: dockIcon, showLabel: false, badge: current.badgeFor(app.packageName), onOpen: () => open(app.packageName), onMore: () => selected.value = app.packageName)),
    if (!recentsFirst) slot(recentsButton),
  ], spacing: 0, align: DVAlign.spaceEvenly, crossAlign: DVCrossAlign.center, modifier: DVModifier().backgroundColor(const Color(0x40FFFFFF)).rounded(28).paddingSymmetric(horizontal: 4, vertical: 6).maxWidth(kind == ScreenKind.phone ? double.infinity : 640));

  // Drag up from the dock (or the handle above it) and the drawer follows the
  // finger, one to one; let go and it settles open or closed.
  final DVModifier dragUp = DVModifier().onGesture(DVGesture(
    onUpdate: (ScaleUpdateDetails details) => dragDrawer(details.focalPointDelta.dy),
    onEnd: (ScaleEndDetails details) => releaseDrawer(details.velocity.pixelsPerSecond.dy),
  ));
  final double top = drawerTop.value ?? size.height;
  final Widget drawer = DVBox(
    DVBox(AppDrawer(onClose: closeDrawer, onDrag: dragDrawer, onDragEnd: releaseDrawer, onSettings: () {
      show('launcher-settings');
      closeDrawer();
    }, onUpdates: () {
      // Updates first, so closing the drawer keeps Back for it.
      show('updates');
      closeDrawer();
    }), DVModifier().height(size.height)),
    // Always animated, with no duration while a finger drags: switching the
    // animation off rebuilt the drawer and cancelled the drag after one move.
    // Only the slide is animated, never the height: an animated height chased
    // every change of the screen and left the home screen showing under the
    // drawer (0.1.14, with the keyboard).
    DVModifier().offset(0, top).animate(dragging.value ? .zero : const Duration(milliseconds: 220)),
  );
  final Widget dragHandle = DVBox(
    DVText('').modifier(DVModifier().width(44).height(5).backgroundColor(const Color(0x88FFFFFF)).rounded(3)),
    DVModifier().centered().paddingSymmetric(vertical: 8).tooltip('Drag up, or tap, for all apps').onTap(openDrawer).merge(dragUp),
  );

  // A browser has no wallpaper to show: the preview sits on the dark page.
  return DVBox(DVBox.stack(<Widget>[
    DVBox.list(<Widget>[
      // The content takes whatever the dock leaves: no height worked out by
      // hand. The page shell's SafeArea keeps both clear of the status and
      // navigation bars (owner, 21 Nov: a hand-made 85 left a 40 dp gap).
      DVBox(content, DVModifier().fill().clipContent().onSwipeLeft(() => show('recents')).onSwipeDown(pullShade).onGesture(DVGesture(
        onStart: (ScaleStartDetails details) => pinch.value = 1,
        onUpdate: (ScaleUpdateDetails details) {
          if (details.pointerCount >= 2 && details.scale < pinch.read()) pinch.value = details.scale;
        },
        onEnd: (ScaleEndDetails details) {
          if (pinch.read() < 0.8 && current.layout.options.pinchSettings) show('launcher-settings');
          pinch.value = 1;
        },
      ))),
      // The dock at the bottom, in a band at least as tall as the keyboard:
      // with the keyboard up the content above ends at its top, and the dock
      // stays where it was, behind it.
      if (!watch)
        DVBox(
          DVBox.list(<Widget>[
            DVBox(DVBox.list(<Widget>[dragHandle, dockRow], spacing: 0), DVModifier().paddingOnly(left: side, right: side, bottom: 8).centered().merge(dragUp)),
            navigationBarRoom(context),
          ], spacing: 0),
          DVModifier().minHeight(keyboardOver(context)).align(Alignment.bottomCenter),
        )
      else
        keyboardRoom(context),
    ], spacing: 0, modifier: DVModifier().height(size.height)),
    drawer,
    if (overlay.value == 'recents') RecentsScreen(onClose: () => show(''), onSettings: () {
      settingsFrom.value = 'recents';
      show('settings');
    }),
    if (overlay.value == 'settings') RecentsSettings(onClose: () => show('recents')),
    if (overlay.value == 'updates') UpdatesScreen(onClose: () => show('')),
    if (overlay.value == 'launcher-settings')
      LauncherSettings(
        onClose: () => show(''),
        onRecentsSettings: () {
          settingsFrom.value = 'launcher-settings';
          show('settings');
        },
        onUpdates: () => show('updates'),
      ),
    if (openFolder != null)
      // Centred in the room the keyboard leaves: renaming a folder keeps its
      // name in sight.
      aboveKeyboard(
        context,
        DVBox(
          FolderView(
            folder: openFolder,
            snapshot: current,
            columns: columns,
            iconSize: iconSize,
            onOpen: (String package) {
              show('');
              open(package);
            },
            onMore: (String package) {
              sheetFolder.value = openFolder.id;
              selected.value = package;
            },
            onClose: () => show(''),
          ),
          DVModifier().align(Alignment.center).padding(16),
        ),
        height: size.height,
      ),
    if (sheetApp != null)
      aboveKeyboard(
        context,
        DVBox(
          AppSheet(
            app: sheetApp,
            snapshot: current,
            folderId: sheetFolder.value,
            onArrange: () {
              show('');
              arranging.value = true;
              claimBack();
            },
            onDone: (String problem) {
              status.value = problem;
              selected.value = '';
              sheetFolder.value = '';
            },
          ),
          DVModifier().align(Alignment.bottomCenter).padding(watch ? side * 0.5 : 16),
        ),
        height: size.height,
      ),
  ], modifier: DVModifier().gradient(wallpaperScrim).minHeight(size.height).clipContent()), DVModifier().backgroundColor(current.preview ? WallpaperColors.page : const Color(0x00000000)));
}
