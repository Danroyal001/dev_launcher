// What the prompt understands: fuzzy app matching and a handful of commands.
// Pure Dart, so it is tested without a phone.

/// An app as the launcher sees it.
class const LauncherApp({required final String packageName, required final String label});

enum LauncherAction { open, info, pin, unpin, uninstall, none }

/// What pressing Enter on the prompt does.
class const LauncherCommand({required final LauncherAction action, final LauncherApp? app, final String message = ''});

/// Apps whose name or package contains [query]'s letters in order, best first:
/// a name that starts with the query, then a word in the name that does, then
/// the letters anywhere in the name, then anywhere in the package.
List<LauncherApp> matchApps(List<LauncherApp> apps, String query) {
  final String wanted = query.trim().toLowerCase();
  if (wanted.isEmpty) return const <LauncherApp>[];
  final List<(int, LauncherApp)> scored = <(int, LauncherApp)>[];
  for (final LauncherApp app in apps) {
    final int score = _score(app, wanted);
    if (score > 0) scored.add((score, app));
  }
  scored.sort(((int, LauncherApp) a, (int, LauncherApp) b) =>
      b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.label.toLowerCase().compareTo(b.$2.label.toLowerCase()));
  return <LauncherApp>[for (final (int, LauncherApp) entry in scored) entry.$2];
}

int _score(LauncherApp app, String wanted) {
  final String label = app.label.toLowerCase();
  final String package = app.packageName.toLowerCase();
  if (label.startsWith(wanted)) return 400;
  if (label.split(RegExp(r'[\s\-_.]+')).any((String word) => word.startsWith(wanted))) return 300;
  if (label.contains(wanted)) return 250;
  if (package.contains(wanted)) return 200;
  if (_inOrder(label, wanted)) return 100;
  if (_inOrder(package, wanted)) return 50;
  return 0;
}

bool _inOrder(String text, String letters) {
  int at = 0;
  for (final int unit in letters.codeUnits) {
    at = text.indexOf(String.fromCharCode(unit), at);
    if (at < 0) return false;
    at++;
  }
  return true;
}

const Map<String, LauncherAction> _verbs = <String, LauncherAction>{
  'info': LauncherAction.info,
  'pin': LauncherAction.pin,
  'unpin': LauncherAction.unpin,
  'uninstall': LauncherAction.uninstall,
};

/// Reads what was typed: `<verb> <app>` for a command, anything else opens the
/// best match. A verb with nothing after it is a search, so "pin" still finds
/// Pinterest.
LauncherCommand parseCommand(String typed, List<LauncherApp> apps) {
  final String text = typed.trim();
  final int space = text.indexOf(' ');
  if (space > 0) {
    final LauncherAction? verb = _verbs[text.substring(0, space).toLowerCase()];
    if (verb != null) {
      final String target = text.substring(space + 1).trim();
      final List<LauncherApp> found = matchApps(apps, target);
      if (found.isEmpty) return LauncherCommand(action: LauncherAction.none, message: 'No app matches "$target".');
      return LauncherCommand(action: verb, app: found.first);
    }
  }
  final List<LauncherApp> found = matchApps(apps, text);
  if (found.isEmpty) return LauncherCommand(action: LauncherAction.none, message: text.isEmpty ? '' : 'No app matches "$text".');
  return LauncherCommand(action: LauncherAction.open, app: found.first);
}

/// Package prefixes of apps developers reach for: terminals, Git hosts,
/// editors, API clients, cloud consoles and the like.
const List<String> devToolPackages = <String>[
  'com.termux',
  'com.github.android',
  'com.gitlab',
  'com.microsoft.vscode',
  'com.jetbrains',
  'com.postman',
  'com.amazon.aws',
  'com.google.android.apps.cloudconsole',
  'com.vercel',
  'io.heroku',
  'com.digitalocean',
  'com.stackexchange',
  'com.slack',
  'com.discord',
  'com.atlassian',
  'com.linear',
  'org.connectbot',
  'com.server.auditor.ssh.client',
  'com.offsec.nethunter',
  'com.aide.ui',
  'io.spck',
  'com.foxdebug.acode',
  'ru.iiec.pydroid3',
  'com.cloudflare.onedotonedotonedotone',
];

/// Whether [packageName] is one of [devToolPackages].
bool isDevTool(String packageName) => devToolPackages.any(packageName.startsWith);
