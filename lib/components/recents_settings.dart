// Recents button settings and diagnostics. Two things live here:
//
// 1. The opt-in Recents service. Android gives the Recents button to the
//    phone's own Recents, never to a home app the person installed. An
//    accessibility service, turned on once by the person in Settings, can
//    notice the button and show Dev Launcher's Recents instead.
// 2. What the phone reports, live: every signal Dev Launcher received, and
//    when, so a press of Recents on this phone shows exactly what arrives.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import '../services/signal_log.dart';
import 'theme.dart';

@DVFunctionalWidget()
Widget _recentsSettings(BuildContext context, {VoidCallback? onClose}) {
  void close() => onClose != null ? onClose() : DV.Navigation.back();
  final SignalLog log = SignalLog.instance;
  final DVSignal<List<DVHomeAppSignal>> signals = context.signal(log.signals);
  final DVSignal<bool?> serviceOn = context.signal<bool?>(null);
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> started = context.signal(false);

  Future<void> readService() async {
    try {
      serviceOn.value = await DV.Platform.apps.isRecentsServiceOn;
    } on Object {
      serviceOn.value = false;
    }
  }

  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      log.start();
      late final StreamSubscription<List<DVHomeAppSignal>> following;
      following = log.changes.listen((List<DVHomeAppSignal> next) {
        if (!context.mounted) {
          following.cancel();
          return;
        }
        signals.value = next;
        // Back from Accessibility settings: the service may be on now.
        if (next.isNotEmpty && next.last.name == 'focus' && next.last.detail == 'gained') readService();
      });
      readService();
    });
  }

  final Size size = MediaQuery.sizeOf(context);
  final ScreenKind kind = screenKindFor(width: size.width, height: size.height);
  final double side = kind == ScreenKind.watch ? roundSafeInset(size.shortestSide) : (kind == ScreenKind.tv ? 56 : 20);
  final List<DVHomeAppSignal> heard = signals.value;
  // Times count from the first thing the phone said (what Dev Launcher notes
  // itself before then has no time of its own).
  final int first = heard.where((DVHomeAppSignal signal) => signal.at != 0).firstOrNull?.at ?? 0;
  bool arrived(String name, [String? detail]) => heard.any((DVHomeAppSignal signal) => signal.name == name && (detail == null || signal.detail == detail));

  Widget link(String label, String hint, VoidCallback onTap, {Color color = LauncherColors.text, bool filled = false}) => DVText(label).modifier(
        (filled ? mono(size: 14, bold: true, color: LauncherColors.page).backgroundColor(LauncherColors.accent).rounded(10).paddingSymmetric(horizontal: 16, vertical: 12) : mono(size: 14, color: color).paddingSymmetric(horizontal: 8, vertical: 10))
            .minimumTapTarget(width: 48, height: 48)
            .tooltip(hint)
            .onTap(onTap),
      );
  Widget heading(String text) => DVText('// $text').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(2));
  Widget say(String text, {Color color = LauncherColors.text}) => DVText(text).modifier(mono(size: 13, color: color));
  Widget check(String label, bool yes) => say('${yes ? '✓' : '·'} $label: ${yes ? 'arrived' : 'not seen yet'}', color: yes ? LauncherColors.accent : LauncherColors.muted);

  final bool? on = serviceOn.value;
  final Widget service = DVBox.list(<Widget>[
    heading('recents button'),
    say('Android gives the Recents button to the phone\'s own Recents, not to a home app you install. Dev Launcher\'s Recents always opens from the dock button and a swipe left on the home screen.'),
    say('To make the phone\'s Recents button open it too, turn on "Dev Launcher Recents" under Accessibility. It only notices the Recents button and which window opens. It does not read your screen or what you type. You can turn it off there at any time.'),
    say(on == null ? 'Checking…' : (on ? 'The Recents service is ON.' : 'The Recents service is off.'), color: on == true ? LauncherColors.accent : LauncherColors.muted),
    link(on == true ? 'Open Accessibility settings' : 'Turn on in Accessibility settings', 'Open the phone\'s Accessibility settings, where the Recents service is turned on or off', () async {
      try {
        await DV.Platform.apps.openRecentsServiceSettings();
        status.value = '';
      } on Object {
        status.value = 'This screen opens the phone\'s Accessibility settings on Android only.';
      }
    }, filled: on != true),
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(LauncherColors.surface).rounded(8).padding(10).semanticRole('status')),
  ], spacing: 10, crossAlign: DVCrossAlign.start);

  final Widget diagnostics = DVBox.list(<Widget>[
    heading('recents diagnostics'),
    say('Press the phone\'s Recents button (from here, from the home screen, from another app), then come back. Everything the phone told Dev Launcher is listed below, oldest first.'),
    check('Phone said "recentapps"', arrived('recents')),
    check('Recents service replaced the phone\'s Recents', arrived('recentsReplaced')),
    check('Recents service saw a window open', arrived('window')),
    check('Something covered Dev Launcher', arrived('focus', 'lost')),
    check('Dev Launcher paused', arrived('pause')),
    check('Leaving by a key or button', arrived('userLeaveHint')),
    check('Home pressed', arrived('home')),
    check('Back pressed', arrived('back')),
    check('Dev Launcher answered Back', arrived('backHandled')),
    DVBox.row(<Widget>[
      DVBox(say('${heard.length} signal${heard.length == 1 ? '' : 's'}', color: LauncherColors.muted), DVModifier().fill()),
      link('clear', 'Empty the list of signals', log.clear),
    ], spacing: 8, crossAlign: DVCrossAlign.center),
    for (final DVHomeAppSignal signal in heard)
      DVText('${sinceLabel(signal.at == 0 ? first : signal.at, first)}  ${describeSignal(signal.name, signal.detail)}').modifier(mono(size: 12).backgroundColor(LauncherColors.surface).rounded(6).paddingSymmetric(horizontal: 10, vertical: 6)),
  ], spacing: 8, crossAlign: DVCrossAlign.start);

  final Widget header = DVBox.row(<Widget>[
    link('‹ back', 'Back', close),
    DVBox(DVText('recents settings').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).maxLines(1).overflow(TextOverflow.ellipsis).semanticHeading(1)), DVModifier().fill()),
  ], spacing: 8, crossAlign: DVCrossAlign.center, modifier: DVModifier().paddingOnly(left: side, right: side, top: MediaQuery.paddingOf(context).top + 4, bottom: 8));

  final Widget body = DVBox.list(<Widget>[service, diagnostics], spacing: 24, modifier: DVModifier().paddingOnly(left: side, right: side, top: 8, bottom: 32 + MediaQuery.paddingOf(context).bottom).maxWidth(760)).scrollable();
  return DVBox.list(<Widget>[header, DVBox(body, DVModifier().fill())], spacing: 0, modifier: DVModifier().backgroundColor(LauncherColors.page).height(size.height));
}
