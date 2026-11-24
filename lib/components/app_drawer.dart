// Every app A to Z, over the wallpaper: a search field (with a clear button),
// letter sections, and a letter index on the right edge, as on Pixel and
// iPhone launchers: tap a letter, or drag along the index, and that letter's
// apps come to the top. The index never filters: every app stays in the list.
// Tap opens, long press offers the rest. Back, a swipe down, or leaving for an
// app returns home.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import '../services/updates.dart';
import 'app_tiles.dart';
import 'launcher_home.dart' show deviceLocale, followStore;
import 'theme.dart';

@DVFunctionalWidget()
Widget _appDrawer(BuildContext context, {VoidCallback? onClose, ValueChanged<double>? onDrag, ValueChanged<double>? onDragEnd, VoidCallback? onUpdates, VoidCallback? onSettings}) {
  followLauncherTheme(context, LauncherStore.instance.current.layout.options);
  // Embedded in the home screen, the drawer is closed by the home screen;
  // on its own (/apps) it goes back.
  void close() => onClose != null ? onClose() : DV.Navigation.back();
  final bool embedded = onClose != null;
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> search = context.signal('');
  // The letter under the finger while it drags along the index, and where the
  // finger is (for the bubble); empty when no finger is on the index.
  final DVSignal<String> scrubbing = context.signal('');
  final DVSignal<double> scrubAt = context.signal(0.0);
  // Where each letter's section is, so the index can bring it to the top.
  final DVSignal<Map<String, BuildContext>> anchors = context.signal(<String, BuildContext>{});
  final DVSignal<String> selected = context.signal('');
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> settingsOpen = context.signal(false);
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
  final List<LauncherApp> shown = query.isEmpty ? current.visibleLauncherApps : matchApps(current.visibleLauncherApps, query);
  final List<LetterSection> sections = letterSections(shown);
  final Map<String, int> appsPerLetter = <String, int>{for (final LetterSection section in sections) section.letter: section.apps.length};
  // Not on a watch, and not before the screen has a height (the first frame
  // can have none): 27 letters need room.
  final bool showIndex = !watch && sections.isNotEmpty && size.height >= 360;
  // The index on the end edge of the reading direction: right on most phones,
  // left on a phone set to a right-to-left language (Arabic, Hebrew, Urdu...),
  // unless the person chose a side in the drawer settings.
  final bool rtlDirection = Directionality.of(context) == TextDirection.rtl;
  final bool indexLeft = indexOnLeft(current.layout.indexSide, rightToLeft: rtlDirection || Bidi.isRtlLanguage(deviceLocale()));
  final DVInstalledApp? sheetApp = selected.value.isEmpty ? null : current.app(selected.value);
  final List<DVInstalledApp> recent = current.recentApps.take(columns).toList();

  // The page shell's SafeArea already keeps the drawer under the status bar.
  // The drawer's settings: which edge the letter index takes.
  Widget indexChoice(IndexSide choice, String name, String hint) {
    final bool picked = current.layout.indexSide == choice;
    return DVText(picked ? '● $name' : '○ $name').modifier(
      mono(size: 14, bold: picked, color: picked ? LauncherColors.accent : LauncherColors.text)
          .paddingSymmetric(horizontal: 8, vertical: 10)
          .minimumTapTarget(width: 48, height: 48)
          .semanticLabel('Letter index: $name${picked ? ', selected' : ''}')
          .tooltip(hint)
          .onTap(() async => status.value = await store.setIndexSide(choice)),
    );
  }
  final Widget drawerSettings = DVBox.list(<Widget>[
    DVText('letter index side').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(2)),
    DVBox.wrapLine(<Widget>[
      indexChoice(IndexSide.device, 'Follow device', 'Right, or left on a phone set to a right-to-left language'),
      indexChoice(IndexSide.left, 'Left', 'The letter index on the left edge'),
      indexChoice(IndexSide.right, 'Right', 'The letter index on the right edge'),
    ], spacing: 4),
  ], spacing: 6, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(12).padding(12).maxWidth(720));
  // Drag the header (handle, title, search) and the drawer follows the
  // finger; let go and it settles. It sits below the status bar, where a
  // finger can reach it.
  final DVModifier dragDown = DVModifier().onGesture(DVGesture(
    onUpdate: (ScaleUpdateDetails details) => onDrag?.call(details.focalPointDelta.dy),
    onEnd: (ScaleEndDetails details) => onDragEnd?.call(details.velocity.pixelsPerSecond.dy),
  ));
  final Widget handle = DVBox(
    DVText('').modifier(DVModifier().width(44).height(5).backgroundColor(LauncherColors.rule).rounded(3)),
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
      // The field, and an x at its end while it holds text: x empties it and
      // leaves the focus (and the keyboard) in it, ready for the next word.
      // The field comes first, so the x appearing never rebuilds it.
      DVBox.row(<Widget>[
        DVBox(
          DVText(search.value).modifier(mono(size: 16).input(
                label: 'Search apps',
                hint: 'name or package',
                onChanged: (String value) => search.value = value,
              )),
          DVModifier().fill(),
        ),
        if (search.value.isNotEmpty)
          DVText('×').modifier(
            mono(size: 22, color: LauncherColors.muted).centered().minimumTapTarget(width: 44, height: 44).semanticLabel('Clear search').tooltip('Clear search').onTap(() => search.value = ''),
          ),
      ], spacing: 4, crossAlign: DVCrossAlign.center, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(12).paddingOnly(left: 14, right: 4, top: 4, bottom: 4).maxWidth(720)),
  ], spacing: 8, modifier: DVModifier().backgroundColor(LauncherColors.page).paddingOnly(left: side, right: side, top: (watch ? side * 0.4 : 4), bottom: 8).merge(embedded ? dragDown : DVModifier()));

  final Widget settingsLink = DVText(settingsOpen.value ? 'hide settings' : 'drawer settings').modifier(mono(size: 13, color: settingsOpen.value ? LauncherColors.accent : LauncherColors.muted).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Drawer settings').tooltip(settingsOpen.value ? 'Hide the drawer settings' : 'Drawer settings: which side the letter index is on').onTap(() => settingsOpen.value = !settingsOpen.read()));
  final Widget list = DVBox.list(<Widget>[
    // The drawer's own settings, at the top of the list: a short link, so the
    // header stays one line on the smallest phone with the largest font.
    // Updates on the left, the drawer's settings on the right, one line.
    if (!watch)
      DVBox.wrapLine(<Widget>[
        DVText('updates · $launcherVersion').modifier(mono(size: 13, color: LauncherColors.muted).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Updates: this phone has Dev Launcher $launcherVersion').tooltip('Which version this phone has, and the newest one to download').onTap(() => onUpdates != null ? onUpdates() : DV.Navigation.navigate(DVRoutes.updates))),
        if (onSettings != null) DVText('settings').modifier(mono(size: 13, color: LauncherColors.muted).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Launcher settings').tooltip('Launcher settings: gestures, badges, hidden apps, wallpaper, backup').onTap(onSettings)),
        settingsLink,
      ], spacing: 0),
    if (settingsOpen.value && !watch) drawerSettings,
    // The apps opened last, newest first: one row, above the A-Z list, as
    // phone launchers put their suggestions. Hidden while searching, where it
    // would push the answer down.
    if (query.isEmpty && recent.isNotEmpty)
      DVBox.list(<Widget>[
        DVText('recent').modifier(mono(size: 13, bold: true, color: LauncherColors.accent).semanticHeading(2)),
        DVBox.grid(<Widget>[
          for (final DVInstalledApp app in recent) AppTile(app: app, iconSize: iconSize, badge: current.badgeFor(app.packageName), onOpen: () => open(app.packageName), onMore: () => more(app.packageName)),
        ], columns: columns, spacing: 4, responsive: false),
      ], spacing: 8),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(LauncherColors.surface).rounded(8).padding(10).semanticRole('status')),
    if (current.loading) DVText('reading apps…').modifier(mono(size: 13, color: LauncherColors.muted)),
    if (!current.loading && shown.isEmpty) DVText('No app matches "$query".').modifier(mono(size: 14)),
    for (final LetterSection section in sections)
      SectionAnchor(
        letter: section.letter,
        anchors: anchors.read(),
        child: DVBox.list(<Widget>[
          DVText(section.letter).modifier(mono(size: 13, bold: true, color: LauncherColors.accent).semanticHeading(2)),
          DVBox.grid(<Widget>[
            for (final DVInstalledApp app in installedFor(current, section.apps)) AppTile(app: app, iconSize: iconSize, badge: current.badgeFor(app.packageName), onOpen: () => open(app.packageName), onMore: () => more(app.packageName)),
          ], columns: columns, spacing: 4, responsive: false),
        ], spacing: 8),
      ),
    if (query.isNotEmpty && !watch)
      SearchExtras(query: query, snapshot: current, onDone: (String problem) => status.value = problem),
  ], spacing: 16, modifier: DVModifier().paddingOnly(left: showIndex && indexLeft ? (kind == ScreenKind.tv ? 44 : 34) : side, right: showIndex && !indexLeft ? (kind == ScreenKind.tv ? 44 : 34) : side, top: 8, bottom: 12)).scrollable();

  // The letter index: # and A to Z down the right edge, each letter one cell
  // of the same height, so the cell under a finger is its height divided into
  // how far down the finger is. A letter with apps brings them to the top; a
  // letter with none is dimmed, and a finger on it shows the next letter that
  // has some.
  // It lies over the list, from just under the header to the bottom edge, so
  // it always fits whatever the screen and font size; the header's height is
  // worked out from the same sizes the header uses.
  final double textScale = MediaQuery.textScalerOf(context).scale(1);
  final double indexTop = 4 + (embedded ? 25 : 0) + (14 * 1.3 * textScale + 20).clamp(48.0, double.infinity) + 8 + (16 * 1.3 * textScale + 34).clamp(52.0, double.infinity) + 16;
  final double cell = ((size.height - indexTop - 8) / indexLetters.length).clamp(8.0, kind == ScreenKind.tv ? 36.0 : 26.0);
  final double letterSize = (cell * 0.7).clamp(7.0, 12.0);
  final double indexWidth = kind == ScreenKind.tv ? 40 : 30;
  void jump(String letter) {
    final String? target = sectionFor(letter, appsPerLetter);
    if (target != null) revealSection(target, anchors.read());
  }
  // The letter under [dy]: the top half holds the first 14 letters, the
  // bottom half the other 13, each half the same height.
  final double half = cell * indexLetters.length / 2;
  void scrub(double dy) {
    final int at = dy < half ? (dy / (half / 14)).floor() : 14 + ((dy - half) / (half / (indexLetters.length - 14))).floor();
    final String letter = indexLetters[at.clamp(0, indexLetters.length - 1)];
    scrubAt.value = dy.clamp(0.0, cell * indexLetters.length);
    if (letter == scrubbing.read()) return;
    scrubbing.value = letter;
    jump(letter);
  }
  Widget indexCell(String letter) => (appsPerLetter[letter] ?? 0) > 0
      ? DVText(letter).modifier(
          mono(size: letterSize, bold: true, color: scrubbing.value == letter ? LauncherColors.accent : LauncherColors.text)
              .width(indexWidth)
              .fill()
              .centered()
              .semanticLabel('Jump to $letter, ${appsPerLetter[letter]} ${appsPerLetter[letter] == 1 ? 'app' : 'apps'}')
              .tooltip('Jump to apps starting with $letter')
              .onTap(() => jump(letter)),
        )
      : DVText(letter).modifier(
          mono(size: letterSize, color: LauncherColors.muted.withValues(alpha: 0.4)).width(indexWidth).fill().centered().semanticLabel('$letter, no apps start with $letter').tooltip('$letter, no apps start with $letter: goes to the next letter that has some').onTap(() => jump(letter)),
        );
  // Two halves: a Dartvel list longer than 24 builds its far rows later, and
  // every letter must be there at once. Each half takes half the height and
  // each letter an equal share of its half, so nothing can overflow whatever
  // a frame gives the index.
  Widget indexHalf(List<String> letters) => DVBox(DVBox.list(<Widget>[for (final String letter in letters) indexCell(letter)], spacing: 0, crossAlign: DVCrossAlign.center), DVModifier().fill());
  final Widget index = DVBox.list(<Widget>[
    indexHalf(indexLetters.take(14).toList()),
    indexHalf(indexLetters.skip(14).toList()),
  ], spacing: 0, crossAlign: DVCrossAlign.center, modifier: DVModifier().width(indexWidth).height(cell * indexLetters.length).onGesture(DVGesture(
        onStart: (ScaleStartDetails details) => scrub(details.localFocalPoint.dy),
        onUpdate: (ScaleUpdateDetails details) => scrub(details.localFocalPoint.dy),
        onEnd: (ScaleEndDetails details) => scrubbing.value = '',
      )));

  // The index and its bubble are placed by offset from the corner, sized to
  // themselves, so they take no touches meant for the list around them. A
  // stack starts at the right in a right-to-left direction.
  double fromLeft(double left, double width) => rtlDirection ? left - (size.width - width) : left;

  // While a finger is on the index, a bubble beside it names the letter.
  final Widget? bubble = scrubbing.value.isEmpty
      ? null
      : DVBox(
          DVText(scrubbing.value).modifier(mono(size: 28, bold: true, color: LauncherColors.page).align(Alignment.center).width(56).height(56).backgroundColor(LauncherColors.accent).rounded(28).semanticLabel('Showing ${scrubbing.value}').semanticRole('status')),
          DVModifier().offset(fromLeft(indexLeft ? indexWidth + 16 : size.width - indexWidth - 16 - 56, 56), (indexTop + scrubAt.value - 28).clamp(0.0, double.infinity)),
        );

  final Widget placedIndex = DVBox(index, DVModifier().offset(fromLeft(indexLeft ? 0 : size.width - indexWidth, indexWidth), indexTop));

  return DVBox.stack(<Widget>[
    // The header as tall as its contents need, whatever the font size, and
    // the list the rest of the screen.
    DVBox.list(<Widget>[header, DVBox(list, DVModifier().fill())], spacing: 0, modifier: DVModifier().height(size.height)),
    if (showIndex) placedIndex,
    if (showIndex) ?bubble,
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

/// One letter's section of the list, remembered in [anchors] under [letter]
/// so the index can bring it to the top.
@DVFunctionalWidget()
Widget _sectionAnchor(BuildContext context, {required String letter, required Map<String, BuildContext> anchors, required Widget child}) {
  anchors[letter] = context;
  return child;
}

/// Scrolls the list so [letter]'s section starts at its top, as far as the
/// list can go (the last letters cannot rise past the end of the list). At
/// once, so a finger dragging along the index is followed with no lag.
///
/// A long Dartvel list builds only the rows near the screen, so a far
/// section may not exist yet: the list is moved to the last section that
/// does on the way there, which builds the next ones, and this goes on the
/// next frame, a few frames at most.
// Dartvel 3.47.2 has no "scroll this box into view" primitive yet; this is
// the one Flutter call in the drawer, to move to it when the framework has one.
int _revealing = 0;

void revealSection(String letter, Map<String, BuildContext> anchors) => _reveal(letter, anchors, ++_revealing, 40);

// One step towards [letter]; a newer request ([generation] is no longer the
// latest) stops this one, so a finger moving along the index is followed to
// where it is now, not where it was.
void _reveal(String letter, Map<String, BuildContext> anchors, int generation, int tries) {
  if (generation != _revealing) return;
  bool built(String candidate) => anchors[candidate]?.mounted ?? false;
  if (built(letter)) {
    Scrollable.ensureVisible(anchors[letter]!, alignment: 0, duration: Duration.zero);
    return;
  }
  if (tries <= 0) return;
  final int wanted = indexLetters.indexOf(letter);
  // The built section nearest the one wanted, on its side.
  final List<String> builtLetters = <String>[for (final String candidate in indexLetters) if (built(candidate)) candidate];
  if (builtLetters.isEmpty) return;
  final List<String> before = builtLetters.where((String candidate) => indexLetters.indexOf(candidate) < wanted).toList();
  final String step = before.isNotEmpty ? before.last : builtLetters.first;
  Scrollable.ensureVisible(anchors[step]!, alignment: before.isNotEmpty ? 0 : 1, duration: Duration.zero);
  WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(letter, anchors, generation, tries - 1));
  WidgetsBinding.instance.scheduleFrame();
}
