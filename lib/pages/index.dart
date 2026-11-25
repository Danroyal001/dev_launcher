import 'package:flutter/widgets.dart';

import '../components/launcher_home.dart';
import '../dartvel_client/dartvel_client.dart';

/// The home screen.
@DVPage(
  // A home screen is not a document: a long press is "more about this app".
  selectable: false,
  // The keyboard covers the page rather than shrinking it: the home screen,
  // dock and drawer stay put, and what must stay in sight ends at the
  // keyboard (see keyboardRoom in components/theme.dart).
  resizeToAvoidBottomInset: false,
  // A home screen is not a document: a long press is "more about this app".
  title: 'Dev Launcher',
  description: 'The Android home screen for developers: type to open any app, run launcher commands, keep your dev tools one tap away.',
)
Widget _indexPage(BuildContext context) => const LauncherHome();
