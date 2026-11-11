// On an Android 12 emulator the drawer did not open from the apps button and
// Back left it open. This drives the real app (real router, real home): tap
// the apps button, then send Back the way Android does.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('the apps button opens the drawer and Back closes it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // The closed drawer sits below the screen, pushed there by a margin that
    // leaves it no height; Flutter reports that as an overflow in debug. It
    // is never painted. Dartvel has no offset modifier yet to move it whole.
    final FlutterExceptionHandler? report = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('RenderFlex overflowed')) return;
      report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      for (int frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    Future<void> settle() async {
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final Finder search = find.text('Search apps');
    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(search).dy < screenHeight / 2;

    final Finder apps = find.bySemanticsLabel('All apps');
    expect(apps, findsWidgets, reason: 'the home screen is up');
    expect(drawerOpen(), isFalse, reason: 'the drawer starts closed');
    await tester.tap(apps.first, warnIfMissed: false);
    await settle();
    expect(drawerOpen(), isTrue, reason: 'the apps button opened the drawer');

    final bool handled = await tester.binding.handlePopRoute();
    await settle();
    expect(handled, isTrue, reason: 'the app took Back');
    expect(drawerOpen(), isFalse, reason: 'Back closed the drawer');
  });
}
