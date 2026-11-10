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

/// Text in the launcher's face: [size] points, bold or not, in [color].
DVModifier mono({double size = 14, bool bold = false, Color color = LauncherColors.text}) =>
    DVModifier().fontFamily(launcherFont).fontSize(size).fontWeight(bold ? FontWeight.w700 : FontWeight.w400).color(color).letterSpacing(-0.2);
