// The Recents diagnostics screen: every signal the phone sent, in plain
// words and in order, so the owner's phone shows what its Recents button
// really does. Reached from Recents; Back returns to Recents.
import 'package:dev_launcher/services/launcher_logic.dart';
import 'package:dev_launcher/services/signal_log.dart';
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/dartvel_client/dartvel_client.dart';

void main() {
  test('each signal is said in plain words', () {
    expect(describeSignal('recents', ''), contains('Recents pressed'));
    expect(describeSignal('closeSystemDialogs', 'recentapps'), contains('recentapps'));
    expect(describeSignal('focus', 'lost'), 'Something covered Dev Launcher');
    expect(describeSignal('window', 'com.android.launcher3/com.android.quickstep.RecentsActivity'), contains('RecentsActivity'));
    expect(describeSignal('recentsReplaced', 'window'), contains('window'));
    expect(describeSignal('unknownThing', 'x'), 'unknownThing: x');
    expect(sinceLabel(1400, 1000), '+0.4 s');
  });

  test('the log keeps the newest signals and drops the oldest', () {
    List<DVHomeAppSignal> signals = const <DVHomeAppSignal>[];
    for (int index = 0; index < signalsKept + 5; index++) {
      signals = withSignal(signals, DVHomeAppSignal('pause', index));
    }
    expect(signals.length, signalsKept);
    expect(signals.first.at, 5);
    expect(signals.last.at, signalsKept + 4);
  });

  testWidgets('signals heard anywhere show on the diagnostics screen, reached from Recents', (WidgetTester tester) async {
    DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
    addTearDown(() => DVNativeBridge.unregister('apps.homePressedAt'));
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

    Future<void> phoneSays(String message) async {
      await tester.runAsync(() async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage(message), (ByteData? _) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }

    // Pressed on the home screen, before the diagnostics screen was ever opened.
    await phoneSays('closeSystemDialogs:1000:recentapps');
    await phoneSays('focus:1400:lost');
    await settle();

    await tester.tap(find.bySemanticsLabel('Recent apps').first, warnIfMissed: false);
    await settle();
    await tester.tap(find.text('Recents button settings'), warnIfMissed: false);
    await settle();
    // The service is asked over a platform channel: let the answer come.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle();
    expect(find.text('recents settings'), findsOneWidget);
    expect(find.textContaining('reason: recentapps'), findsOneWidget);
    expect(find.textContaining('+0.4 s'), findsOneWidget);
    expect(find.textContaining('Something covered Dev Launcher: arrived'), findsOneWidget);
    expect(find.textContaining('Recents service is off'), findsOneWidget, reason: 'nothing answers in a test: off, not a crash');

    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle();
    expect(find.text('recents settings'), findsNothing);
    expect(find.text('recent apps'), findsOneWidget, reason: 'Back returns to Recents');
  });
}
