import 'package:flutter/widgets.dart';

import '../components/app_drawer.dart';
import '../dartvel_client/dartvel_client.dart';

/// Every app, A to Z.
@DVPage(
  title: 'All apps',
  description: 'Every app on the phone, A to Z, with search and a letter index.',
)
Widget _appsPage(BuildContext context) => const AppDrawer();
