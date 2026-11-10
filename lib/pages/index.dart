import 'package:flutter/widgets.dart';

import '../components/launcher_home.dart';
import '../dartvel_client/dartvel_client.dart';

/// The home screen.
@DVPage(
  title: 'Dev Launcher',
  description: 'The Android home screen for developers: type to open any app, run launcher commands, keep your dev tools one tap away.',
)
Widget _indexPage(BuildContext context) => const LauncherHome();
