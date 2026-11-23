// Updates: which version this phone has, the newest release on GitHub, and
// the APK for this phone's processor. Pure Dart apart from the one fetch, so
// it is tested without a phone or a network.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// This build's version. A test keeps it equal to pubspec.yaml's.
const String launcherVersion = '0.1.14';

/// The newest published (not pre-release) version, as GitHub answers it.
final Uri latestReleaseApi = Uri.parse('https://api.github.com/repos/Danroyal001/dev_launcher/releases/latest');

/// Every release, for the "all releases" link.
const String releasesPage = 'https://github.com/Danroyal001/dev_launcher/releases';

/// One APK of a release.
class const ReleaseApk({required final String abi, required final String name, required final String url, required final int bytes});

/// A release as the updates screen shows it.
class const LauncherRelease({required final String version, required final String pageUrl, required final DateTime? published, required final List<ReleaseApk> apks, final String notes = ''});

const List<String> _abis = <String>['armeabi-v7a', 'arm64-v8a', 'x86_64'];

/// GitHub's answer for a release, or null when it is not one (an error, a
/// rate limit message).
LauncherRelease? parseRelease(Map<String, Object?> json) {
  final Object? tag = json['tag_name'];
  if (tag is! String || tag.isEmpty) return null;
  final List<ReleaseApk> apks = <ReleaseApk>[];
  final Object? assets = json['assets'];
  if (assets is List) {
    for (final Object? asset in assets) {
      if (asset is! Map) continue;
      final String name = '${asset['name'] ?? ''}';
      if (!name.endsWith('.apk')) continue;
      final String abi = _abis.firstWhere((String each) => name.contains(each), orElse: () => '');
      final Object? size = asset['size'];
      apks.add(ReleaseApk(abi: abi, name: name, url: '${asset['browser_download_url'] ?? ''}', bytes: size is int ? size : 0));
    }
  }
  final Object? published = json['published_at'];
  return LauncherRelease(
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    pageUrl: '${json['html_url'] ?? releasesPage}',
    published: published is String ? DateTime.tryParse(published) : null,
    apks: apks,
    notes: '${json['body'] ?? ''}'.trim(),
  );
}

/// Above zero when [a] is newer than [b]. A leading v is ignored and a
/// pre-release (0.1.13-rc1) comes before its release (0.1.13).
int compareVersions(String a, String b) {
  (List<int>, String) split(String version) {
    final String plain = version.startsWith('v') ? version.substring(1) : version;
    final int dash = plain.indexOf('-');
    final String core = dash < 0 ? plain : plain.substring(0, dash);
    return (<int>[for (final String part in core.split('.')) int.tryParse(part) ?? 0], dash < 0 ? '' : plain.substring(dash + 1));
  }

  final (List<int> numbersA, String preA) = split(a);
  final (List<int> numbersB, String preB) = split(b);
  for (int at = 0; at < 3; at++) {
    final int partA = at < numbersA.length ? numbersA[at] : 0;
    final int partB = at < numbersB.length ? numbersB[at] : 0;
    if (partA != partB) return partA.compareTo(partB);
  }
  if (preA == preB) return 0;
  if (preA.isEmpty) return 1;
  if (preB.isEmpty) return -1;
  return preA.compareTo(preB);
}

/// The APK of [release] for [abi], or null when there is none (or no abi).
ReleaseApk? apkForAbi(LauncherRelease release, String abi) {
  if (abi.isEmpty) return null;
  for (final ReleaseApk apk in release.apks) {
    if (apk.abi == abi) return apk;
  }
  return null;
}

/// Whether [release] is newer than the version this phone has.
bool isNewer(LauncherRelease release, {String installed = launcherVersion}) => compareVersions(release.version, installed) > 0;

/// One plain sentence: up to date, or what is out.
String updateHeadline(String installed, LauncherRelease release) =>
    compareVersions(release.version, installed) > 0 ? 'Dev Launcher ${release.version} is out. This phone has $installed.' : 'This phone has the newest version, $installed.';

/// Bytes as a phone shows a download: 15.6 MB.
String sizeText(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// What a processor name means to a person.
String abiName(String abi) => switch (abi) {
      'armeabi-v7a' => '32-bit ARM phones (Tecno, Infinix, itel and other older phones)',
      'arm64-v8a' => '64-bit ARM phones (most phones since 2017)',
      'x86_64' => 'x86 devices (emulators, some Chromebooks)',
      _ => 'other devices',
    };

/// What the last check found.
class const UpdateCheck({final LauncherRelease? release, final String problem = '', final bool checking = false});

/// The one place the launcher asks for updates, shared by the home screen
/// (a note when a newer version is out) and the updates screen.
class LauncherUpdates {
  static final LauncherUpdates instance = LauncherUpdates();

  /// How the release is fetched; tests replace it.
  Future<String> Function(Uri uri) fetch = _fetchWithDio;

  /// Whether the home screen checks on its own. Null: on a phone, not in the
  /// browser preview.
  bool? autoCheck;

  final StreamController<UpdateCheck> _changes = StreamController<UpdateCheck>.broadcast();
  UpdateCheck _current = const UpdateCheck();
  Future<void>? _running;

  UpdateCheck get current => _current;
  Stream<UpdateCheck> get changes => _changes.stream;

  void _emit(UpdateCheck next) {
    _current = next;
    _changes.add(next);
  }

  /// Asks GitHub for the newest release. One question at a time.
  Future<void> check() => _running ??= _check().whenComplete(() => _running = null);

  /// Checks only when nothing has been asked yet this run.
  Future<void> checkOnce() => _current.release != null || _current.problem.isNotEmpty || _running != null ? Future<void>.value() : check();

  Future<void> _check() async {
    _emit(UpdateCheck(release: _current.release, checking: true));
    try {
      final Object? json = jsonDecode(await fetch(latestReleaseApi));
      final LauncherRelease? release = json is Map<String, Object?> ? parseRelease(json) : null;
      _emit(release == null ? UpdateCheck(release: _current.release, problem: 'Could not check for updates: GitHub gave no release.') : UpdateCheck(release: release));
    } on Object catch (error) {
      _emit(UpdateCheck(release: _current.release, problem: 'Could not check for updates (${_plain(error)}). Check the connection and try again.'));
    }
  }

  /// Back to how a fresh start finds it. For tests.
  void reset() {
    fetch = _fetchWithDio;
    autoCheck = null;
    _running = null;
    _current = const UpdateCheck();
  }
}

String _plain(Object error) {
  if (error is DioException) return error.message ?? error.type.name;
  final String text = '$error';
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

Future<String> _fetchWithDio(Uri uri) async {
  final Response<String> response = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15))).getUri<String>(
    uri,
    options: Options(responseType: ResponseType.plain, headers: <String, String>{'Accept': 'application/vnd.github+json'}),
  );
  return response.data ?? '';
}
