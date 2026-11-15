// Dev Launcher's own Recents: the apps opened last, newest first, as cards.
// Tap a card to open the app; its remove control takes it off the list. A
// home app cannot be the phone's Recents (only the system's or the phone
// maker's launcher can), so this is the Recents that always works: from the
// dock's Recents button, a swipe left on the home screen, and the phone's
// Recents button wherever the phone lets Dev Launcher hear it.
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

  Widget card(DVInstalledApp app) => DVBox.row(<Widget>[
        DVBox(
          DVBox.row(<Widget>[
            AppIcon(app: app, size: watch ? 32 : 44),
            DVBox(
              DVBox.list(<Widget>[
                DVText(app.label).modifier(mono(size: 16, bold: true).maxLines(1).overflow(TextOverflow.ellipsis)),
                if (!watch) DVText(app.packageName).modifier(mono(size: 11, color: LauncherColors.muted).maxLines(1).overflow(TextOverflow.ellipsis)),
              ], spacing: 2),
              DVModifier().fill(),
            ),
          ], spacing: 12, crossAlign: DVCrossAlign.center),
          DVModifier().fill().padding(12).tooltip('Open ${app.label}').onTap(() => open(app.packageName)),
        ),
        DVBox(
          DVText('✕').modifier(mono(size: 16, color: LauncherColors.muted).align(Alignment.center)),
          DVModifier().minimumTapTarget(width: 48, height: 48).centered().tooltip('Remove ${app.label} from recent apps').semanticLabel('Remove ${app.label} from recent apps').onTap(() => store.forgetRecentApp(app.packageName)),
        ),
      ], spacing: 4, crossAlign: DVCrossAlign.center, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: LauncherColors.rule)).rounded(16).maxWidth(720));

  final Widget header = DVBox.row(<Widget>[
    link('‹ home', 'Back to the home screen', close),
    DVBox(DVText('recent apps').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).maxLines(1).overflow(TextOverflow.ellipsis).semanticHeading(1)), DVModifier().fill()),
    if (recent.isNotEmpty) link('clear all', 'Remove every app from recent apps', store.clearRecents),
  ], spacing: 8, crossAlign: DVCrossAlign.center, modifier: DVModifier().paddingOnly(left: side, right: side, top: MediaQuery.paddingOf(context).top + (watch ? side * 0.4 : 4), bottom: 8));

  final Widget list = DVBox.list(<Widget>[
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),
    if (recent.isEmpty) DVText('No recent apps yet. Apps you open from Dev Launcher show here, newest first.').modifier(mono(size: 14, color: LauncherColors.muted)),
    for (final DVInstalledApp app in recent) card(app),
    if (onSettings != null && !watch) link('Recents button settings', 'Make the phone\'s Recents button open this screen, and see what the phone reports', onSettings, color: LauncherColors.accent),
  ], spacing: 10, modifier: DVModifier().paddingOnly(left: side, right: side, top: 8, bottom: 32 + MediaQuery.paddingOf(context).bottom)).scrollable();

  return DVBox.list(<Widget>[header, DVBox(list, DVModifier().fill())], spacing: 0, modifier: DVModifier().backgroundColor(LauncherColors.page).height(size.height).onSwipeRight(close));
}
