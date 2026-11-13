// A drawer dragged open whose gesture never ends (the system's own gesture
// area at the bottom of the screen can swallow the finger's release, as
// HiOS's gesture navigation does) was open on screen with nothing claiming
// Back: only a settled drawer did. Back must close a drawer that is showing,
// however it got there.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  testWidgets('Back closes a drawer dragged open whose release never arrived', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
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

    final double screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    bool drawerOpen() => tester.getTopLeft(find.text('Search apps')).dy < screenHeight / 2;

    // Drag the handle above the dock most of the way up, and keep the finger
    // down: no release, so the drawer never settles.
    final Offset handle = tester.getCenter(find.byTooltip('Drag up, or tap, for all apps').first);
    final TestGesture finger = await tester.startGesture(handle);
    for (int step = 0; step < 12; step++) {
      await finger.moveBy(Offset(0, -screenHeight * 0.06));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle();
    expect(drawerOpen(), isTrue, reason: 'the drawer followed the finger up');

    final bool handled = await tester.binding.handlePopRoute();
    await settle();
    expect(handled, isTrue, reason: 'the app took Back');
    expect(drawerOpen(), isFalse, reason: 'Back closed the drawer');
    await finger.cancel();
    await settle();
  });
}
