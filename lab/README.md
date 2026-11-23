# DeleLuz LED Lab

From the repository root, serve the static files (no install or build):

```sh
python -m http.server 8000 -d lab/web
```

Open `http://localhost:8000` in Chrome. Web Bluetooth needs a secure context (HTTPS or localhost), a supported browser/platform, and a working Bluetooth adapter. On an Android phone connected over USB with USB debugging enabled, run `adb reverse tcp:8000 tcp:8000`, then open `http://localhost:8000` in phone Chrome. No Chrome flags are normally needed. Only if testing an environment where Web Bluetooth is experimental, try `chrome://flags/#enable-experimental-web-platform-features` if offered, then relaunch; this does not add Bluetooth support to an unsupported platform.

Close the vendor app if it holds the connection. Click **Connect** and select the LEDDMX controller. **Reconnect** uses the selected device after a disconnect. **Simulate device** logs the same frames without connecting and is automatic when the Web Bluetooth API is missing.

Android Chrome worked over `adb reverse` in the bench run; Windows (two USB adapters, including the TP-Link UB500 Plus) connects but fails characteristic discovery, so the lab cannot control the strip from Windows (see `docs/CAPABILITIES.md`, Windows connectivity). Android FFE1 notifications were enabled but no RX frames arrived; FFE2 did not support notifications. Judge results by watching the strip, not by waiting for an acknowledgement.

Use **Next effect** and **Previous effect** to sweep native effects. Tap **worked**, **no change**, or **unexpected** on the exact Traffic log row to record what you saw, or add a free-text observation for the latest send. Observations and saved modes are local to this browser and origin. Export JSON or Markdown before switching devices or clearing browser storage.

## Presets and limits

Tap any **Presets** button in Mode studio to start a looping whole-strip mode: Christmas moving fades through red, green, and warm white; Christmas glow breathes between red and green; Police double-flashes red and blue; Siren sweeps between red and blue; Rasta cycles green → yellow → red; Flashing strobes white. Leave **Step interval** blank for the preset default or enter a value of at least 150 ms. Static red/green Christmas and static three-band Rasta are not possible through the stock controller's known commands; try native effects for built-in multicolor patterns.

Modes are sequenced by the page, not stored on the controller. Stop cancels future steps, not a write already in flight; the strip remains in its last state. The painter is **Preview only** and sends nothing.

## Rate test

Turn on the strip, set a comfortable brightness, and stop mode playback. Enter up to six distinct intervals in the order you want to test (default: 300, 200, 150, 100, 70, 50 ms). The test sends 20 alternating red/blue frames per interval and excludes other writes while running. Watch the strip and use **Mark first skip** after stopping or completing the run to record the first interval where it did not visibly alternate. Leave this unset if you saw no skips. Rapid color alternation may be uncomfortable; stop if needed.

The log and both observation exports include browser send-attempt timestamps and measured gaps, not BLE delivery or strip-update timings. These can exceed the requested interval, especially on a busy or backgrounded phone. Keep the page in the foreground. Simulation verifies the workflow, not the strip's throughput.

## Safety

- [`docs/PROTOCOL.md`](../docs/PROTOCOL.md) is the wire-format authority. Writes go only to FFE1 under FFE0, without response. No handshake is sent automatically.
- Raw writes are experimental and opt-in. Unknown opcodes, malformed frames and chip-config or handshake variations are always rejected. Use the separate one-attempt unlock for the exact captured handshake or chip-config frame only in an explicitly approved, dedicated, reversible test. Do not replay them blindly.
- Only the Rate test may send below 150 ms; ordinary writes, including optional power-off and speed duplicates, use the normal throttle.
- A successful write is not proof of physical effect. Check the strip and record the result. Effect and speed bytes are captured; not every effect or notification is verified on hardware.

Run the frame tests with `node --test lab/web/` (Node 26).
