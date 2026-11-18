// The dock is one row: every item in it (the apps, the All apps button and
// the Recent apps button) sits on the same horizontal line, with the same
// visible size, on every phone. 18 Nov the round buttons sat 6 px higher
// than the app icons.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/launcher_store.dart';

Future<void> _startApp(WidgetTester tester, {required Size logical, required RecentsSide side}) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // The owner's dock (18 Nov): Phone, Camera, Chrome around the All apps
    // button, with the Recent apps button on the left (Tecno) or the right.
    await LauncherStore.instance.saveLayout(LauncherLayout(dock: const <String>['com.google.android.dialer', 'com.android.camera', 'com.android.chrome'], recentsSide: side));
  });
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The visible shape of each dock item, left to right: the round buttons
/// and each app's icon (not its tap area), measured on screen.
List<(String, Rect)> _dockItems(WidgetTester tester, Size screen) {
  final List<(String, Rect)> items = <(String, Rect)>[];
  // A round button is its painted circle: the nearest box drawn round its
  // glyph, not its tap area.
  for (final (String button, Type glyph) in <(String, Type)>[('All apps', AppsButtonIcon), ('Recent apps', RecentsButtonIcon)]) {
    for (final Element element in find.byType(glyph).evaluate()) {
      final Finder circle = find.ancestor(of: find.byElementPredicate((Element each) => each == element), matching: find.byType(DecoratedBox)).first;
      items.add((button, tester.getRect(circle)));
    }
  }
  for (final Element element in find.byType(AppIcon).evaluate()) {
    final AppIcon icon = element.widget as AppIcon;
    items.add((icon.app.label, tester.getRect(find.byElementPredicate((Element each) => each == element))));
  }
  // The dock is the bottom strip; the drawer and home grid sit above it or off screen.
  final List<(String, Rect)> dock = items.where(((String, Rect) item) => item.$2.top > screen.height - 140 && item.$2.bottom <= screen.height).toList()
    ..sort(((String, Rect) a, (String, Rect) b) => a.$2.left.compareTo(b.$2.left));
  return dock;
}

void main() {
  for (final RecentsSide side in <RecentsSide>[RecentsSide.left, RecentsSide.right])
  for (final Size screen in <Size>[const Size(320, 568), const Size(360, 800), const Size(412, 915)]) {
    testWidgets('${screen.width.toInt()}x${screen.height.toInt()}, Recents ${side.name}: every dock item shares one vertical centre and one size', (WidgetTester tester) async {
      await _startApp(tester, logical: screen, side: side);
      final List<(String, Rect)> dock = _dockItems(tester, screen);
      final String described = dock.map(((String, Rect) item) => '${item.$1} ${item.$2}').join('\n');

      expect(dock.map(((String, Rect) item) => item.$1), containsAll(<String>['All apps', 'Recent apps']), reason: described);
      expect(dock.length, equals(5), reason: 'both buttons and the dock apps:\n$described');

      final double centre = dock.first.$2.center.dy;
      final Size size = dock.first.$2.size;
      for (final (String label, Rect rect) in dock) {
        expect(rect.center.dy, moreOrLessEquals(centre, epsilon: 0.5), reason: '$label is off the dock line:\n$described');
        expect(rect.height, moreOrLessEquals(size.height, epsilon: 0.5), reason: '$label is a different height:\n$described');
        expect(rect.width, moreOrLessEquals(size.width, epsilon: 0.5), reason: '$label is a different width:\n$described');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
