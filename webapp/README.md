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

- **Home**: power, brightness, White / Warm white, quick scenes, off timer (clock icon). Quick scenes are yours: up to 6 colors or included scenes (default warm white, cool white, blue, green, yellow, red); tap to apply, press and hold for options (change, move, remove), hold and drag to reorder, + to add. Saved in this browser only.
- **Color**: hue wheel and quick colors; built-in controller effects 1–210 with their vendor names, or Auto cycle, with speed; four Music modes that react to sound through the strip’s own microphone.
- **Scenes**: preview included page scenes and built-in effects before applying. In **Mis escenas** (My scenes), create up to 12 sequences with 1–8 color squares each, then set the speed and intensity. Sequences are saved in this browser only. Playback shows one color at a time across the whole strip and requires this page to stay open and in front. Stopping leaves the last color on the strip.
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
