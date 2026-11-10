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
- A dark editor palette and JetBrains Mono. Pins are kept on the phone.

## Use it as your home screen

Install the APK, press Home, and choose Dev Launcher (or set it in Settings → Apps → Default apps →
Home app). `dartvel.android.launcher: true` in `pubspec.yaml` is what makes Android offer it, and lets
it see your installed apps on Android 11 and later.

## Build

```sh
dartvel build apk     # Android
dartvel build web     # a labelled preview with example apps, for the browser
dartvel test          # the matching and command tests
```

Listing and opening apps is `DV.Platform.apps` (Android). In a browser `isSupported` is false and the
launcher says it is showing example apps.

Fonts: JetBrains Mono, SIL Open Font License (`assets/fonts/JetBrainsMono-OFL.txt`).
