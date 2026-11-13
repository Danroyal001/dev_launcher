// Every app A to Z, over the wallpaper: a search field, a letter index that
// narrows the list to one letter, and letter sections. Tap opens, long press
// offers the rest. Back, a swipe down, or leaving for an app returns home.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import 'app_tiles.dart';
import 'launcher_home.dart' show followStore;
import 'theme.dart';

@DVFunctionalWidget()
Widget _appDrawer(BuildContext context, {VoidCallback? onClose, ValueChanged<double>? onDrag, ValueChanged<double>? onDragEnd}) {
  // Embedded in the home screen, the drawer is closed by the home screen;
  // on its own (/apps) it goes back.
  void close() => onClose != null ? onClose() : DV.Navigation.back();
  final bool embedded = onClose != null;
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> search = context.signal('');
  final DVSignal<String> letter = context.signal('');
  final DVSignal<String> selected = context.signal('');
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> started = context.signal(false);

  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      followStore(context, snapshot);
      store.start();
      // An app opened from here: when the person comes back with home, they
      // land on the home screen, as on every launcher.
      late final StreamSubscription<DVAppLifecycle> lifecycle;
      lifecycle = DV.lifecycle.app.changes.listen((DVAppLifecycle state) {
        if (!context.mounted) {
          lifecycle.cancel();
          return;
        }
        if (state == DVAppLifecycle.backgrounded && !embedded) {
          lifecycle.cancel();
          DV.Navigation.back();
        }
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

  // An app opened from here: the drawer closes behind it, so coming back
  // lands on the home screen. Android does not always stop the home app
  // while another is in front, so closing when the launcher is backgrounded
  // missed it (Appetize, Android 12).
  Future<void> open(String package) async {
    final String problem = await openApp(package);
    status.value = problem;
    if (problem.isEmpty && embedded) close();
  }
  void more(String package) => selected.value = package;

  final String query = search.value.trim();
  final List<LauncherApp> shown = query.isEmpty ? current.launcherApps : matchApps(current.launcherApps, query);
  final List<LetterSection> sections = letterSections(shown);
  final List<LetterSection> visible = letter.value.isEmpty || query.isNotEmpty ? sections : sections.where((LetterSection s) => s.letter == letter.value).toList();
  final DVInstalledApp? sheetApp = selected.value.isEmpty ? null : current.app(selected.value);
  final List<DVInstalledApp> recent = current.recentApps.take(columns).toList();

  final double safeTop = MediaQuery.paddingOf(context).top;
  // Drag the header (handle, title, search) and the drawer follows the
  // finger; let go and it settles. It sits below the status bar, where a
  // finger can reach it.
  final DVModifier dragDown = DVModifier().onGesture(DVGesture(
    onUpdate: (ScaleUpdateDetails details) => onDrag?.call(details.focalPointDelta.dy),
    onEnd: (ScaleEndDetails details) => onDragEnd?.call(details.velocity.pixelsPerSecond.dy),
  ));
  final Widget handle = DVBox(
    DVText('').modifier(DVModifier().width(44).height(5).backgroundColor(const Color(0x88FFFFFF)).rounded(3)),
    DVModifier().centered().paddingSymmetric(vertical: 10).tooltip('Drag down, or tap, to close all apps').onTap(close),
  );
  final Widget header = DVBox.list(<Widget>[
    if (embedded) handle,
    DVBox.row(<Widget>[
      DVText('‹ home').modifier(mono(size: 14, color: LauncherColors.text).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).tooltip('Back to the home screen').onTap(close)),
      // The title takes what the back link leaves, and ends in … rather than
      // pushing past the edge on a small phone with large text.
      DVBox(DVText(watch ? 'apps' : 'all apps · ${current.apps.length}').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).maxLines(1).overflow(TextOverflow.ellipsis).semanticHeading(1)), DVModifier().fill()),
    ], spacing: 8, crossAlign: DVCrossAlign.start),
    if (!watch)
      DVText(search.value).modifier(
        mono(size: 16).backgroundColor(const Color(0xCC151B23)).border(Border.all(color: LauncherColors.rule)).rounded(12).paddingSymmetric(horizontal: 14, vertical: 4).maxWidth(720).input(
              label: 'Search apps',
              hint: 'name or package',
              onChanged: (String value) {
                search.value = value;
                letter.value = '';
              },
            ),
      ),
  ], spacing: 8, modifier: DVModifier().backgroundColor(LauncherColors.page).paddingOnly(left: side, right: side, top: safeTop + (watch ? side * 0.4 : 4), bottom: 8).merge(embedded ? dragDown : DVModifier()));

  final Widget list = DVBox.list(<Widget>[
    // The apps opened last, newest first: one row, above the A-Z list, as
    // phone launchers put their suggestions. Hidden while searching or
    // looking at one letter, where it would push the answer down.
    if (query.isEmpty && letter.value.isEmpty && recent.isNotEmpty)
      DVBox.list(<Widget>[
        DVText('recent').modifier(mono(size: 13, bold: true, color: LauncherColors.accent).semanticHeading(2)),
        DVBox.grid(<Widget>[
          for (final DVInstalledApp app in recent) AppTile(app: app, iconSize: iconSize, onOpen: () => open(app.packageName), onMore: () => more(app.packageName)),
        ], columns: columns, spacing: 4, responsive: false),
      ], spacing: 8),
    if (query.isEmpty && sections.length > 1 && !watch)
      DVBox.wrapLine(<Widget>[
        for (final LetterSection section in sections)
          DVText(section.letter).modifier(
            mono(size: watch ? 13 : 15, bold: letter.value == section.letter, color: letter.value == section.letter ? LauncherColors.accent : LauncherColors.text)
                .paddingSymmetric(horizontal: 8, vertical: 6)
                .minimumTapTarget(width: 40, height: 40)
                .tooltip(letter.value == section.letter ? 'Show every letter again' : 'Only apps starting with ${section.letter}')
                .onTap(() => letter.value = letter.read() == section.letter ? '' : section.letter),
          ),
      ], spacing: 0),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (current.loading) DVText('reading apps…').modifier(mono(size: 13, color: LauncherColors.muted)),
    if (!current.loading && shown.isEmpty) DVText('No app matches "$query".').modifier(mono(size: 14)),
    for (final LetterSection section in visible)
      DVBox.list(<Widget>[
        DVText(section.letter).modifier(mono(size: 13, bold: true, color: LauncherColors.accent).semanticHeading(2)),
        DVBox.grid(<Widget>[
          for (final DVInstalledApp app in installedFor(current, section.apps)) AppTile(app: app, iconSize: iconSize, onOpen: () => open(app.packageName), onMore: () => more(app.packageName)),
        ], columns: columns, spacing: 4, responsive: false),
      ], spacing: 8),
  ], spacing: 16, modifier: DVModifier().paddingOnly(left: side, right: side, top: 8, bottom: 32 + MediaQuery.paddingOf(context).bottom)).scrollable();

  return DVBox.stack(<Widget>[
    // The header as tall as its contents need, whatever the font size, and
    // the list the rest of the screen.
    DVBox.list(<Widget>[header, DVBox(list, DVModifier().fill())], spacing: 0, modifier: DVModifier().height(size.height)),
    if (sheetApp != null)
      DVBox(
        AppSheet(app: sheetApp, snapshot: current, onDone: (String problem) {
          status.value = problem;
          selected.value = '';
        }),
        DVModifier().align(Alignment.bottomCenter).padding(watch ? side * 0.5 : 16),
      ),
  ], modifier: DVModifier().backgroundColor(LauncherColors.page).minHeight(size.height).merge(embedded ? DVModifier() : DVModifier().onSwipeDown(close)));
}
