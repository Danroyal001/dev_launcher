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
Widget _appDrawer(BuildContext context) {
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
        if (state == DVAppLifecycle.backgrounded) {
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

  Future<void> open(String package) async => status.value = await openApp(package);
  void more(String package) => selected.value = package;

  final String query = search.value.trim();
  final List<LauncherApp> shown = query.isEmpty ? current.launcherApps : matchApps(current.launcherApps, query);
  final List<LetterSection> sections = letterSections(shown);
  final List<LetterSection> visible = letter.value.isEmpty || query.isNotEmpty ? sections : sections.where((LetterSection s) => s.letter == letter.value).toList();
  final DVInstalledApp? sheetApp = selected.value.isEmpty ? null : current.app(selected.value);

  final Widget list = DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      DVText('‹ home').modifier(mono(size: 14, color: LauncherColors.text).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).tooltip('Back to the home screen').onTap(() => DV.Navigation.back())),
      DVText(watch ? 'apps' : 'all apps · ${current.apps.length}').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).semanticHeading(1)),
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
  ], spacing: 16, modifier: DVModifier().paddingOnly(left: side, right: side, top: watch ? side * 0.6 : 24, bottom: 32)).scrollable();

  return DVBox.stack(<Widget>[
    DVBox(list, DVModifier().height(size.height)),
    if (sheetApp != null)
      DVBox(
        AppSheet(app: sheetApp, snapshot: current, onDone: (String problem) {
          status.value = problem;
          selected.value = '';
        }),
        DVModifier().align(Alignment.bottomCenter).padding(watch ? side * 0.5 : 16),
      ),
  ], modifier: DVModifier().backgroundColor(current.preview ? LauncherColors.page : const Color(0xB30B0F14)).minHeight(size.height).onSwipeDown(() => DV.Navigation.back()));
}
