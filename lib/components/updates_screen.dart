// Updates, in the launcher: which version this phone has, the newest release,
// and its downloads, the APK for this phone's processor first. A home app
// cannot install itself, so each download is handed on: opened in the
// browser where the phone can, shared (pick the browser, or send it), or
// copied. Opens from the drawer, from the home screen's note when a newer
// version is out, and at /updates; Back closes it.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/device_abi.dart';
import '../services/launcher_logic.dart';
import '../services/launcher_store.dart';
import '../services/updates.dart';
import 'theme.dart';

@DVFunctionalWidget()
Widget _updatesScreen(BuildContext context, {VoidCallback? onClose}) {
  followLauncherTheme(context, LauncherStore.instance.current.layout.options);
  void close() => onClose != null ? onClose() : DV.Navigation.back();
  final LauncherUpdates updates = LauncherUpdates.instance;
  final DVSignal<UpdateCheck> state = context.signal(updates.current);
  final DVSignal<String> status = context.signal('');
  final DVSignal<bool> started = context.signal(false);
  if (!started.read()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || started.read()) return;
      started.value = true;
      late final StreamSubscription<UpdateCheck> subscription;
      subscription = updates.changes.listen((UpdateCheck next) {
        if (!context.mounted) {
          subscription.cancel();
          return;
        }
        state.value = next;
      });
      // Every visit asks again: someone opening this wants today's answer.
      unawaited(updates.check());
    });
  }

  final Size size = MediaQuery.sizeOf(context);
  final ScreenKind kind = screenKindFor(width: size.width, height: size.height);
  final bool watch = kind == ScreenKind.watch;
  final double side = watch ? roundSafeInset(size.shortestSide) : (kind == ScreenKind.tv ? 56 : 20);
  final UpdateCheck check = state.value;
  final LauncherRelease? release = check.release;
  final String abi = deviceAbi();
  // Opening in the browser needs the framework's links.open binding (Dartvel
  // after 3.47.7); until the phone has it, share and copy do the job.
  final bool canOpen = kIsWeb || DVNativeBridge.isRegistered('links.open');

  Widget button(String label, String hint, VoidCallback onTap, {bool primary = false}) => DVText(label).modifier(
        mono(size: 14, bold: primary, color: primary ? LauncherColors.page : LauncherColors.text)
            .backgroundColor(primary ? LauncherColors.accent : const Color(0x00000000))
            .border(Border.all(color: primary ? LauncherColors.accent : LauncherColors.rule))
            .rounded(10)
            .paddingSymmetric(horizontal: 14, vertical: 10)
            .minimumTapTarget(width: 48, height: 48)
            .semanticLabel(hint)
            .tooltip(hint)
            .onTap(onTap),
      );

  Future<void> share(String url) async {
    try {
      await DV.Platform.share.shareText(url);
      status.value = '';
    } on Object {
      status.value = 'This device cannot share. The link: $url';
    }
  }

  Future<void> copy(String url) async {
    try {
      await DV.Platform.clipboard.copy(url);
      status.value = 'Link copied. Paste it in the browser to download.';
    } on Object {
      status.value = 'Could not copy. The link: $url';
    }
  }

  Widget download(ReleaseApk apk, {required bool forThisPhone}) => DVBox.list(<Widget>[
        DVText(forThisPhone ? 'For this phone' : abiName(apk.abi)).modifier(mono(size: 13, bold: true, color: forThisPhone ? LauncherColors.accent : LauncherColors.text).semanticHeading(3)),
        DVText('${apk.name} · ${sizeText(apk.bytes)}').modifier(mono(size: 13, color: LauncherColors.muted).maxLines(2).overflow(TextOverflow.ellipsis)),
        DVBox.wrapLine(<Widget>[
          if (canOpen) button('Download', 'Download ${apk.name} in the browser', () => DVLinkOpener.open(apk.url, newTab: true), primary: forThisPhone),
          button('Share link', 'Share the download link for ${apk.name}', () => share(apk.url), primary: forThisPhone && !canOpen),
          button('Copy link', 'Copy the download link for ${apk.name}', () => copy(apk.url)),
        ], spacing: 8),
      ], spacing: 6, crossAlign: DVCrossAlign.start, modifier: DVModifier().backgroundColor(LauncherColors.surface).border(Border.all(color: forThisPhone ? LauncherColors.accent : LauncherColors.rule)).rounded(14).padding(14).maxWidth(720));

  final ReleaseApk? mine = release == null ? null : apkForAbi(release, abi);
  final String published = release?.published == null ? '' : ' · ${dayLine(release!.published!.toLocal(), locale: 'en')}';

  final Widget header = DVBox.row(<Widget>[
    DVText('‹ home').modifier(mono(size: 14).paddingSymmetric(horizontal: 8, vertical: 10).minimumTapTarget(width: 48, height: 48).semanticLabel('Back to the home screen').tooltip('Back to the home screen').onTap(close)),
    DVBox(DVText('updates').modifier(mono(size: 14, color: LauncherColors.accent).paddingSymmetric(vertical: 10).maxLines(1).overflow(TextOverflow.ellipsis).semanticHeading(1)), DVModifier().fill()),
  ], spacing: 8, crossAlign: DVCrossAlign.start, modifier: DVModifier().paddingOnly(left: side, right: side, top: watch ? side * 0.4 : 4, bottom: 8));

  final Widget body = DVBox.list(<Widget>[
    DVText('This phone: Dev Launcher $launcherVersion${abi.isEmpty ? '' : ' ($abi)'}').modifier(mono(size: 14)),
    if (check.checking && release == null) DVText('Asking GitHub for the newest version…').modifier(mono(size: 14, color: LauncherColors.muted).semanticRole('status')),
    if (check.problem.isNotEmpty) DVText(check.problem).modifier(mono(size: 13).backgroundColor(LauncherColors.surface).rounded(8).padding(10).semanticRole('status')),
    if (release != null) ...<Widget>[
      DVText(updateHeadline(launcherVersion, release)).modifier(mono(size: 18, bold: true, color: isNewer(release) ? LauncherColors.accent : LauncherColors.text).semanticHeading(2).semanticRole('status')),
      DVText('Newest: ${release.version}$published').modifier(mono(size: 13, color: LauncherColors.muted)),
      if (mine != null) download(mine, forThisPhone: true),
      for (final ReleaseApk apk in release.apks)
        if (apk != mine) download(apk, forThisPhone: false),
      if (release.notes.isNotEmpty) ...<Widget>[
        DVText('what is new in ${release.version}').modifier(mono(size: 13, color: LauncherColors.accent).semanticHeading(2)),
        DVText(release.notes).modifier(mono(size: 13).maxWidth(720)),
      ],
    ],
    if (status.value.isNotEmpty) DVText(status.value).modifier(mono(size: 13).backgroundColor(LauncherColors.surface).rounded(8).padding(10).semanticRole('status')),
    DVBox.wrapLine(<Widget>[
      button(check.checking ? 'Checking…' : 'Check again', 'Check for updates again', () => unawaited(updates.check())),
      button('All releases', 'Share the link to every release', () => share(releasesPage)),
    ], spacing: 8),
  ], spacing: 14, crossAlign: DVCrossAlign.start, modifier: DVModifier().paddingOnly(left: side, right: side, top: 8, bottom: 24)).scrollable();

  return DVBox(
    DVBox.list(<Widget>[header, DVBox(body, DVModifier().fill())], spacing: 0, modifier: DVModifier().height(size.height)),
    DVModifier().backgroundColor(LauncherColors.page).minHeight(size.height),
  );
}
