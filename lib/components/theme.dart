// Dev Launcher's look: a dark editor palette, JetBrains Mono, one green accent.
import 'package:flutter/painting.dart';

import '../dartvel_client/dartvel_client.dart';

abstract final class LauncherColors {
  static const Color page = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF151B23);
  static const Color rule = Color(0xFF2A313C);
  static const Color text = Color(0xFFE6EDF3);
  static const Color muted = Color(0xFF8B949E);
  static const Color accent = Color(0xFF3FB950);
  static const Color danger = Color(0xFFF85149);
}

const String launcherFont = 'JetBrainsMono';

/// How much larger text is on this screen: 1.5 on a TV read from across a
/// room. Set by each screen as it lays out.
double launcherTextScale = 1;

/// Text in the launcher's face: [size] points, bold or not, in [color].
DVModifier mono({double size = 14, bool bold = false, Color color = LauncherColors.text}) =>
    DVModifier().fontFamily(launcherFont).fontSize(size * launcherTextScale).fontWeight(bold ? FontWeight.w700 : FontWeight.w400).color(color).letterSpacing(-0.2);

/// Over the phone's wallpaper: dark enough at the top for the clock and at
/// the bottom for the dock, light in the middle so the wallpaper shows.
const LinearGradient wallpaperScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0x99000000), Color(0x33000000), Color(0x33000000), Color(0xB3000000)],
  stops: <double>[0, 0.3, 0.7, 1],
);
