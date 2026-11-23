import 'package:flutter/widgets.dart';

import '../components/updates_screen.dart';
import '../dartvel_client/dartvel_client.dart';

/// This phone's version, the newest release and its downloads.
@DVPage(
  // A home screen is not a document: a long press is "more about this app".
  selectable: false,
  title: 'Updates',
  description: 'Which Dev Launcher this phone has, the newest release, and the download for this phone.',
)
Widget _updatesPage(BuildContext context) => const UpdatesScreen();
