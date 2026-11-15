import 'package:flutter/widgets.dart';

import '../components/recents_settings.dart';
import '../dartvel_client/dartvel_client.dart';

/// The Recents button: the opt-in service, and what the phone reports.
@DVPage(
  // A home screen is not a document: a long press is "more about this app".
  selectable: false,
  // A home screen is not a document: a long press is "more about this app".
  title: 'Recents settings',
  description: 'Make the phone\'s Recents button open Dev Launcher\'s recent apps, and see live what the phone reports when Recents is pressed.',
)
Widget _recentsSettingsPage(BuildContext context) => const RecentsSettings();
