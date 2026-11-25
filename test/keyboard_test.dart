// Owner, 25 Nov (Tecno, 0.1.14): "search is messed up on the app drawer,
// launching the on-screen keyboard ruins everything".
//
// The keyboard comes up the way Android brings it: over about a quarter of a
// second, a little more of it each frame, reported as a bottom view inset
// measured from the bottom of the screen, with the navigation bar's padding
// going to nothing once the keyboard covers it. On every one of those frames,
// and once it has settled:
// - the drawer's header and search field stay where they were, the field
//   keeps the focus;
// - the list of apps ends at the top of the keyboard (never under it), keeps
//   room for results and still scrolls;
// - the home screen and dock behind the drawer do not move;
// - the letter index never squashes (it steps aside while the keyboard is up,
//   as on Pixel and Lawnchair);
// - the drawer always reaches the bottom of the screen (0.1.14 animated its
//   height after the keyboard, so the dock showed under it).
// Typing filters at once; Back puts the keyboard away first, then closes the
// drawer; with the keyboard gone everything is back where it was.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

const int _keyboardFrames = 12;

/// The same rectangle, to a hundredth of a dp (layout at a device pixel ratio
/// of 2 leaves fractions that print alike and compare unequal).
void expectSameRect(Rect actual, Rect expected, String reason) {
  for (final (double, double) edge in <(double, double)>[(actual.left, expected.left), (actual.top, expected.top), (actual.right, expected.right), (actual.bottom, expected.bottom)]) {
    expect(edge.$1, moreOrLessEquals(edge.$2, epsilon: 0.01), reason: '$reason: $actual, expected $expected');
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// One phone: its size, status bar, navigation bar and keyboard, in dp.
class _Phone {
  const _Phone(this.size, this.statusBar, this.navBar, this.keyboard);
  final Size size;
  final double statusBar;
  final double navBar;
  final double keyboard;
  String get name => '${size.width.toInt()}x${size.height.toInt()} (bars ${statusBar.toInt()}/${navBar.toInt()}, keyboard ${keyboard.toInt()})';
}

const List<_Phone> _phones = <_Phone>[
  _Phone(Size(360, 800), 35, 48, 300),
  _Phone(Size(360, 800), 24, 48, 280),
  _Phone(Size(412, 915), 40, 48, 320),
  _Phone(Size(412, 915), 32, 48, 300),
];

Future<void> _startOn(WidgetTester tester, _Phone phone) async {
  tester.view.physicalSize = phone.size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: phone.statusBar * 2, bottom: phone.navBar * 2);
  tester.view.viewPadding = FakeViewPadding(top: phone.statusBar * 2, bottom: phone.navBar * 2);
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}

/// The keyboard [shown] dp tall, as Android reports it: the inset from the
/// bottom of the screen, and the navigation bar's padding what the keyboard
/// leaves of it.
void _keyboardAt(WidgetTester tester, _Phone phone, double shown) {
  tester.view.viewInsets = FakeViewPadding(bottom: shown * 2);
  tester.view.padding = FakeViewPadding(top: phone.statusBar * 2, bottom: (phone.navBar - shown).clamp(0.0, phone.navBar) * 2);
}

void main() {
  for (final _Phone phone in _phones) {
    testWidgets('${phone.name}: the drawer search with the keyboard up', (WidgetTester tester) async {
      await _startOn(tester, phone);
      final Finder dockButton = find.bySemanticsLabel('All apps');
      final Rect dockBefore = tester.getRect(dockButton.first);
      await tester.tap(dockButton.first, warnIfMissed: false);
      await _settle(tester);

      final Finder drawer = find.byType(AppDrawer);
      final Finder field = find.descendant(of: drawer, matching: find.byType(EditableText));
      // The drawer's list: its vertical scrollable (the field has a sideways one).
      final Finder lists = find.descendant(of: drawer, matching: find.byWidgetPredicate((Widget widget) => widget is Scrollable && axisDirectionToAxis(widget.axisDirection) == Axis.vertical));
      final Finder indexCells = find.bySemanticsLabel(RegExp(r'^Jump to [A-Z#]'));
      expect(field, findsOneWidget);
      expect(indexCells, findsWidgets, reason: 'the letter index is there before the keyboard');
      final Rect fieldBefore = tester.getRect(field);
      final Rect listBefore = tester.getRect(lists.first);
      final Rect drawerBefore = tester.getRect(drawer);
      final double indexCellBefore = tester.getRect(indexCells.first).height;
      final double screenBottom = phone.size.height;
      // The list keeps its own bottom margin (12 dp) to whatever it ends on:
      // the navigation bar before the keyboard, the keyboard while it is up.
      final double listMargin = (screenBottom - phone.navBar) - listBefore.bottom;
      expect(listMargin, inInclusiveRange(0, 16), reason: 'the list reaches down to the navigation bar: $listBefore');

      void checkFrame(String when, double shown) {
        expect(tester.takeException(), isNull, reason: '$when: nothing overflows');
        final double keyboardTop = screenBottom - shown;
        final Rect fieldNow = tester.getRect(field);
        expect(fieldNow.top, moreOrLessEquals(fieldBefore.top, epsilon: 0.5), reason: '$when: the field does not jump (was $fieldBefore, now $fieldNow)');
        expect(fieldNow.bottom, lessThanOrEqualTo(keyboardTop), reason: '$when: the field is above the keyboard');
        final Rect listNow = tester.getRect(lists.first);
        expect(listNow.top, moreOrLessEquals(listBefore.top, epsilon: 0.5), reason: '$when: the list starts where it did');
        expect(listNow.bottom, lessThanOrEqualTo(math.min(keyboardTop, screenBottom - phone.navBar) - listMargin + 0.5), reason: '$when: the list ends at or above the keyboard top $keyboardTop: $listNow');
        final Rect drawerNow = tester.getRect(drawer);
        expect(drawerNow.top, moreOrLessEquals(drawerBefore.top, epsilon: 0.5), reason: '$when: the drawer stays open where it was');
        expect(drawerNow.bottom, greaterThanOrEqualTo(drawerBefore.bottom - 0.5), reason: '$when: the drawer reaches the bottom of the screen, nothing of the home screen shows under it: $drawerNow');
        expectSameRect(tester.getRect(dockButton.first), dockBefore, '$when: the dock behind the drawer does not move');
        for (final Element cell in indexCells.evaluate()) {
          expect(tester.getRect(find.byElementPredicate((Element element) => element == cell)).height, moreOrLessEquals(indexCellBefore, epsilon: 0.5), reason: '$when: the letter index never squashes');
        }
      }

      // The field is tapped and the keyboard slides up.
      await tester.tap(field);
      await tester.pump();
      for (int frame = 1; frame <= _keyboardFrames; frame++) {
        final double shown = phone.keyboard * frame / _keyboardFrames;
        _keyboardAt(tester, phone, shown);
        await tester.pump(const Duration(milliseconds: 20));
        checkFrame('keyboard coming up, frame $frame', shown);
      }
      await _settle(tester);
      checkFrame('keyboard up', phone.keyboard);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue, reason: 'the field keeps the focus');
      final double keyboardTop = screenBottom - phone.keyboard;
      final Rect viewport = tester.getRect(lists.first);
      expect(viewport.bottom, moreOrLessEquals(keyboardTop - listMargin, epsilon: 0.5), reason: 'the list uses the room down to the keyboard: $viewport');
      expect(viewport.height, greaterThan(150), reason: 'the list keeps room to show results: $viewport');
      expect(indexCells, findsNothing, reason: 'the letter index steps aside while the keyboard is up');

      // Typing filters at once.
      tester.testTextInput.enterText('cal');
      await tester.pump();
      checkFrame('typed', phone.keyboard);
      expect(find.descendant(of: drawer, matching: find.text('Calendar')), findsWidgets);
      expect(find.descendant(of: drawer, matching: find.text('Gmail')), findsNothing, reason: 'the list filters as the letters come');
      final Rect match = tester.getRect(find.descendant(of: drawer, matching: find.text('Calendar')).last);
      expect(match.top, greaterThanOrEqualTo(tester.getRect(field).bottom), reason: 'results sit under the field');
      expect(match.bottom, lessThanOrEqualTo(keyboardTop), reason: 'the first result is above the keyboard: $match');
      tester.testTextInput.enterText('');
      await tester.pump();

      // Still scrolls with the keyboard up: a drag moves the list.
      final ScrollableState scrollable = tester.state<ScrollableState>(lists.first);
      expect(scrollable.position.maxScrollExtent, greaterThan(0), reason: 'the full list is longer than the room above the keyboard');
      await tester.drag(lists.first, const Offset(0, -200));
      await _settle(tester);
      expect(scrollable.position.pixels, greaterThan(0), reason: 'the list scrolls with the keyboard up');
      checkFrame('scrolled', phone.keyboard);
      scrollable.position.jumpTo(0);
      await tester.pump();

      // Back: the keyboard goes first, the drawer stays.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse, reason: 'Back put the keyboard away');
      for (int frame = _keyboardFrames - 1; frame >= 0; frame--) {
        final double shown = phone.keyboard * frame / _keyboardFrames;
        _keyboardAt(tester, phone, shown);
        await tester.pump(const Duration(milliseconds: 20));
        checkFrame('keyboard going down, frame $frame', shown);
      }
      await _settle(tester);
      // Everything back where it was.
      expectSameRect(tester.getRect(field), fieldBefore, 'the field is back where it was');
      expectSameRect(tester.getRect(lists.first), listBefore, 'the list has its full height back');
      expectSameRect(tester.getRect(drawer), drawerBefore, 'the drawer did not close or move');
      expect(indexCells, findsWidgets, reason: 'the letter index is back');
      expect(tester.getRect(indexCells.first).height, moreOrLessEquals(indexCellBefore, epsilon: 0.5));
      expectSameRect(tester.getRect(dockButton.first), dockBefore, 'the dock is where it was');

      // Back again closes the drawer.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await _settle(tester);
      // Closed, the drawer waits just below the page, whose bottom edge is the
      // top of the navigation bar.
      expect(tester.getRect(drawer).top, greaterThanOrEqualTo(screenBottom - phone.navBar - 1), reason: 'the drawer closed');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing the drawer with the keyboard up puts the keyboard away', (WidgetTester tester) async {
    const _Phone phone = _Phone(Size(360, 800), 35, 48, 300);
    await _startOn(tester, phone);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);
    final Finder field = find.descendant(of: find.byType(AppDrawer), matching: find.byType(EditableText));
    await tester.tap(field);
    _keyboardAt(tester, phone, phone.keyboard);
    await _settle(tester);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await tester.tap(find.text('‹ home'));
    await _settle(tester);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse, reason: 'the keyboard does not stay up over the home screen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home command line with the keyboard up: the dock stays put, the prompt stays in sight', (WidgetTester tester) async {
    const _Phone phone = _Phone(Size(360, 800), 35, 48, 300);
    await _startOn(tester, phone);
    final Finder dockButton = find.bySemanticsLabel('All apps');
    final Rect dockBefore = tester.getRect(dockButton.first);
    final Finder prompt = find.descendant(of: find.byType(LauncherHome), matching: find.byType(EditableText)).first;
    final Rect promptBefore = tester.getRect(prompt);
    await tester.tap(prompt);
    for (int frame = 1; frame <= _keyboardFrames; frame++) {
      final double shown = phone.keyboard * frame / _keyboardFrames;
      _keyboardAt(tester, phone, shown);
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
      expectSameRect(tester.getRect(dockButton.first), dockBefore, 'frame $frame: the dock does not jump over the keyboard');
      expect(tester.getRect(prompt).top, moreOrLessEquals(promptBefore.top, epsilon: 0.5), reason: 'frame $frame: the prompt does not move');
    }
    await _settle(tester);
    expect(tester.getRect(prompt).bottom, lessThanOrEqualTo(phone.size.height - phone.keyboard), reason: 'the prompt is above the keyboard');
    expect(tester.takeException(), isNull);
  });
}
