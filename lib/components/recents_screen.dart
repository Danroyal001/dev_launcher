// Dev Launcher's own Recents, laid out as a phone's: a row of large app cards,
// newest first, scrolled sideways. Tap a card to open the app, swipe it up
// (or its x) to close it, and "Clear all" after the last card. A home app
// cannot be the phone's Recents (only the system's or the phone maker's
// launcher can), so this is the Recents that always works: from the dock's
// Recents button, a swipe left on the home screen, and the phone's Recents
// button wherever the phone lets Dev Launcher hear it.
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import 'app_tiles.dart';
import 'launcher_home.dart' show followStore;
import 'theme.dart';

@DVFunctionalWidget()
Widget _recentsScreen(BuildContext context, {VoidCallback? onClose, VoidCallback? onSettings}) {
  // Embedded in the home screen it is closed by the home screen; on its own
  // (/recents) it goes back.
  void close() => onClose != null ? onClose() : DV.Navigation.back();
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> started = context.signal(false);
  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      followStore(context, snapshot);
      store.start();
    });
  }

  final LauncherSnapshot current = snapshot.value;
  final Size size = MediaQuery.sizeOf(context);
  final ScreenKind kind = screenKindFor(width: size.width, height: size.height);
  final bool watch = kind == ScreenKind.watch;
  final double side = watch ? roundSafeInset(size.shortestSide) : (kind == ScreenKind.tv ? 56 : 20);
  final List<DVInstalledApp> recent = current.recentApps;

  Future<void> open(String package) async {
    final String problem = await openApp(package);
    status.value = problem;
    if (problem.isEmpty) close();
  }

  Widget link(String label, String hint, VoidCallback onTap, {Color color = LauncherColors.text}) =>
      DVText(label).modifier(mono(size: 14, color: color).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).tooltip(hint).onTap(onTap));

  // A card per app, as a phone's Recents draws them: the app's colour, its
  // icon and name, large; swipe it up to close it, tap it to open the app.
  // Android shows a home app it installed no other app's screenshot, so the
  // card is the app's icon on its own colour, not a picture of its screen.
  final double cardWidth = watch ? size.width * 0.7 : (size.width * 0.66).clamp(200.0, 360.0);
  final double cardHeight = watch ? size.height * 0.6 : (size.height * 0.56).clamp(260.0, 640.0);
  Widget card(DVInstalledApp app) => DVBox.list(<Widget>[
        DVBox.row(<Widget>[
          DVText('×').modifier(mono(size: 22, color: LauncherColors.text).centered().minimumTapTarget(width: 44, height: 44).semanticLabel('Remove ${app.label} from recent apps').tooltip('Close ${app.label} (swipe up)').onTap(() => store.forgetRecentApp(app.packageName))),
          AppIcon(app: app, size: 28),
          DVBox(DVText(app.label).modifier(mono(size: 14, bold: true).maxLines(1).overflow(TextOverflow.ellipsis)), DVModifier().fill()),
        ], spacing: 8, crossAlign: DVCrossAlign.center),
        DVBox(
          DVBox(AppIcon(app: app, size: watch ? 48 : 88), DVModifier().centered()),
          DVModifier().fill().backgroundColor(cardColour(app.packageName)).rounded(20).semanticLabel('Open ${app.label}').tooltip('Open ${app.label}').onTap(() => open(app.packageName)).onSwipeUp(() => store.forgetRecentApp(app.packageName)),
        ),
      ], spacing: 8, modifier: DVModifier().width(cardWidth).height(cardHeight));

  final Widget clearAll = DVBox(
    DVText('Clear all').modifier(mono(size: 14, bold: true, color: LauncherColors.page).backgroundColor(LauncherColors.text).rounded(24).paddingSymmetric(horizontal: 18, vertical: 12).minimumTapTarget(width: 48, height: 48).semanticLabel('Clear all recent apps').tooltip('Close every app in recent apps').onTap(store.clearRecents)),
    DVModifier().height(cardHeight).centered().paddingSymmetric(horizontal: 12),
  );

  final Widget header = DVBox.row(<Widget>[
    link('‹ home', 'Back to the home screen', close),
    DVBox(DVText('recent apps').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).maxLines(1).overflow(TextOverflow.ellipsis).semanticHeading(1)), DVModifier().fill()),
  ], spacing: 8, crossAlign: DVCrossAlign.center, modifier: DVModifier().paddingOnly(left: side, right: side, top: MediaQuery.paddingOf(context).top + (watch ? side * 0.4 : 4), bottom: 8));

  final Widget list = DVBox.list(<Widget>[
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (recent.isEmpty) DVText('No recent apps yet. Apps you open from Dev Launcher show here, newest first.').modifier(mono(size: 14, color: LauncherColors.muted)),
    if (recent.isNotEmpty)
      DVBox.horizontalScrollable(<Widget>[
        for (final DVInstalledApp app in recent) card(app),
        clearAll,
      ], spacing: 16),
    if (onSettings != null && !watch) link('Recents button settings', 'Make the phone\'s Recents button open this screen, and see what the phone reports', onSettings, color: LauncherColors.accent),
  ], spacing: 10, modifier: DVModifier().paddingOnly(left: side, right: side, top: 8, bottom: 32 + MediaQuery.paddingOf(context).bottom)).scrollable();

  // No swipe to close here: a sideways swipe scrolls the cards. Back, Home
  // and "‹ home" close it.
  return DVBox.list(<Widget>[header, DVBox(list, DVModifier().fill())], spacing: 0, modifier: DVModifier().backgroundColor(LauncherColors.page).height(size.height));
}

/// A card's colour, the same for an app every time: a muted shade picked by
/// its package name, so cards side by side are told apart at a glance.
Color cardColour(String package) {
  final int hash = package.codeUnits.fold(0, (int sum, int unit) => (sum * 31 + unit) & 0xFFFFFF);
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.32, 0.26).toColor();
}
