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

- **Home**: power, brightness, quick scenes, off timer (clock icon). Keep up to six shortcuts to colors, included page scenes, or saved My scenes. Tap to play or apply; press and hold to change, move, or remove; hold and drag to reorder. Tap + to add a shortcut. The chooser has collapsible Scenes and Colors sections; you can re-add any of the six default colors (warm white, cool white, blue, green, yellow, red). Shortcuts are saved in this browser only; deleting a saved scene removes its shortcuts.
- **Color**: hue wheel and quick colors; built-in controller effects 1–210 with their vendor names, or Auto cycle, with speed; four Music modes that react to sound through the strip’s own microphone.
- **Scenes**: preview included page scenes and built-in effects before applying. In **Mis escenas** (My scenes), tap + to draft a scene with 1–8 color squares, speed (0% slowest, 100% fastest), and intensity. Tap a saved scene to play it; press and hold to edit it or use the trash icon and confirm deletion. Play and Stop in the editor preview the draft on the connected strip. Tap Save to keep your changes (up to 12 scenes, stored in this browser only); closing without saving discards the draft. Playback shows one color at a time across the whole strip and requires the page to stay open and in the foreground.
- **Help**: connection state, Reconnect, and fixes by symptom.

## Limits

- The controller reports nothing back: the app shows what it last sent, not the strip's real state.
- Page scenes and the off timer run only while this page is open and in front; the strip has no timer of its own. If the page closes, the strip stays on with its last color.
- Commands sent: power, brightness, whole-strip color, built-in effect, speed, and voice mode (1–4). The page does not capture or stream audio.
- Commands are spaced 50 ms apart (the strip follows changes down to ~35 ms, see `docs/CAPABILITIES.md`); the scene step interval starts at 150 ms, and fade scenes send intermediate colors about every 50 ms.
- No per-LED control is known for this controller.

## Tests

```sh
node --test webapp/ lab/web/
```
