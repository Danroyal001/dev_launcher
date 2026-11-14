import 'package:flutter/widgets.dart';

import '../components/recents_screen.dart';
import '../dartvel_client/dartvel_client.dart';

/// The apps opened last.
@DVPage(
  // A home screen is not a document: a long press is "more about this app".
  selectable: false,
  // A home screen is not a document: a long press is "more about this app".
  title: 'Recent apps',
  description: 'The apps opened last from Dev Launcher, newest first: open one, or take it off the list.',
)
Widget _recentsPage(BuildContext context) => const RecentsScreen();
