// What the phone told Dev Launcher lately: Home, Recents, pauses, focus
// changes, windows the Recents service saw. Kept from the moment the home
// screen starts, so a press made anywhere shows on the Recents diagnostics
// screen afterwards. Phones differ in what they send for the Recents button;
// this is how one phone shows what it really does.
import 'dart:async';

import '../dartvel_client/dartvel_client.dart';

/// How many signals are kept: enough for several presses, each of which
/// arrives as a handful of signals.
const int signalsKept = 60;

/// [signals] with [next] added at the end, the oldest dropped past [signalsKept].
List<DVHomeAppSignal> withSignal(List<DVHomeAppSignal> signals, DVHomeAppSignal next) {
  final List<DVHomeAppSignal> all = <DVHomeAppSignal>[...signals, next];
  return all.length > signalsKept ? all.sublist(all.length - signalsKept) : all;
}

class SignalLog {
  SignalLog();

  static final SignalLog instance = SignalLog();

  final StreamController<List<DVHomeAppSignal>> _changes = StreamController<List<DVHomeAppSignal>>.broadcast();
  List<DVHomeAppSignal> _signals = const <DVHomeAppSignal>[];
  StreamSubscription<DVHomeAppSignal>? _listening;

  List<DVHomeAppSignal> get signals => _signals;
  Stream<List<DVHomeAppSignal>> get changes => _changes.stream;

  /// Starts keeping signals; a second call changes nothing.
  void start() {
    _listening ??= DV.Platform.apps.homeAppSignals.listen(add);
  }

  void add(DVHomeAppSignal signal) {
    _signals = withSignal(_signals, signal);
    _changes.add(_signals);
  }

  /// Something Dev Launcher did itself, listed among what the phone said,
  /// at the time of the signal it answered.
  void note(String name, String detail) => add(DVHomeAppSignal(name, _signals.isEmpty ? 0 : _signals.last.at, detail));

  void clear() {
    _signals = const <DVHomeAppSignal>[];
    _changes.add(_signals);
  }
}
