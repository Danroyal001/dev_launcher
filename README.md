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
- **A letter index on the edge, as on Pixel and iPhone.** Tap a letter, or drag a finger (or the
  mouse) along the index, and that letter's apps come to the top, with a bubble naming the letter
  under the finger. It never filters: every app stays in the list. Letters with no apps are dimmed
  and go to the next letter that has some. Each letter has a tooltip and a screen-reader name. The
  index sits on the right, or the left on a phone set to a right-to-left language; "drawer
  settings" at the top of the list picks Follow device, Left or Right.
- **Search clears with x.** The x at the end of the search field empties it and keeps the focus
  (and the keyboard) in the field.
- **The clock follows the phone.** 12- or 24-hour as the phone is set, and the date in the
  phone's language and order (Sun, Nov 15 in US English, Sun 15 Nov in British English).
- **Recent apps in the drawer.** The apps you opened last lead the drawer, newest first, in one row above the A-Z
  list. Kept on the phone across restarts; an uninstalled app leaves the row.
- **Installs and uninstalls while it is open.** Coming back to the home screen asks Android for the
  apps again: new apps appear (only their icons are drawn), removed ones leave the list, the recents
  and the icon cache. Tapping an app that is already gone says so and drops its tile.
- **No blank start.** The app names the last start saw show at once, then Android's own list, then
  the icons saved on the phone, then the missing icons a few at a time.
- **Back and Home behave like a launcher's.** Back closes what is on top: the Recents settings, then
  Recents, then the drawer whenever any of it is showing. Home, pressed while the launcher is in
  front, closes all of them (`DV.Platform.apps.homePresses`). An app opened from the drawer closes
  it behind the app, so coming back lands on the home screen.
- **Its own Recents, laid out like a phone's.** The apps you opened from Dev Launcher, newest first,
  as a row of large cards scrolled sideways (each app's icon on its own colour): tap a card to open
  the app, swipe it up (or its x) to take it off, "Clear all" after the last card empties the row.
  Android shows a third-party home app no other app's screenshot, and does not let it close
  other apps' tasks, so the cards are icons and closing takes the app off Dev Launcher's list. It
  opens from the dock's Recents button and a swipe left on the home screen; Back or Home closes it.
- **The Recents button matches the phone's navigation bar.** On the side the phone puts Recents
  (left on Tecno, Infinix, itel, Samsung and Xiaomi; right on Pixel and most others), drawn the
  way that bar draws it (three lines, or three bars on Samsung), never a square. Recents button
  settings pick Follow device, Left or Right. Android gives the
  phone's Recents button to the phone's own Recents, never to a home app you install, so:
  - where the phone tells Dev Launcher about the press and shows nothing itself, Dev Launcher's
    Recents opens (`DV.Platform.apps.recentsPresses`);
  - **optional:** turn on "Dev Launcher Recents" under Accessibility (Recents → Recents button
    settings) and the phone's Recents button opens Dev Launcher's Recents. The service only notices
    the Recents button and which window opens; it does not read the screen or what you type.
- **Recents diagnostics.** The same settings screen lists, live, everything the phone told Dev
  Launcher (Home, Back, Recents, pauses, focus changes, windows the service saw) and when. Press
  Recents on your phone, come back, and it shows what that phone really sends.
- **No text selection.** A home screen is not a document: a long press on a label is "more about
  this app", never "select this text" (`@DVPage(selectable: false)` on every page). The command and
  search fields still take typing, and every control keeps its name and tooltip.
- **No freeze on returning home.** Listing apps and drawing icons run off the main thread
  (Dartvel 0.13.51), and the list is re-read 2 s after the home screen is back, at most every 30 s.
- **Small phones and large text.** The home screen scrolls when it is taller than the room above the
  dock, the dock's icons shrink to fit across, and titles end in an ellipsis instead of overflowing
  (tested at 320 px wide and up to 2x font size).
- **One line across the dock.** The round menu and All apps buttons take the same slot as an app
  icon, so every dock item shares one centre line and one size (tested at 320, 360 and 412 px wide).
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
