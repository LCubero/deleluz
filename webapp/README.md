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

- **Home**: power, brightness, quick scenes, off timer (clock icon). Keep up to six shortcuts to colors, included page scenes, or saved My scenes. Tap to play or apply; press and hold to change, move, or remove; hold and drag to reorder. Tap + to add a shortcut. The chooser opens with both Scenes and Colors collapsed. Collapse Quick scenes on Home to reveal the same effect speed control as in Color. In the chooser, tap a tile from the shared palette or use the wheel and Add this color. Existing color shortcuts keep their original RGB when you edit the palette. Shortcuts are saved in this browser only; deleting a saved scene removes its shortcuts.
- **Color**: hue wheel and quick colors; built-in controller effects 1–210 with their vendor names, or Auto cycle (shown as All). Brightness sits above effect speed.
- **Scenes**: preview included page scenes and built-in effects before applying. In **Mis escenas** (My scenes), tap + to draft a scene with 1–8 color squares, speed (0% slowest, 100% fastest), and intensity. Tap a square to select it and edit it with the hue wheel or swatches. Press and hold a square, then drag it onto another square to reorder the draft. Tap a saved scene to play it; press and hold to edit it or use the trash icon and confirm deletion. Play and Stop in the editor preview the draft on the connected strip. Tap Save to keep your changes (up to 12 scenes, stored in this browser only); closing without saving discards the draft. Playback shows one color at a time across the whole strip and requires the page to stay open and in the foreground. In **Música** (Music), choose one of four sound-reactive modes that use the strip’s own microphone.
- **Help**: connection state, Reconnect, and fixes by symptom.

**Shared color palette:** Color → Solid color and the scene editor both let you edit the same palette, and the quick-scene chooser shows those colors as tiles. The palette starts with nine colors and holds up to 15. To add a color, pick it on the wheel and tap the dashed + without a selected swatch. To replace any swatch (including a default), tap it first, pick the new color on the wheel, then tap +. A dashed outline marks the replacement slot. Switch tabs or reopen the scene editor to clear that selection. A full palette never overwrites a color automatically. In Solid color, this works even without a connected strip.

## Limits

- The controller reports nothing back: the app shows what it last sent, not the strip's real state.
- Page scenes and the off timer run only while this page is open and in front; the strip has no timer of its own. If the page closes, the strip stays on with its last color.
- Commands sent: power, brightness, whole-strip color, built-in effect, speed, and voice mode (1–4). The page does not capture or stream audio.
- Commands are spaced 50 ms apart (the strip follows changes down to ~35 ms, see `docs/CAPABILITIES.md`); the scene step interval starts at 150 ms, and fade scenes send intermediate colors about every 50 ms.
- No per-LED control is known for this controller.

## Privacy and errors

The app loads static files from its host and makes no application network requests after loading. It asks Chrome to show the Bluetooth chooser only on Connect; Reconnect can reuse the chosen strip. Disconnect is available on Home. The app does not access your location, phone microphone, notifications, or accounts. Music modes use the strip’s microphone. The foreground off timer may use Screen Wake Lock; it still runs in the foreground if wake lock is unavailable or denied.

Settings stay in this browser’s local storage. The keys all start with `deleluz.webapp.`: `state`, `shortcuts`, `sequences`, `quickOpen`, `palette`, and `language`. If `palette` is missing, the app combines the defaults with the colors from a valid legacy `customColors` list, without duplicates and up to the 15-color limit. The first palette edit saves the new list. Unreadable or invalid saved settings fall back to safe defaults. Command, connection, and save failures show a short localized message, not the browser’s raw error. A storage failure does not block strip commands. Simulation logs command bytes only, not device identifiers.

## Tests

```sh
node --test webapp/ lab/web/
```
