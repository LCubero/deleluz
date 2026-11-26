# DeleLuz Android app

Native Android app (Flutter) for the LEDDMX-03 LED strip controller, with the Glow Glass design of the phone webapp ([`../webapp/README.md`](../webapp/README.md)). It is shared as an APK, not through an app store. iPhone builds need macOS and are not covered here.

<p align="center"><img src="../docs/app-screens/showreel.webp" width="300" alt="DeleLuz 1.0.0 Android app tour"></p>

## Install

1. Download the universal `DeleLuz-1.1.0.apk` from the [v1.1.0 release](https://github.com/LCubero/deleluz/releases/tag/v1.1.0). It requires Android 7.0 or newer.
2. Open it on the phone and allow installing apps from that source. Google Play Protect may warn because the app is not from the store.
3. Install over 1.0.0 or a test build signed with the same key to keep your data.

If Android rejects the update because the installed build uses a different key, uninstalling removes all app data (saved strips, aliases, scenes, quick actions, favorites, and settings). Android backup is disabled. The strip keeps its own settings.

## What it does

An [automated compatibility matrix](test/ui/compat_test.dart) covers 16 phone sizes.

- **Inicio**: connect, reconnect, disconnect, or cancel a pending connection. Tap the connection card to open Elegir tira, or swipe it horizontally to preview another saved strip without switching tabs or connecting. **Acciones rápidas** replaces **Escenas rápidas**: pick a type (color, effect, included scene, or saved scene), then an item. The off-timer sheet shows a countdown ring and shutoff time, offers +5 and +15 min, and accepts custom minutes and seconds up to 12 hours.
- **Color**: the color disc adjusts saturation and offers Cálido, Neutro, and Frío white presets. Color, quick actions, and scene color steps use the same picker, including editable color favorites. The three white chips have no heading; the picker no longer offers Noche. **Efectos integrados** lists **Ciclo de la tira**, **Catálogo** (search and starred favorites first), **AUTO de la app**, **Brillo**, then **Velocidad** (not on Inicio). After a manual catalog selection is sent, **En la tira: NN · name** shows what the app sent, not a reading from the strip. App AUTO shows the effect name and advances every 10 s, 30 s, 1 min, or 5 min through Todos or Favoritos. It only runs in the foreground while connected, unlike the separate firmware cycle.
- **Escenas**: **Mis escenas** supports up to eight color or built-in effect steps, each with its own duration. Older scenes still load and play. Included scenes and Música (four strip-microphone modes and sensitivity) are also available.
- **Elegir tira** (from Cambiar or Ajustes → Dispositivos): tap a saved or nearby strip to connect. Saved rows also offer rename and forget (or long-press for the menu). Use Desconectar to release the connected strip. Errors show on the row with Reintentar. Search appears with four or more strips.
- **Ajustes**: Dispositivos; Configuración del dispositivo (color order and LED count, saved per strip and sent only when connected and after a confirmation); language (Spanish default, English); help; privacy; Acerca de.

Horizontal drags on sliders and color pickers never switch tabs; swipe elsewhere on the page to change tab.

## Connection

One strip connected at a time; several can be saved, each with an alias that stays on this phone. BLE retries are bounded, and connect and write operations have timeouts. A prominent card prompts you to enable Bluetooth when it is off; notices use icons, snackbars use a dark translucent blur, and a failed timer shutoff shows an error with a retry option. Commands are spaced 50 ms apart, and a new slider value replaces the unsent one. A deliberate disconnect releases the strip so another phone or app can connect. **Último comando enviado** on Inicio shows what the app last sent, not the strip's real state. Wire format: [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).

## Limits

- Scene playback and the off timer run in the app, not on the strip. Keep the app in the foreground; opening the notification shade does not stop them.
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

Raise the build number in `pubspec.yaml` for every new build you share. The next build number must be greater than the v1.1.0 release's `2013`. Keep `lib/version.dart` in sync with the version name (a test checks it).

On Windows the release build sometimes fails with `stableIds.txt ... The device does not recognize the command`; delete `build/app/intermediates/stable_resource_ids_file` and build again.

On Windows, Kotlin incremental compilation is turned off in `android/gradle.properties` because plugin sources in the pub cache live on another drive.
