# DeleLuz Android app

Native Android app (Flutter) for the LEDDMX-03 LED strip controller, with the Glow Glass design of the phone webapp ([`../webapp/README.md`](../webapp/README.md)). It is shared as an APK, not through an app store. iPhone builds need macOS and are not covered here.

<p align="center"><img src="../docs/app-screens/showreel.webp" width="300" alt="Published DeleLuz Android app tour"></p>

## Install

1. Download `DeleLuz-1.0.0.apk` from the [Releases](https://github.com/LCubero/deleluz/releases/latest) page. It is one file for every Android phone with Android 7.0 or newer.
2. Open it on the phone and allow installing apps from that source. Google Play Protect may warn because the app is not from the store.
3. Updates install over the previous version and keep your data.

If you installed a test build from before 1.0.0, uninstall it once first: it was signed with a different key. That removes its saved strips, aliases and scenes.

## What it does

The features below describe unreleased phase 1 on `feat/app-polish`, not the APK above. One phone has been tested; the wider compatibility pass is in progress ([T17](../odd/tasks/app-polish.md#tasks)).

- **Inicio**: connect, reconnect, disconnect, or cancel a pending connection. **Cambiar** opens the strip selector. The connection card does not swipe. **Acciones rápidas** replaces **Escenas rápidas**: pick a type (color, effect, included scene, or saved scene), then an item. The off-timer sheet shows a countdown ring and shutoff time, offers +5 and +15 min, and accepts custom minutes and seconds up to 12 hours.
- **Color**: the color disc adjusts saturation and offers Cálido, Neutro, and Frío white presets. Color, quick actions, and scene color steps use the same picker, including editable color favorites. Search the 210 built-in effects and star favorites to list them first. **AUTO de la app** shows the current effect name and advances every 10 s, 30 s, 1 min, or 5 min through Todos or Favoritos. It only runs in the foreground while connected. **Ciclo de la tira** is the separate firmware cycle.
- **Escenas**: **Mis escenas** supports up to eight color or built-in effect steps, each with its own duration. Older scenes still load and play. Included scenes and Música (four strip-microphone modes and sensitivity) are also available.
- **Elegir tira** (from Cambiar or Ajustes → Dispositivos): your saved strips and new nearby strips. Each row has rename (pencil), forget (trash) and one Conectar/Desconectar button; long-press for the same menu. Errors show on the row with Reintentar. Search appears with four or more strips.
- **Ajustes**: Dispositivos; Configuración del dispositivo (color order and LED count, saved per strip and sent only when connected and after a confirmation); language (Spanish default, English); help; privacy; Acerca de.

Horizontal drags on sliders and color pickers never switch tabs; swipe elsewhere on the page to change tab.

## Connection

One strip connected at a time; several can be saved, each with an alias that stays on this phone. BLE retries are bounded, and connect and write operations have timeouts. A prominent card prompts you to enable Bluetooth when it is off; notices use icons, and a failed timer shutoff shows an error with a retry option. Commands are spaced 50 ms apart, and a new slider value replaces the unsent one. A deliberate disconnect releases the strip so another phone or app can connect. The app shows what it last sent, not the strip's real state: the controller reports nothing back. Wire format: [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).

## Limits

- Scene playback and the off timer run only while the app is in front. The strip has no timer of its own.
- Shortcuts are reordered from the long-press menu, not by dragging.
- No per-LED control is known for this controller.
- No automatic update notice: install a newer APK over the old one.

## Privacy and permissions

The app asks for Bluetooth permissions only when you connect or search. On Android 12 and newer, nearby-device scanning does not use location; on Android 11 and older, Android requires the location permission to scan. The app makes no network requests and does not use the phone microphone, notifications, or accounts. Settings, saved strips and aliases stay on the phone: Android backup and device-to-device transfer are turned off for the app.

## Build

From `app/`, with the Flutter SDK in `../_tools/flutter` (not on `PATH`):

```sh
../_tools/flutter/bin/flutter test
../_tools/flutter/bin/flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk, published as DeleLuz-<version>.apk
```

Release signing reads `android/key.properties`, which points to a keystore under `android/release/`. Both are git-ignored; keep a private backup, because updates must be signed with the same key. Without `key.properties`, release builds fall back to the debug key, which is only for local testing. `key.properties` format:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=deleluz
storeFile=../release/deleluz-release.jks
```

Raise the build number in `pubspec.yaml` (`version: 1.0.0+N`) for every APK you share; Android only installs an update over a lower number. It starts at 2004 because earlier test builds were split per ABI and used codes up to 2003. Keep `lib/version.dart` in sync with the version name (a test checks it).

On Windows the release build sometimes fails with `stableIds.txt ... The device does not recognize the command`; delete `build/app/intermediates/stable_resource_ids_file` and build again.

On Windows, Kotlin incremental compilation is turned off in `android/gradle.properties` because plugin sources in the pub cache live on another drive.
