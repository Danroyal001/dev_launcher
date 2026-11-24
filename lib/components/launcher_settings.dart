// The launcher's own settings, in one screen as every launcher has it: the
// home app, the wallpaper, gestures, notification badges, what the search
// offers, hidden apps, the drawer's letter index, backup and restore of the
// layout, and the phone's own settings. Opened by a pinch on the home screen,
// a long press on the clock, "settings" in the drawer or the prompt.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import '../services/updates.dart' show launcherVersion;
import 'launcher_home.dart' show followStore;
import 'theme.dart';

@DVFunctionalWidget()
Widget _launcherSettings(BuildContext context, {required VoidCallback onClose, VoidCallback? onRecentsSettings, VoidCallback? onUpdates}) {
  final LauncherStore store = LauncherStore.instance;
  final DVSignal<LauncherSnapshot> snapshot = context.signal(store.current);
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> badgeAccess = context.signal(false);
  final DVSignal<bool> lockService = context.signal(false);
  final DVSignal<bool> started = context.signal(false);
  if (!started.read()) {
    started.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      followStore(context, snapshot);
      unawaited(DV.Platform.apps.isNotificationAccessOn.then((bool on) {
        if (context.mounted) badgeAccess.value = on;
      }));
      unawaited(DV.Platform.apps.isRecentsServiceOn.then((bool on) {
        if (context.mounted) lockService.value = on;
      }));
    });
  }
  final LauncherSnapshot current = snapshot.value;
  final LauncherOptions options = current.layout.options;

  Future<void> say(Future<String> Function() run) async => status.value = await run();
  Future<String> attempt(Future<void> Function() call) async {
    try {
      await call();
      return '';
    } on Object catch (error) {
      return '$error'.replaceFirst('Bad state: ', '').replaceFirst('Unsupported operation: ', '');
    }
  }

  Widget heading(String text) => DVText(text).modifier(mono(size: 13, bold: true, color: LauncherColors.accent).semanticHeading(2).paddingOnly(top: 8));
  Widget note(String text) => DVText(text).modifier(mono(size: 12, color: LauncherColors.muted));
  Widget button(String label, String hint, VoidCallback onTap) => DVText(label).modifier(
        mono(size: 14, color: LauncherColors.text).backgroundColor(const Color(0xFF1C2430)).border(Border.all(color: LauncherColors.rule)).rounded(10).paddingSymmetric(horizontal: 14, vertical: 12).minimumTapTarget(width: 48, height: 48).tooltip(hint).onTap(onTap),
      );
  Widget toggle(String label, bool on, String hint, LauncherOptions Function(bool next) change) => DVBox.row(<Widget>[
        DVBox(DVText(label).modifier(mono(size: 14)), DVModifier().fill()),
        DVText(on ? 'on' : 'off').modifier(mono(size: 13, bold: true, color: on ? LauncherColors.page : LauncherColors.text).backgroundColor(on ? LauncherColors.accent : const Color(0xFF1C2430)).rounded(12).paddingSymmetric(horizontal: 12, vertical: 6)),
      ], spacing: 12, crossAlign: DVCrossAlign.center, modifier: DVModifier().paddingSymmetric(vertical: 8).minimumTapTarget(width: 48, height: 48).semanticLabel('$label, ${on ? 'on' : 'off'}').tooltip(hint).onTap(() => say(() => store.setOptions(change(!on)))));

  final List<DVInstalledApp> hidden = current.appsFor(current.layout.hidden);
  final Widget body = DVBox.list(<Widget>[
    DVBox.row(<Widget>[
      DVText('‹ home').modifier(mono(size: 14).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).tooltip('Back to the home screen').onTap(onClose)),
      DVBox(DVText('launcher settings').modifier(mono(size: 16, bold: true, color: LauncherColors.accent).semanticHeading(1).maxLines(1).overflow(TextOverflow.ellipsis)), DVModifier().fill()),
    ], spacing: 8, crossAlign: DVCrossAlign.center),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(const Color(0xCC151B23)).rounded(8).padding(10).semanticRole('status')),

    heading('home app'),
    note(current.isDefault ? 'Dev Launcher is your home app.' : 'Dev Launcher is not your home app yet.'),
    if (!current.isDefault) button('make it my home app', 'Ask Android to make Dev Launcher the home app', () => say(store.askToBeDefault)),

    heading('wallpaper'),
    button('change wallpaper', 'Open the phone\'s wallpaper picker', () => say(() => attempt(DV.Platform.apps.pickWallpaper))),

    heading('gestures'),
    toggle('swipe down: notifications', options.swipeDownShade, 'A swipe down on the home screen pulls the notification shade down', (bool next) => options.copyWith(swipeDownShade: next)),
    toggle('double-tap the clock: lock', options.doubleTapLock, 'A double tap on the clock locks the screen', (bool next) => options.copyWith(doubleTapLock: next)),
    if (options.doubleTapLock && !lockService.value) ...<Widget>[
      note('Android lets a home app lock the screen only through an accessibility service you turn on: "Dev Launcher Recents" under Accessibility.'),
      button('open accessibility settings', 'Turn on Dev Launcher Recents, which can lock the screen', () => say(() => attempt(DV.Platform.apps.openRecentsServiceSettings))),
    ],
    toggle('pinch: these settings', options.pinchSettings, 'A pinch on the home screen opens these settings', (bool next) => options.copyWith(pinchSettings: next)),
    note('Swipe up or the dot grid opens all apps; swipe left opens Recents.'),

    heading('notification badges'),
    toggle('badges on app icons', options.badges, 'A count on each app that has notifications', (bool next) => options.copyWith(badges: next)),
    if (options.badges && !badgeAccess.value) ...<Widget>[
      note('Badges need notification access: Android shows the counts only to apps you allow. Dev Launcher reads how many, never what they say.'),
      button('give notification access', 'Open the page where you allow Dev Launcher badges', () => say(() => attempt(DV.Platform.apps.openNotificationAccessSettings))),
    ],

    heading('search'),
    toggle('search the web', options.searchWeb, 'Offer a web search under the apps that match', (bool next) => options.copyWith(searchWeb: next)),
    toggle('search contacts', options.searchContacts, 'Offer your contacts that match (asks for permission)', (bool next) => options.copyWith(searchContacts: next)),
    note('Settings pages (Wi-Fi, Bluetooth, battery...) are always offered.'),

    heading('hidden apps'),
    if (hidden.isEmpty) note('None. Long-press an app and choose hide to keep it out of all apps and the search.'),
    for (final DVInstalledApp app in hidden)
      DVBox.row(<Widget>[
        DVBox(DVText(app.label).modifier(mono(size: 14)), DVModifier().fill()),
        DVText('unhide').modifier(mono(size: 13, color: LauncherColors.accent).paddingSymmetric(horizontal: 10, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Show ${app.label} in the drawer again').tooltip('Show ${app.label} in the drawer again').onTap(() => say(() => store.hideApp(app.packageName, hidden: false)))),
      ], spacing: 8, crossAlign: DVCrossAlign.center),

    heading('letter index'),
    DVBox.wrapLine(<Widget>[
      for (final (IndexSide side, String name) in const <(IndexSide, String)>[(IndexSide.device, 'Follow device'), (IndexSide.left, 'Left'), (IndexSide.right, 'Right')])
        DVText(current.layout.indexSide == side ? '● $name' : '○ $name').modifier(mono(size: 14, color: current.layout.indexSide == side ? LauncherColors.accent : LauncherColors.text).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Letter index: $name${current.layout.indexSide == side ? ', selected' : ''}').tooltip('The letter index on the ${name.toLowerCase()} side').onTap(() => say(() => store.setIndexSide(side)))),
    ], spacing: 4),
    if (onRecentsSettings != null) button('recents button settings', 'Which side the Recents button takes, and the Recents service', onRecentsSettings),

    heading('backup'),
    note('Your home screen, dock, folders, hidden apps and these settings, as text: keep it anywhere, paste it back to restore.'),
    DVBox.wrapLine(<Widget>[
      button('copy layout', 'Copy the layout to the clipboard', () => say(() => attempt(() async {
            await DV.Platform.clipboard.copy(layoutBackup(current.layout));
            status.value = 'Layout copied. Paste it into a note to keep it.';
          }).then((String problem) => problem.isEmpty ? status.read() : problem))),
      button('restore from clipboard', 'Replace this layout with one copied earlier', () => say(() async {
            try {
              final LauncherLayout? layout = restoreLayout(await DV.Platform.clipboard.paste() ?? '');
              if (layout == null) return 'The clipboard holds no Dev Launcher layout. Copy one first.';
              final String problem = await store.restore(layout);
              return problem.isEmpty ? 'Layout restored.' : problem;
            } on Object catch (error) {
              return '$error'.replaceFirst('Bad state: ', '');
            }
          })),
    ], spacing: 8),

    heading('phone'),
    button('phone settings', 'Open the phone\'s own settings', () => say(() => attempt(DV.Platform.apps.openSystemSettings))),
    if (onUpdates != null) button('updates · $launcherVersion', 'Which version this phone has, and the newest one', onUpdates),
  ], spacing: 8, modifier: DVModifier().paddingOnly(left: 20, right: 20, top: 8, bottom: 24).maxWidth(720)).scrollable();

  final Size size = MediaQuery.sizeOf(context);
  return DVBox.list(<Widget>[DVBox(body, DVModifier().fill())], spacing: 0, modifier: DVModifier().backgroundColor(LauncherColors.page).height(size.height).semanticRole('dialog'));
}

