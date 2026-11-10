import 'package:flutter/material.dart';

import 'components/theme.dart';
import 'dartvel_client/dartvel_client.dart';

/// The launcher is dark on every phone: a home screen sits behind every other
/// app, and a white flash between them is the one thing it must not do.
@DVAppRoot()
Widget _launcherRoot(BuildContext context, DVAppParts parts) => MaterialApp.router(
      title: 'Dev Launcher',
      debugShowCheckedModeBanner: false,
      themeMode: .dark,
      darkTheme: launcherTheme(),
      theme: launcherTheme(),
      routerConfig: parts.router,
    );

/// Dartvel's default theme in the launcher's dark palette and face, so fields,
/// the cursor, selection and scrollbars match.
ThemeData launcherTheme() {
  final ThemeData base = dartvelDefaultTheme(.dark);
  return base.copyWith(
    scaffoldBackgroundColor: LauncherColors.page,
    colorScheme: base.colorScheme.copyWith(primary: LauncherColors.accent, surface: LauncherColors.surface, onSurface: LauncherColors.text),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: LauncherColors.accent, selectionColor: Color(0x553FB950)),
    textTheme: base.textTheme.apply(fontFamily: launcherFont, bodyColor: LauncherColors.text, displayColor: LauncherColors.text),
    inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, labelStyle: TextStyle(color: LauncherColors.muted), hintStyle: TextStyle(color: LauncherColors.muted)),
  );
}
