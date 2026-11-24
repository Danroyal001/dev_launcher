// Every test file starts from an empty phone: the launcher's layout, recents and
// app list go to memory, never to the real device directory, where one run
// would leave pins (a folder, a hidden app) that the next run starts from.
import 'dart:async';

import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
  await testMain();
}
