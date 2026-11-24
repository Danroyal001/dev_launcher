// Dev Launcher's look: an editor palette, JetBrains Mono, one green accent.
// The drawer, menus and settings are dark or light (the phone's dark theme, or
// the person's choice); what sits on the wallpaper keeps the dark palette, light
// text over the scrim, as on every launcher.
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';

/// Whether the drawer, menus and settings are drawn light. Set by each screen
/// as it builds, from the setting and the phone's theme.
bool launcherLightTheme = false;

/// Light for [theme], given the phone's [platform] brightness.
bool launcherIsLight(LauncherTheme theme, Brightness platform) => theme == LauncherTheme.light || (theme == LauncherTheme.device && platform == Brightness.light);

/// Sets [launcherLightTheme] for this build, and rebuilds [context] when the
/// phone switches between light and dark.
void followLauncherTheme(BuildContext context, LauncherOptions options) {
  launcherLightTheme = launcherIsLight(options.theme, MediaQuery.platformBrightnessOf(context));
}

/// The palette of the drawer, menus and settings, light or dark.
abstract final class LauncherColors {
  static Color get page => launcherLightTheme ? const Color(0xFFFFFFFF) : const Color(0xFF0B0F14);
  static Color get surface => launcherLightTheme ? const Color(0xFFF6F8FA) : const Color(0xFF151B23);
  static Color get control => launcherLightTheme ? const Color(0xFFEAEEF2) : const Color(0xFF1C2430);
  static Color get rule => launcherLightTheme ? const Color(0xFFD0D7DE) : const Color(0xFF2A313C);
  static Color get text => launcherLightTheme ? const Color(0xFF1F2328) : const Color(0xFFE6EDF3);
  static Color get muted => launcherLightTheme ? const Color(0xFF59636E) : const Color(0xFF8B949E);
  static Color get accent => launcherLightTheme ? const Color(0xFF1A7F37) : const Color(0xFF3FB950);
  static Color get danger => launcherLightTheme ? const Color(0xFFCF222E) : const Color(0xFFF85149);
}

/// What sits on the wallpaper (clock, prompt, home and dock): always light text
/// on the dark scrim, whatever the theme.
abstract final class WallpaperColors {
  static const Color page = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF151B23);
  static const Color panel = Color(0xCC151B23);
  static const Color rule = Color(0xFF2A313C);
  static const Color text = Color(0xFFE6EDF3);
  static const Color muted = Color(0xFF8B949E);
  static const Color accent = Color(0xFF3FB950);
}

const String launcherFont = 'JetBrainsMono';

/// How much larger text is on this screen: 1.5 on a TV read from across a
/// room. Set by each screen as it lays out.
double launcherTextScale = 1;

/// Text in the launcher's face: [size] points, bold or not, in [color] (the
/// theme's text colour when none is given).
DVModifier mono({double size = 14, bool bold = false, Color? color}) =>
    DVModifier().fontFamily(launcherFont).fontSize(size * launcherTextScale).fontWeight(bold ? FontWeight.w700 : FontWeight.w400).color(color ?? LauncherColors.text).letterSpacing(-0.2);

/// Over the phone's wallpaper: dark enough at the top for the clock and at
/// the bottom for the dock, light in the middle so the wallpaper shows.
const LinearGradient wallpaperScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0x99000000), Color(0x33000000), Color(0x33000000), Color(0xB3000000)],
  stops: <double>[0, 0.3, 0.7, 1],
);

/// [mono] for what sits on the wallpaper: light text over the scrim unless
/// [color] says otherwise.
DVModifier wallMono({double size = 14, bool bold = false, Color? color}) => mono(size: size, bold: bold, color: color ?? WallpaperColors.text);
