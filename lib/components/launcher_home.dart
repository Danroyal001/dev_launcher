// The home screen: a clock, a prompt that opens apps and runs commands,
// pinned apps, the developer's tools, and every app A to Z.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/launcher_logic.dart';
import 'theme.dart';

const String _pinsFile = 'dev-launcher/pins.json';

/// Shown where the device cannot list apps (a browser), clearly as examples.
const List<DVInstalledApp> _previewApps = <DVInstalledApp>[
  DVInstalledApp(packageName: 'com.termux', label: 'Termux'),
  DVInstalledApp(packageName: 'com.github.android', label: 'GitHub'),
  DVInstalledApp(packageName: 'com.postman.app', label: 'Postman'),
  DVInstalledApp(packageName: 'com.android.chrome', label: 'Chrome'),
  DVInstalledApp(packageName: 'com.google.android.gm', label: 'Gmail'),
  DVInstalledApp(packageName: 'com.slack', label: 'Slack'),
  DVInstalledApp(packageName: 'com.spotify.music', label: 'Spotify'),
  DVInstalledApp(packageName: 'com.whatsapp', label: 'WhatsApp'),
];

class LauncherHome extends StatefulWidget {
  const LauncherHome({super.key});

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome> {
  final TextEditingController _prompt = TextEditingController();
  final FocusNode _promptFocus = FocusNode();
  List<DVInstalledApp> _apps = const <DVInstalledApp>[];
  List<String> _pins = <String>[];
  bool _preview = false;
  bool _loading = true;
  String _status = '';
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _now = DateTime.now()));
    _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _prompt.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final DVApps apps = DV.Platform.apps;
    List<DVInstalledApp> found;
    bool preview = false;
    if (apps.isSupported) {
      try {
        found = await apps.list();
      } on Object catch (error) {
        found = const <DVInstalledApp>[];
        _status = 'Could not read your apps: $error';
      }
    } else {
      found = _previewApps;
      preview = true;
    }
    final List<String> pins = await _readPins();
    if (!mounted) return;
    setState(() {
      _apps = found;
      _preview = preview;
      _pins = pins.where((String p) => found.any((DVInstalledApp a) => a.packageName == p)).toList();
      _loading = false;
    });
  }

  Future<List<String>> _readPins() async {
    try {
      final DVDeviceStorage storage = DV.Platform.fileStorage;
      if (!await storage.exists(_pinsFile)) return <String>[];
      final Object? decoded = jsonDecode(utf8.decode(await storage.get(_pinsFile)));
      return decoded is List ? <String>[for (final Object? item in decoded) '$item'] : <String>[];
    } on Object {
      return <String>[];
    }
  }

  Future<void> _savePins() async {
    try {
      await DV.Platform.fileStorage.put(_pinsFile, utf8.encode(jsonEncode(_pins)));
    } on Object catch (error) {
      setState(() => _status = 'Could not save pins: $error');
    }
  }

  List<LauncherApp> get _launcherApps => <LauncherApp>[
        for (final DVInstalledApp app in _apps) LauncherApp(packageName: app.packageName, label: app.label),
      ];

  DVInstalledApp? _byPackage(String package) {
    for (final DVInstalledApp app in _apps) {
      if (app.packageName == package) return app;
    }
    return null;
  }

  Future<void> _act(LauncherAction action, String package) async {
    final DVInstalledApp? app = _byPackage(package);
    if (app == null) return;
    if (_preview && action != LauncherAction.pin && action != LauncherAction.unpin) {
      setState(() => _status = 'Preview: on your phone this would ${action.name} ${app.label}.');
      return;
    }
    try {
      switch (action) {
        case .open:
          await DV.Platform.apps.open(package);
        case .info:
          await DV.Platform.apps.openSettings(package);
        case .uninstall:
          await DV.Platform.apps.uninstall(package);
        case .pin:
          if (!_pins.contains(package)) setState(() => _pins = <String>[..._pins, package]);
          await _savePins();
        case .unpin:
          setState(() => _pins = _pins.where((String p) => p != package).toList());
          await _savePins();
        case .none:
          break;
      }
      if (action == LauncherAction.open || action == LauncherAction.info) _clearPrompt();
    } on Object catch (error) {
      setState(() => _status = '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  void _clearPrompt() {
    _prompt.clear();
    setState(() => _status = '');
  }

  void _submit(String typed) {
    final LauncherCommand command = parseCommand(typed, _launcherApps);
    if (command.action == LauncherAction.none) {
      setState(() => _status = command.message);
      return;
    }
    _act(command.action, command.app!.packageName);
    if (command.action == LauncherAction.pin || command.action == LauncherAction.unpin) {
      setState(() => _status = '${command.action == LauncherAction.pin ? 'Pinned' : 'Unpinned'} ${command.app!.label}.');
      _prompt.clear();
    }
  }

  void _menu(DVInstalledApp app) {
    final bool pinned = _pins.contains(app.packageName);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LauncherColors.surface,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Padding(
              padding: const .fromLTRB(20, 20, 20, 8),
              child: Text(app.label, style: launcherText(size: 18, bold: true)),
            ),
            Padding(
              padding: const .fromLTRB(20, 0, 20, 12),
              child: Text(app.packageName, style: launcherText(size: 13, color: LauncherColors.muted)),
            ),
            for (final (String label, LauncherAction action, IconData icon) in <(String, LauncherAction, IconData)>[
              ('Open', LauncherAction.open, Icons.open_in_new),
              (pinned ? 'Unpin' : 'Pin to home', pinned ? LauncherAction.unpin : LauncherAction.pin, Icons.push_pin_outlined),
              ('App info', LauncherAction.info, Icons.info_outline),
              ('Uninstall', LauncherAction.uninstall, Icons.delete_outline),
            ])
              ListTile(
                leading: Icon(icon, color: action == LauncherAction.uninstall ? LauncherColors.danger : LauncherColors.text),
                title: Text(label, style: launcherText(size: 15, color: action == LauncherAction.uninstall ? LauncherColors.danger : LauncherColors.text)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _act(action, app.packageName);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String typed = _prompt.text;
    final List<DVInstalledApp> matches = <DVInstalledApp>[
      for (final LauncherApp app in matchApps(_launcherApps, typed.split(' ').length > 1 && const <String>{'info', 'pin', 'unpin', 'uninstall'}.contains(typed.split(' ').first.toLowerCase()) ? typed.substring(typed.indexOf(' ') + 1) : typed))
        if (_byPackage(app.packageName) case final DVInstalledApp found) found,
    ];
    final List<DVInstalledApp> pinned = <DVInstalledApp>[for (final String p in _pins) if (_byPackage(p) case final DVInstalledApp app) app];
    final List<DVInstalledApp> devTools = _apps.where((DVInstalledApp a) => isDevTool(a.packageName)).toList();
    return Scaffold(
      backgroundColor: LauncherColors.page,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const .fromLTRB(20, 28, 20, 0),
              sliver: SliverList.list(children: <Widget>[
                if (_preview) const _PreviewNotice(),
                _Clock(now: _now, appCount: _apps.length),
                const SizedBox(height: 24),
                _Prompt(controller: _prompt, focus: _promptFocus, onChanged: (_) => setState(() => _status = ''), onSubmitted: _submit),
                if (_status.isNotEmpty)
                  Padding(padding: const .only(top: 10), child: Text(_status, style: launcherText(size: 13, color: LauncherColors.muted))),
                if (typed.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  for (final DVInstalledApp app in matches.take(6)) _MatchRow(app: app, onOpen: () => _act(.open, app.packageName), onMenu: () => _menu(app)),
                  if (matches.isEmpty) Text('Enter runs it. Try: info, pin, unpin, uninstall + an app.', style: launcherText(size: 13, color: LauncherColors.muted)),
                ],
                const SizedBox(height: 28),
                if (pinned.isNotEmpty) ...<Widget>[
                  const _SectionLabel('pinned'),
                  _IconRow(apps: pinned, onOpen: (DVInstalledApp a) => _act(.open, a.packageName), onMenu: _menu),
                  const SizedBox(height: 24),
                ],
                if (devTools.isNotEmpty) ...<Widget>[
                  const _SectionLabel('dev tools'),
                  _IconRow(apps: devTools, onOpen: (DVInstalledApp a) => _act(.open, a.packageName), onMenu: _menu),
                  const SizedBox(height: 24),
                ],
                _SectionLabel(_loading ? 'reading apps…' : 'all apps · ${_apps.length}'),
              ]),
            ),
            SliverPadding(
              padding: const .fromLTRB(12, 4, 12, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 104),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => _AppTile(app: _apps[index], onOpen: () => _act(.open, _apps[index].packageName), onMenu: () => _menu(_apps[index])),
                  childCount: _apps.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) => Container(
        margin: const .only(bottom: 20),
        padding: const .all(14),
        decoration: BoxDecoration(color: LauncherColors.surface, borderRadius: .circular(10), border: .all(color: LauncherColors.rule)),
        child: Text(
          'Preview. Dev Launcher is an Android home screen; here it shows example apps. Install it on Android to see yours.',
          style: launcherText(size: 13, color: LauncherColors.muted),
        ),
      );
}

class _Clock extends StatelessWidget {
  const _Clock({required this.now, required this.appCount});

  final DateTime now;
  final int appCount;

  static const List<String> _days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        // The page's heading: what a screen reader user hears first.
        Semantics(
          headingLevel: 1,
          label: 'Dev Launcher, ${two(now.hour)}:${two(now.minute)}',
          child: ExcludeSemantics(child: Text('${two(now.hour)}:${two(now.minute)}', style: launcherText(size: 64, bold: true, height: 1))),
        ),
        const SizedBox(height: 8),
        Text('${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]} · $appCount apps', style: launcherText(size: 15, color: LauncherColors.muted)),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.controller, required this.focus, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const .symmetric(horizontal: 14),
        decoration: BoxDecoration(color: LauncherColors.surface, borderRadius: .circular(10), border: .all(color: LauncherColors.rule)),
        child: Row(
          children: <Widget>[
            Text('❯', style: launcherText(size: 18, bold: true, color: LauncherColors.accent)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: .go,
                inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(80)],
                cursorColor: LauncherColors.accent,
                style: launcherText(size: 16),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'open an app or run a command',
                  hintStyle: launcherText(size: 16, color: LauncherColors.muted),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const .only(bottom: 10),
        child: Text('// $text', style: launcherText(size: 13, color: LauncherColors.accent)),
      );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, this.size = 52});

  final DVInstalledApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Uint8List? icon = app.icon;
    if (icon != null) return Image.memory(icon, width: size, height: size, gaplessPlayback: true);
    // No icon: the first letter on a tile, never an empty square.
    return Container(
      width: size,
      height: size,
      alignment: .center,
      decoration: BoxDecoration(color: LauncherColors.surface, borderRadius: .circular(size * 0.28), border: .all(color: LauncherColors.rule)),
      child: Text(app.label.isEmpty ? '?' : app.label.substring(0, 1).toUpperCase(), style: launcherText(size: size * 0.42, bold: true, color: LauncherColors.accent)),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onOpen, required this.onMenu});

  final DVInstalledApp app;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Open ${app.label}. Long-press for more',
        child: InkWell(
          borderRadius: .circular(12),
          onTap: onOpen,
          onLongPress: onMenu,
          child: Padding(
            padding: const .all(6),
            child: Column(
              children: <Widget>[
                _AppIcon(app: app),
                const SizedBox(height: 6),
                Text(app.label, maxLines: 1, overflow: .ellipsis, textAlign: .center, style: launcherText(size: 12)),
              ],
            ),
          ),
        ),
      );
}

class _IconRow extends StatelessWidget {
  const _IconRow({required this.apps, required this.onOpen, required this.onMenu});

  final List<DVInstalledApp> apps;
  final void Function(DVInstalledApp) onOpen;
  final void Function(DVInstalledApp) onMenu;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: .horizontal,
          itemCount: apps.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (BuildContext context, int index) =>
              SizedBox(width: 80, child: _AppTile(app: apps[index], onOpen: () => onOpen(apps[index]), onMenu: () => onMenu(apps[index]))),
        ),
      );
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.app, required this.onOpen, required this.onMenu});

  final DVInstalledApp app;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Open ${app.label}',
        child: InkWell(
          onTap: onOpen,
          onLongPress: onMenu,
          borderRadius: .circular(8),
          child: Padding(
            padding: const .symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: <Widget>[
                _AppIcon(app: app, size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(app.label, style: launcherText(size: 15))),
                Text(app.packageName, style: launcherText(size: 11, color: LauncherColors.muted)),
              ],
            ),
          ),
        ),
      );
}
