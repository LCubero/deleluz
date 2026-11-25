# DeleLuz Android app

Native Android app (Flutter) for the LEDDMX-03 LED strip controller. It has the same features and Glow Glass design as the phone webapp ([`../webapp/README.md`](../webapp/README.md)) and is shared as an APK, not through an app store. iPhone builds need macOS and are not covered here.

## Build

From `app/`, with the Flutter SDK in `../_tools/flutter` (not on `PATH`):

```sh
../_tools/flutter/bin/flutter test
../_tools/flutter/bin/flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

On Windows, Kotlin incremental compilation is turned off in `android/gradle.properties` because plugin sources in the pub cache live on another drive.

## What it does

- **Inicio**: connect to a strip named `LEDDMX…`, which the app remembers. Reconnect, switch strips, forget, or disconnect. Also power (disabled while disconnected), brightness, speed, quick scenes, up to six shortcuts, and the off timer.
- **Color**: hue wheel, shared Favoritos palette (up to 15), built-in effects 1–210 with vendor names, or Auto cycle.
- **Escenas**: included scenes, Mis escenas (1–8 colors, up to 12 scenes), and Música (four strip-microphone modes and their sensitivity).
- **Ajustes**: strip color order and LED count (sent only after a confirmation), language (Spanish default, English), help, and privacy.

## Connection

One strip at a time. Up to 4 connect tries, 300 ms apart. Commands are spaced 50 ms apart, and a new slider value replaces the unsent one. A deliberate disconnect releases the strip so another phone or app can connect. The app shows what it last sent, not the strip's real state: the controller reports nothing back. Wire format: [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).

## Limits

- Scene playback and the off timer run only while the app is in the foreground. The strip has no timer of its own.
- Shortcuts are reordered from the long-press menu, not by dragging.
- No per-LED control is known for this controller.

## Privacy and permissions

The app asks for Bluetooth permissions only when you tap Connect. On Android 12 and newer, nearby-device scanning does not use location. On Android 11 and older, Android requires the location permission to scan. The app makes no network requests and does not use the phone microphone, notifications, or accounts. Settings stay on the phone.
