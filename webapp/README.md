# DeleLuz webapp

Phone web app for the LEDDMX-03-03C1 LED strip controller, over Web Bluetooth. Static files, no install or build. Design: [`design/deleluz-webapp/01-glow-glass.html`](../design/deleluz-webapp/01-glow-glass.html).

## Run

From the repository root (the app imports `lab/web/protocol.js` and `lab/web/presets.js`):

```sh
python webapp/serve.py
adb reverse tcp:8000 tcp:8000   # phone connected over USB
```

Open `http://localhost:8000/webapp/` in Chrome on Android. Close the LED LAMP app first: the controller accepts one connection. Add `?sim` to the URL to log frames instead of sending them; simulation is automatic when the browser has no Web Bluetooth (for example, iPhone browsers).

Spanish is the default; choose English in Help (Ayuda).

## What it does

- **Navigation**: tap the bottom tabs or swipe left/right on the page to move between Inicio, Color, Escenas and Ajustes (it wraps around from the last to the first) (not on sliders, the color wheel, color circles or open sheets). Every collapsible section starts closed.
- **Home**: power, brightness, quick scenes, off timer (clock icon). Keep up to six shortcuts to colors, included page scenes, or saved My scenes. Tap to play or apply; press and hold to change, move, or remove; hold and drag to reorder. Tap + to add a shortcut. The chooser opens with both Scenes and Colors collapsed. Collapse Quick scenes on Home to reveal the same effect speed control as in Color. In the chooser, tap a tile from the shared palette or use the wheel and Add this color. Existing color shortcuts keep their original RGB when you edit the palette. Shortcuts are saved in this browser only; deleting a saved scene removes its shortcuts.
- **Color**: hue wheel and quick colors; built-in controller effects 1–210 with their vendor names, or Auto cycle (shown as All). Brightness sits above effect speed.
- **Scenes**: included and saved scenes use same-height cards with names limited to two visible lines. Tap an included scene to apply it, or press and hold to open its preview. In **Mis escenas** (My scenes), tap + to draft a scene with 1–8 color squares, speed (0% slowest, 100% fastest), and intensity. Tap a square to select it and edit it with the hue wheel or swatches. Press and hold a square, then drag it onto another square to reorder the draft. Tap a saved scene to play it; press and hold to edit it or use the trash icon and confirm deletion. Tap the pencil to rename a scene. Names are trimmed, must contain 1–24 characters, and cannot match another saved name regardless of case. Play and Stop in the editor preview the draft on the connected strip. Tap Save to keep your changes (up to 12 scenes, stored in this browser only); closing without saving discards the draft. Playback shows one color at a time across the whole strip and requires the page to stay open and in the foreground. In **Música** (Music), choose one of four sound-reactive modes that use the strip’s own microphone.
- **Ajustes** (Settings): configure the strip’s color order and pixel count (choose Total de LEDs to type it, or Por metro to calculate it from LEDs per meter × meters, rounded to the nearest LED; 1–1024), choose the language, find troubleshooting by symptom, and review privacy and permissions. Sending strip settings requires a connection and confirmation, then writes the chip-config frame. The old `#help` link still opens Settings.

**Connection status:** Color, Scenes, and Settings show the same status chip (status only). Connect and disconnect from the device card on Home.

**Shared color palette (Favoritos):** the same favorites appear in Color → Solid color, the scene editor and the quick-scene chooser, in the same order (wheel, Favoritos, circles). They start as green, yellow and red, are collapsed until you open them (each place remembers its own state), and hold up to 15 colors. Tap a favorite to use it and select it; "+" replaces the selected one or adds the wheel color; press and hold to move a favorite or drag it to the trash to delete it (the list may become empty). The quick-scene chooser also offers Blanco cálido, Blanco frío and Noche.

## Limits

- The controller reports nothing back: the app shows what it last sent, not the strip's real state.
- Page scenes and the off timer run only while this page is open and in front; the strip has no timer of its own. If the page closes, the strip stays on with its last color.
- Commands sent: power, brightness, whole-strip color, built-in effect, speed, voice mode (1–4), and chip configuration. The page does not capture or stream audio.
- Only RGB, GRB and BGR orders, at 150 pixels, were confirmed on the physical strip. Other orders follow the vendor list, and the app accepts the vendor range of 1–1024 pixels.
- Commands are spaced 50 ms apart (the strip follows changes down to ~35 ms, see `docs/CAPABILITIES.md`); the scene step interval starts at 150 ms, and fade scenes send intermediate colors about every 50 ms.
- No per-LED control is known for this controller.

## Privacy and errors

The app loads static files from its host and makes no application network requests after loading. It asks Chrome to show the Bluetooth chooser only on Connect; Reconnect can reuse the chosen strip. Disconnect is available on Home. The app does not access your location, phone microphone, notifications, or accounts. Music modes use the strip’s microphone. The foreground off timer may use Screen Wake Lock; it still runs in the foreground if wake lock is unavailable or denied.

Settings stay in this browser’s local storage. The keys all start with `deleluz.webapp.`: `state`, `shortcuts`, `sequences`, `quickOpen`, `palette`, `language`, and `stripSettings`. If `palette` is missing, the app combines the defaults with the colors from a valid legacy `customColors` list, without duplicates and up to the 15-color limit. The first palette edit saves the new list. Unreadable or invalid saved settings fall back to safe defaults. Command, connection, and save failures show a short localized message, not the browser’s raw error. A storage failure does not block strip commands. Simulation logs command bytes only, not device identifiers.

## Tests

```sh
node --test webapp/ lab/web/
```
