// The pure half of the standard launcher features: hidden apps, folders,
// rearranging the home screen, the launcher's own settings, backup and
// restore of the layout, and what the drawer's search offers besides apps.
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_launcher/services/launcher_logic.dart';

void main() {
  group('the layout keeps what the person arranged', () {
    test('hidden apps, folders and options survive a save and a read', () {
      const LauncherLayout layout = LauncherLayout(
        home: <String>['com.termux', 'folder:1'],
        dock: <String>['com.android.chrome'],
        hidden: <String>['com.facebook.katana'],
        folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'Social', apps: <String>['com.whatsapp', 'com.twitter.android'])],
        options: LauncherOptions(swipeDownShade: false, doubleTapLock: true, pinchSettings: false, badges: false, searchWeb: false, searchContacts: true),
      );
      final LauncherLayout back = LauncherLayout.decode(layout.encode());
      expect(back.home, layout.home);
      expect(back.hidden, <String>['com.facebook.katana']);
      expect(back.folders.single.name, 'Social');
      expect(back.folders.single.apps, <String>['com.whatsapp', 'com.twitter.android']);
      expect(back.options.swipeDownShade, isFalse);
      expect(back.options.pinchSettings, isFalse);
      expect(back.options.badges, isFalse);
      expect(back.options.searchWeb, isFalse);
      expect(back.options.searchContacts, isTrue);
    });

    test('a layout saved before these existed reads with nothing hidden, no folders and every gesture on', () {
      final LauncherLayout old = LauncherLayout.decode('{"home":["com.termux"],"dock":[]}');
      expect(old.hidden, isEmpty);
      expect(old.folders, isEmpty);
      expect(old.options.swipeDownShade, isTrue);
      expect(old.options.doubleTapLock, isTrue);
      expect(old.options.pinchSettings, isTrue);
      expect(old.options.badges, isTrue);
      expect(old.options.searchWeb, isTrue);
      expect(old.options.searchContacts, isFalse, reason: 'reading contacts asks for a permission: off until chosen');
    });

    test('a folder id on home with no folder behind it is dropped, not shown blank', () {
      final LauncherLayout layout = LauncherLayout.decode('{"home":["com.termux","folder:9"],"dock":[]}');
      expect(layout.home, <String>['com.termux']);
    });
  });

  group('folders', () {
    test('putting an app in a new folder replaces it on home with the folder, where it was', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['a', 'b', 'c']);
      final LauncherLayout next = addToFolder(layout, 'b', folderName: 'Work');
      expect(next.home, <String>['a', 'folder:${next.folders.single.id}', 'c']);
      expect(next.folders.single.apps, <String>['b']);
      expect(next.folders.single.name, 'Work');
    });

    test('putting an app in an existing folder takes it off home and out of other folders', () {
      const LauncherLayout layout = LauncherLayout(
        home: <String>['a', 'folder:1', 'b', 'folder:2'],
        folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'One', apps: <String>['x', 'y']), LauncherFolder(id: '2', name: 'Two', apps: <String>['z', 'w', 'b'])],
      );
      final LauncherLayout next = addToFolder(layout, 'b', folderId: '1');
      expect(next.home, <String>['a', 'folder:1', 'folder:2']);
      expect(next.folders.firstWhere((LauncherFolder folder) => folder.id == '1').apps, <String>['x', 'y', 'b']);
      expect(next.folders.firstWhere((LauncherFolder folder) => folder.id == '2').apps, <String>['z', 'w']);
    });

    test('a folder left with one app gives it back to home in its place; an empty one goes', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['a', 'folder:1'], folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'F', apps: <String>['x', 'y'])]);
      final LauncherLayout one = removeFromFolder(layout, '1', 'x');
      expect(one.home, <String>['a', 'y']);
      expect(one.folders, isEmpty);
    });

    test('renaming keeps the apps; a blank name is "Folder"', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['folder:1'], folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'F', apps: <String>['x', 'y'])]);
      expect(renameFolder(layout, '1', 'Games').folders.single.name, 'Games');
      expect(renameFolder(layout, '1', '  ').folders.single.name, 'Folder');
      expect(renameFolder(layout, '1', 'Games').folders.single.apps, <String>['x', 'y']);
    });

    test('new folder ids never repeat one in use', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['folder:1', 'folder:2', 'a'], folders: <LauncherFolder>[LauncherFolder(id: '1', name: 'A', apps: <String>['x', 'y']), LauncherFolder(id: '2', name: 'B', apps: <String>['z', 'w'])]);
      final LauncherLayout next = addToFolder(layout, 'a');
      expect(next.folders.map((LauncherFolder folder) => folder.id).toSet().length, 3);
    });
  });

  group('rearranging the home screen by dragging', () {
    test('a tile dropped a cell to the right and a row down lands there', () {
      expect(dropIndex(from: 0, dx: 90, dy: 0, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 1);
      expect(dropIndex(from: 0, dx: 0, dy: 110, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 4);
      expect(dropIndex(from: 5, dx: -170, dy: -95, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 0);
    });

    test('a small wobble stays put, and a drop past either end goes to that end', () {
      expect(dropIndex(from: 2, dx: 30, dy: -40, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 2);
      expect(dropIndex(from: 2, dx: 0, dy: 900, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 7);
      expect(dropIndex(from: 2, dx: -900, dy: -900, columns: 4, cellWidth: 80, cellHeight: 100, count: 8), 0);
    });

    test('moving an item shifts the ones between, keeping everything once', () {
      expect(moveItem(<String>['a', 'b', 'c', 'd'], 0, 2), <String>['b', 'c', 'a', 'd']);
      expect(moveItem(<String>['a', 'b', 'c', 'd'], 3, 0), <String>['d', 'a', 'b', 'c']);
      expect(moveItem(<String>['a', 'b'], 1, 1), <String>['a', 'b']);
    });
  });

  group('backup and restore', () {
    test('a backup is the layout with a header, and restoring it gives the same layout', () {
      const LauncherLayout layout = LauncherLayout(home: <String>['com.termux'], hidden: <String>['com.x'], dock: <String>['com.android.chrome']);
      final String backup = layoutBackup(layout);
      expect(backup, startsWith('dev-launcher-layout:'));
      final LauncherLayout? restored = restoreLayout(backup);
      expect(restored?.home, <String>['com.termux']);
      expect(restored?.hidden, <String>['com.x']);
    });

    test('anything else pasted is no layout, never an empty one written over the person\'s', () {
      expect(restoreLayout('hello'), isNull);
      expect(restoreLayout('dev-launcher-layout:{not json'), isNull);
      expect(restoreLayout(''), isNull);
    });
  });

  group('what the search offers besides apps', () {
    test('settings pages match their words', () {
      final List<(String, List<String>)> pages = <(String, List<String>)>[('Wi-Fi', <String>['wifi', 'network']), ('Bluetooth', <String>['bluetooth']), ('Display', <String>['brightness', 'dark mode'])];
      expect(matchKeywords(pages, 'wifi', ((String, List<String>) page) => <String>[page.$1, ...page.$2]).map(((String, List<String>) page) => page.$1), <String>['Wi-Fi']);
      expect(matchKeywords(pages, 'bright', ((String, List<String>) page) => <String>[page.$1, ...page.$2]).map(((String, List<String>) page) => page.$1), <String>['Display']);
      expect(matchKeywords(pages, 'b', ((String, List<String>) page) => <String>[page.$1, ...page.$2]), isEmpty, reason: 'one letter is an app search, not a settings list');
    });

    test('the web search is the phone\'s browser on a search page for the words', () {
      expect(webSearchUrl('dart records'), 'https://www.google.com/search?q=dart%20records');
    });

    test('contacts match by name or number', () {
      final List<LauncherContact> contacts = <LauncherContact>[const LauncherContact(name: 'Ada Lovelace', phone: '+44 20 1234'), const LauncherContact(name: 'Grace Hopper', phone: '555 0100')];
      expect(matchContacts(contacts, 'ada').map((LauncherContact contact) => contact.name), <String>['Ada Lovelace']);
      expect(matchContacts(contacts, 'hop').map((LauncherContact contact) => contact.name), <String>['Grace Hopper']);
      expect(matchContacts(contacts, '5550').map((LauncherContact contact) => contact.name), <String>['Grace Hopper']);
      expect(matchContacts(contacts, 'a'), isEmpty, reason: 'one letter would list half the phone book');
    });
  });

  test('the drawer and its search leave hidden apps out', () {
    const List<LauncherApp> apps = <LauncherApp>[LauncherApp(packageName: 'a', label: 'Alpha'), LauncherApp(packageName: 'b', label: 'Bravo')];
    expect(visibleApps(apps, <String>['b']).map((LauncherApp app) => app.label), <String>['Alpha']);
  });
}
