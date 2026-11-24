// An app's name sits right under its icon, centred on it, the same small gap
// on every tile: placed by the tile's own column (spacing and cross-axis
// centring), never by a margin nudge (owner rule, "align with layout").
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  for (final Size screen in <Size>[const Size(320, 568), const Size(360, 800), const Size(412, 915)]) {
    testWidgets('${screen.width.toInt()}x${screen.height.toInt()}: every label is centred under its icon with the same small gap', (WidgetTester tester) async {
      tester.view.physicalSize = screen * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(createDartvelApp());
        for (int frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
      for (int frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final List<double> gaps = <double>[];
      for (final Element tile in find.byType(AppTile).evaluate()) {
        final AppTile widget = tile.widget as AppTile;
        if (!widget.showLabel) continue;
        final Finder inTile = find.descendant(of: find.byElementPredicate((Element each) => each == tile), matching: find.byType(AppIcon));
        final Finder label = find.descendant(of: find.byElementPredicate((Element each) => each == tile), matching: find.text(widget.app.label));
        if (inTile.evaluate().isEmpty || label.evaluate().isEmpty) continue;
        final Rect icon = tester.getRect(inTile.first);
        final Rect text = tester.getRect(label.first);
        if (icon.top > screen.height || icon.bottom < 0) continue;
        gaps.add(text.top - icon.bottom);
        expect(text.center.dx, moreOrLessEquals(icon.center.dx, epsilon: 1), reason: '${widget.app.label}: label centred under its icon');
      }
      expect(gaps, isNotEmpty);
      for (final double gap in gaps) {
        expect(gap, inInclusiveRange(2, 6), reason: 'gap between icon and label');
      }
      expect(gaps.toSet().length, 1, reason: 'the same gap on every tile: $gaps');
      expect(isDevTool('com.termux'), isTrue);
    });
  }

  testWidgets('the prompt sign sits on the same line as the command field, centred on it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      for (int frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    final Rect sign = tester.getRect(find.text('\u276F'));
    final Rect field = tester.getRect(find.byType(EditableText).first);
    expect(sign.center.dy, moreOrLessEquals(field.center.dy, epsilon: 2), reason: 'sign $sign, field $field');
    expect(find.bySemanticsLabel(RegExp('^Command')), findsWidgets, reason: 'the field still has a name for a screen reader');
  });
}
