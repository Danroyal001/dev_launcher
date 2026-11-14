import 'package:flutter/widgets.dart';

import '../components/recents_screen.dart';
import '../dartvel_client/dartvel_client.dart';

/// The apps opened last.
@DVPage(
  title: 'Recent apps',
  description: 'The apps opened last from Dev Launcher, newest first: open one, or take it off the list.',
)
Widget _recentsPage(BuildContext context) => const RecentsScreen();
