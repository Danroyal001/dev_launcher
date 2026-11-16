// The drawer's letter index sits on the right edge, as on Pixel and iPhone
// launchers. A tap or a drag (scrub) along it brings that letter's apps to
// the top of the list, with a bubble naming the letter while the finger is
// down. It never filters: every app stays in the list. Letters with no apps
// are dimmed. The search field has a clear button that keeps the focus.
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:dev_launcher/services/launcher_store.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

const Size _phone = Size(360, 640);

Future<void> _openDrawer(WidgetTester tester, {Locale? locale}) async {
  if (locale != null) {
    tester.platformDispatcher.localeTestValue = locale;
    tester.platformDispatcher.localesTestValue = <Locale>[locale];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  tester.view.physicalSize = _phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // The sides are saved on the device, which other test files share and
    // change: each test starts from the defaults.
    await LauncherStore.instance.setIndexSide(IndexSide.device);
    await LauncherStore.instance.setRecentsSide(RecentsSide.device);
  });
  await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The index entry for [letter].
Finder _indexLetter(String letter) => find.bySemanticsLabel(RegExp('^Jump to $letter\\b'));

/// The section heading for [letter] in the list (the left one of the two
/// texts that read [letter]; the other is the index entry on the right).
double _headingTop(WidgetTester tester, String letter) {
  // In the drawer only (the home screen behind it shows icon letters too),
  // and the leftmost: the heading starts the section, the index is on the
  // right and an app without an icon shows its letter further in.
  final Finder inDrawer = find.descendant(of: find.byWidgetPredicate((Widget widget) => widget.runtimeType.toString() == 'AppDrawer'), matching: find.text(letter, skipOffstage: false), skipOffstage: false);
  Offset at(Element element) => tester.getTopLeft(find.byElementPredicate((Element other) => other == element, skipOffstage: false));
  final List<Element> texts = inDrawer.evaluate().where((Element element) => at(element).dx < _phone.width / 2).toList()..sort((Element a, Element b) => at(a).dx.compareTo(at(b).dx));
  expect(texts, isNotEmpty, reason: 'the list has a heading for $letter');
  return at(texts.first).dy;
}

double _searchBottom(WidgetTester tester) => tester.getBottomLeft(find.text('Search apps')).dy;

void main() {
  testWidgets('the index is on the right edge, every letter A-Z with # first', (WidgetTester tester) async {
    await _openDrawer(tester);
    for (final String letter in <String>['C', 'S', 'W']) {
      expect(_indexLetter(letter), findsOneWidget, reason: '$letter is in the index');
      expect(tester.getCenter(_indexLetter(letter)).dx, greaterThan(_phone.width - 40), reason: '$letter sits on the right edge');
    }
    expect(find.bySemanticsLabel(RegExp(r'^A, no apps')), findsOneWidget, reason: 'a letter with no apps is shown, dimmed, and says so');
    expect(find.bySemanticsLabel(RegExp(r'^#, no apps')), findsOneWidget);
    expect(tester.getCenter(find.bySemanticsLabel(RegExp(r'^#, no apps'))).dy, lessThan(tester.getCenter(_indexLetter('C')).dy), reason: '# comes first');
  });

  testWidgets('on a right-to-left phone (Arabic) the index is on the left edge', (WidgetTester tester) async {
    await _openDrawer(tester, locale: const Locale('ar'));
    expect(tester.getCenter(_indexLetter('C')).dx, lessThan(40), reason: 'C sits on the left edge');
  });

  testWidgets('tapping a letter scrolls its apps to the top and hides nothing', (WidgetTester tester) async {
    await _openDrawer(tester);
    // W starts below the screen at this size (a long list builds what is near
    // the screen, so W may not be built yet at all).
    final Iterable<Element> wBefore = find.text('W', skipOffstage: false).evaluate().where((Element element) => tester.getTopLeft(find.byElementPredicate((Element other) => other == element, skipOffstage: false)).dx < _phone.width / 2);
    expect(wBefore.isEmpty || tester.getTopLeft(find.byElementPredicate((Element other) => other == wBefore.first, skipOffstage: false)).dy > _phone.height, isTrue, reason: 'W starts below the screen');

    await tester.tap(_indexLetter('W'));
    await _settle(tester);

    // The letters next to W are still there: the list was scrolled, not cut
    // down to W (the far ones are built as they come near the screen).
    expect(find.text('Termux', skipOffstage: false), findsWidgets, reason: 'apps of other letters are still in the list');
    expect(find.text('Spotify', skipOffstage: false), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
    final double wTop = _headingTop(tester, 'W');
    expect(wTop, lessThan(_phone.height - 60), reason: 'W is on screen now');
    expect(wTop, greaterThanOrEqualTo(_searchBottom(tester)), reason: 'under the header, not behind it');

    // Back up to C: a second tap never turns into "show only this letter".
    await tester.tap(_indexLetter('C'));
    await _settle(tester);
    final double cTop = _headingTop(tester, 'C');
    expect(cTop, greaterThanOrEqualTo(_searchBottom(tester)));
    expect(cTop, lessThan(_searchBottom(tester) + 60), reason: 'C is at the top of the list');
    expect(find.text('Gmail', skipOffstage: false), findsWidgets, reason: 'the letters after C are still in the list');
    expect(find.text('Messages', skipOffstage: false), findsWidgets);
  });

  testWidgets('a dimmed letter goes to the next letter that has apps, and hides nothing', (WidgetTester tester) async {
    await _openDrawer(tester);
    // A has no apps: C, the next letter that has some, comes to the top.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^A, no apps')), warnIfMissed: false);
    await _settle(tester);
    final double cTop = _headingTop(tester, 'C');
    expect(cTop, greaterThanOrEqualTo(_searchBottom(tester)));
    expect(cTop, lessThan(_searchBottom(tester) + 60));
    expect(find.text('Gmail'), findsWidgets, reason: 'nothing hidden');
  });

  testWidgets('scrubbing the index follows the finger, with a bubble naming the letter', (WidgetTester tester) async {
    await _openDrawer(tester);
    // From W up to G: G has letters enough below it to reach the top.
    final Offset from = tester.getCenter(_indexLetter('W'));
    final Offset to = tester.getCenter(_indexLetter('G'));
    final TestGesture finger = await tester.startGesture(from);
    // In steps, as a finger moves.
    const int steps = 8;
    for (int step = 1; step <= steps; step++) {
      await finger.moveTo(Offset.lerp(from, to, step / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _settle(tester);

    expect(find.bySemanticsLabel(RegExp(r'^Showing G')), findsOneWidget, reason: 'the bubble names the letter under the finger');
    final double gTop = _headingTop(tester, 'G');
    expect(gTop, greaterThanOrEqualTo(_searchBottom(tester)));
    expect(gTop, lessThan(_searchBottom(tester) + 60), reason: 'G is at the top of the list while the finger is on it');

    await finger.up();
    await _settle(tester);
    expect(find.bySemanticsLabel(RegExp(r'^Showing ')), findsNothing, reason: 'the bubble goes when the finger lifts');
    expect(find.text('Gmail'), findsWidgets, reason: 'nothing was filtered');
    expect(find.text('Messages', skipOffstage: false), findsWidgets);
  });

  testWidgets('the search field clears with x and keeps the focus', (WidgetTester tester) async {
    await _openDrawer(tester);
    expect(find.bySemanticsLabel('Clear search'), findsNothing, reason: 'no x while the field is empty');

    // The drawer's field (the home screen has its own, the command line).
    final Finder searchField = find.descendant(of: find.ancestor(of: find.text('Search apps'), matching: find.byType(TextField)), matching: find.byType(EditableText));
    await tester.tap(searchField);
    await tester.enterText(searchField, 'sla');
    await _settle(tester);
    expect(find.text('Calendar'), findsNothing, reason: 'the search narrowed the list');
    expect(find.bySemanticsLabel('Clear search'), findsOneWidget);
    expect(tester.getCenter(find.bySemanticsLabel('Clear search')).dx, greaterThan(_phone.width / 2), reason: 'the x is at the end of the field');

    await tester.tap(find.bySemanticsLabel('Clear search'));
    await _settle(tester);
    final EditableText field = tester.widget<EditableText>(searchField);
    expect(field.controller.text, isEmpty, reason: 'x cleared the text');
    expect(field.focusNode.hasFocus, isTrue, reason: 'the focus stayed in the field, ready to type again');
    expect(find.text('Calendar'), findsWidgets, reason: 'every app is back');
    expect(find.bySemanticsLabel('Clear search'), findsNothing, reason: 'x goes with the text');
  });
}
