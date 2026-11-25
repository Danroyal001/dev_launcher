// Light and dark, as on Pixel Launcher and Lawnchair: the drawer, menus and
// settings follow the phone's dark theme (or the person's choice), while what
// sits on the wallpaper (clock, home and dock labels) stays light over its scrim.
import 'package:dev_launcher/components/theme.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _startApp(WidgetTester tester, {required Brightness brightness}) async {
  tester.view.physicalSize = const Size(412, 915) * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.runAsync(() async {
    await tester.pumpWidget(createDartvelApp());
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Color _colorOf(WidgetTester tester, Finder text) {
  final Text widget = tester.widget<Text>(text);
  return widget.style?.color ?? const Color(0xFF000000);
}

/// The background colour painted nearest behind [finder].
Color? _backgroundBehind(WidgetTester tester, Finder finder) {
  Color? found;
  tester.element(finder).visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      final Color? color = (widget.decoration as BoxDecoration).color;
      if (color != null && color.a > 0.9) {
        found = color;
        return false;
      }
    }
    return true;
  });
  return found;
}

void main() {
  group('the theme setting', () {
    test('follows the device by default, and an older layout reads as following it', () {
      expect(const LauncherOptions().theme, LauncherTheme.device);
      expect(LauncherOptions.fromJson(<String, Object?>{'badges': true}).theme, LauncherTheme.device);
    });

    test('is kept across a save and a read', () {
      for (final LauncherTheme theme in LauncherTheme.values) {
        final LauncherLayout layout = LauncherLayout(options: const LauncherOptions().copyWith(theme: theme));
        expect(LauncherLayout.decode(layout.encode()).options.theme, theme);
      }
    });

    test('light is chosen by the setting, or by the phone when following it', () {
      expect(launcherIsLight(LauncherTheme.device, Brightness.light), isTrue);
      expect(launcherIsLight(LauncherTheme.device, Brightness.dark), isFalse);
      expect(launcherIsLight(LauncherTheme.light, Brightness.dark), isTrue);
      expect(launcherIsLight(LauncherTheme.dark, Brightness.light), isFalse);
    });
  });

  testWidgets('a phone in light theme: a light drawer with dark text, the clock still light on the wallpaper', (WidgetTester tester) async {
    await _startApp(tester, brightness: Brightness.light);
    final Finder clock = find.textContaining(RegExp(r'^\d{1,2}:\d{2}'));
    expect(clock, findsWidgets);
    expect(_colorOf(tester, clock.first).computeLuminance(), greaterThan(0.6), reason: 'the clock sits on the wallpaper scrim');

    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);
    final Finder calendar = find.text('Calendar').last;
    expect(_colorOf(tester, calendar).computeLuminance(), lessThan(0.2), reason: 'dark text in a light drawer');
    final Color? behind = _backgroundBehind(tester, calendar);
    expect(behind, isNotNull);
    expect(behind!.computeLuminance(), greaterThan(0.7), reason: 'the drawer is light');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone in dark theme keeps the dark drawer', (WidgetTester tester) async {
    await _startApp(tester, brightness: Brightness.dark);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);
    final Finder calendar = find.text('Calendar').last;
    expect(_colorOf(tester, calendar).computeLuminance(), greaterThan(0.6));
    expect(_backgroundBehind(tester, calendar)!.computeLuminance(), lessThan(0.1));
  });

  testWidgets('the launcher settings offer the theme and it changes at once', (WidgetTester tester) async {
    await _startApp(tester, brightness: Brightness.dark);
    await tester.tap(find.bySemanticsLabel('All apps').first, warnIfMissed: false);
    await _settle(tester);
    await tester.tap(find.text('settings'));
    await _settle(tester);
    expect(find.text('launcher settings'), findsOneWidget);
    expect(find.text('theme'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Theme: light').first, warnIfMissed: false);
    await _settle(tester);
    final Finder title = find.text('theme');
    expect(_colorOf(tester, title).computeLuminance(), lessThan(0.2), reason: 'the settings turned light');
    expect(tester.takeException(), isNull);
  });
}
