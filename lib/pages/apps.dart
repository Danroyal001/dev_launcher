import 'package:flutter/widgets.dart';

import '../components/app_drawer.dart';
import '../dartvel_client/dartvel_client.dart';

/// Every app, A to Z.
@DVPage(
  // A home screen is not a document: a long press is "more about this app".
  selectable: false,
  // A home screen is not a document: a long press is "more about this app".
  title: 'All apps',
  description: 'Every app on the phone, A to Z, with search and a letter index.',
)
Widget _appsPage(BuildContext context) => const AppDrawer();
