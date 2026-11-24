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

- **Home**: power, brightness, White / Warm white, quick scenes, off timer (clock icon).
- **Color**: hue wheel and quick colors; built-in controller effects 1–210 or Auto cycle, with speed.
- **Scenes**: included page scenes and built-in effects with a preview before applying; **Mine** saves the current color or page scene (with its step interval) under a name in this browser only. Brightness and built-in effects are not saved.
- **Help**: connection state, Reconnect, and fixes by symptom.

## Limits

- The controller reports nothing back: the app shows what it last sent, not the strip's real state.
- Page scenes and the off timer run only while this page is open and in front; the strip has no timer of its own. If the page closes, the strip stays on with its last color.
- Commands are spaced 50 ms apart (the strip follows changes down to ~35 ms, see `docs/CAPABILITIES.md`); the scene step interval starts at 150 ms, and fade scenes send intermediate colors about every 50 ms.
- No per-LED control is known for this controller.

## Tests

```sh
node --test webapp/ lab/web/
```
