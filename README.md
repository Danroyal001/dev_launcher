# Dev Launcher

The Android home screen for developers. Built with [Dartvel](https://dartvel.dev).

- **A prompt, not a page of icons.** Type a few letters and Enter opens the best match. It matches
  the start of the name first, then a word in the name, then the letters in order anywhere, then the
  package name (`trx` finds Termux, `postman.app` finds Postman).
- **Commands.** `info <app>` opens the app's system page, `pin <app>` and `unpin <app>` change the
  pinned row, and `uninstall <app>` asks Android to remove it. A command word on its own is still a
  search, so `pin` finds Pinterest.
- **Dev tools row.** Terminals, Git hosts, editors, API clients, SSH and cloud consoles you have
  installed are picked out automatically (`lib/services/launcher_logic.dart`, `devToolPackages`).
- **Every app, A to Z**, with its real icon. Long-press any app for open, pin, app info and uninstall.
- **Recent apps.** The apps you opened last lead the drawer, newest first, in one row above the A-Z
  list. Kept on the phone across restarts; an uninstalled app leaves the row.
- **Installs and uninstalls while it is open.** Coming back to the home screen asks Android for the
  apps again: new apps appear (only their icons are drawn), removed ones leave the list, the recents
  and the icon cache. Tapping an app that is already gone says so and drops its tile.
- **No blank start.** The app names the last start saw show at once, then Android's own list, then
  the icons saved on the phone, then the missing icons a few at a time.
- **Small phones and large text.** The home screen scrolls when it is taller than the room above the
  dock, the dock's icons shrink to fit across, and titles end in an ellipsis instead of overflowing
  (tested at 320 px wide and up to 2x font size).
- A dark editor palette and JetBrains Mono. Pins are kept on the phone.

## Use it as your home screen

Install the APK, press Home, and choose Dev Launcher (or set it in Settings → Apps → Default apps →
Home app). `dartvel.android.launcher: true` in `pubspec.yaml` is what makes Android offer it, and lets
it see your installed apps on Android 11 and later.

## Build

```sh
dartvel build android # Android APK
dartvel build web     # a labelled preview with example apps, for the browser
dartvel test          # the matching and command tests
```

Listing and opening apps is `DV.Platform.apps` (Android). In a browser `isSupported` is false and the
launcher says it is showing example apps.

Fonts: JetBrains Mono, SIL Open Font License (`assets/fonts/JetBrainsMono-OFL.txt`).
