# DeleLuz plan after v1.0.0

Analysis of the owner's 2026-11-25 requests, checked against the code, the docs and screenshots. Each claim is labelled: **verified** (seen in code, docs or a capture), **inference** (reasoned from evidence; the check that would verify it is named), **unknown**.

North star: a small, efficient, safe suite to control LEDDMX-03 strips from any device. Less is more, done well. Each phase ships and is tested before the next starts.

## Requests (verbatim, 2026-11-25)

> - como se selecciona el color blanco ? algun otro color nos falta, algun selector de gama o algo?
> - no se pueden crear escenas con efectos de los que ya trae ?
> - verifica el repoharness, las skills dejalas mit si no están, todo es mit.
> - en efectos integrados en el modo auto me gustaria que se muestre el nombre del efecto que está corriendo y el poder cambiar el tiempo que dura cada efecto no solo la velocidad del efecto mismo, bueno no sé si se puede esto ultimo. hay que revisar.
> - falta favoritos para los efectos incluidos aunq el acciones rapidas lo hace mas o menos algo asi
> - quiero todo lo que hicimos en el app en el webapp, es decir que el webapp sea como es el app ahora mismo y quiero crear las vista/version para:  web, tablet, diferentes tamaños, un dashboard para la casa tmb
> - hay que revisar e ir viendo para probar con esp32, pero primero con arduino o raspberry pi 3b+ si se puede antes mientras compro esp32 (sugerir cual comprar en amazon y en cr costa rica)
> - revisar y la posibilidad de integrar compatibilidad con alexa y google, obviamente en dispositivos fijos que controlen los leds, como raspberry, esp32, etc
> - revisar la posibilidad de conectar a mas de 1 tira led a la vez, crear grupos y que se puyeda cambiar todas a las vez modo sync que todas cambian a lo mismo.
> - al final final lo que quiero lograr es una suite completa para poder administrar, conectar, usar, configurar, automatizar, integrar los leds a cualquier cosa, desde cualquier dispositivo, asistente, etc, ia, casaos, etc
> - la ventada del temporizador se podría mejorar tmb

The MIT request is done: the three repo-harness skills, their runtime copies and `.repo-harness/manifest.json` say MIT, and `.repo-harness/check.py` reports `current`.

## Findings

| Topic | Today | What is possible |
|---|---|---|
| White and saturation | **Verified.** White comes only from the quick scenes "Blanco cálido" and "Blanco frío". The hue wheel fixes saturation and value at 100 % (`app/lib/ui/color/color_screen.dart:190-193`), so it cannot reach white, pastels or soft tones. White is sent as RGB. | **Verified** that the strip takes any RGB value. **Unknown:** whether there is a separate white channel or a color-temperature command; nothing is documented. |
| Scenes with built-in effects | **Verified.** A scene stores only 1-8 RGB colors, the brightness and one interval (`app/lib/model/models.dart:421-432`). | **Inference.** An "effect" step type (ID plus duration) fits, because the app can already send any effect ID (`app/lib/protocol.dart`). |
| AUTO: effect name and duration | **Verified.** AUTO sends ID `FF` once. The strip never notifies its state: FFE1 sends nothing, and FFE2 has no descriptor to turn notifications on (`docs/PROTOCOL.md` GATT table). No command for per-effect duration is known. | **Inference.** An app-driven AUTO can send effect IDs on a timer, show the current name and use its own duration per effect, separate from the effect speed. It only runs while the app is open and connected. |
| Effect favorites | **Verified.** Favorites store colors only. Quick scenes take colors and scenes, not effects. The 210 effects are browsed with a number stepper, with no list and no search. | Add a star on effects, a searchable effect list, and effects as quick-scene targets. |
| Off timer | **Verified.** A generic dialog. No countdown is shown, custom time is typed in two text fields, and the only action is "off". At 320-360 px wide the webapp sheet title is cut to "Temporizador de ap…". | Countdown ring, add-time and cancel buttons, end time ("se apaga a las 23:15"), the last-used duration as default, no truncation. A strip-side timer stays **unknown** (`0x10` is unconfirmed). |
| Several strips | **Verified.** Android remembers several strips, but `Link` holds one connection (`app/lib/link.dart:56-57`). There are no groups. | **Inference.** Android usually allows about 7 GATT links (`BTA_GATTC_CONN_MAX`), so fan-out to 2-4 strips is plausible. "Same state" is achievable; frame-exact sync of animations is **unknown**. Test 2 strips first and measure skew. |
| Webapp vs app | **Verified.** The webapp has the 4 tabs and the main controls. Missing compared with Android: named strip list, strip picker and search, per-strip settings, About. Layout is a fixed 480 px column (`webapp/style.css:19`). On tablet and desktop the column floats in empty space while the bottom bar spans the full width. | Responsive layouts: two panes on tablet, a dashboard grid on desktop or a wall tablet. **Constraint (verified):** Web Bluetooth works in Chrome for Android; the Windows Bluetooth stack fails GATT discovery. A PC dashboard therefore needs a hub (below). |

### Frontend review (2026-11-25)

Checked at 320, 360, 412, 768, 1024, 1366 and 1920 px wide with device emulation, plus the Android captures in `docs/app-screens/`.

- **Verified:** no horizontal overflow at any width. The tabs, cards and sliders are aligned, and their spacing is consistent.
- **Verified:** the timer sheet title is truncated at 320 and 360 px.
- **Verified:** on tablet and desktop the 480 px column wastes most of the screen, and the full-width bottom bar does not line up with the column.
- **Verified:** picking 1 of 210 effects with a number stepper is slow to browse.
- **Unknown:** whether bottom cards are hidden behind the bottom bar at 320×568. Full-page captures with a fixed bar cannot tell; check by scrolling on a real 320 px viewport.

## Hardware and integrations

- **Raspberry Pi 3B+, start here:** built-in Bluetooth 4.2 (Cypress CYW43438). Linux BlueZ already connects to this strip (`docs/repo-harness/current-state.md`). Python with `bleak` can replay the protocol. A 2019 test held about 7 stable BLE links (DevelopersIO, "Raspberry Pi 3B+ Maximum BLE Connections").
- **Arduino:** the Uno and Nano classic boards have no Bluetooth. The UNO R4 WiFi (an ESP32-S3 inside) supports ArduinoBLE central mode, but it cannot use Wi-Fi and Bluetooth at the same time (Arduino UNO R4 WiFi manual). Not recommended for a hub.
- **ESP32 to buy:** an ESP32-S3-DevKitC-1 N16R8 (dual core, BLE 5, Wi-Fi and BLE together). A classic ESP32-WROOM-32 also works. Avoid the ESP32-S2: it has no Bluetooth. Prices seen 2026-11-25 change often:
  - Amazon: several brands at about €16-18 per board, also sold in packs of 3.
  - Costa Rica, bmlogics.com: S3 N16R8 at $16.25 with IVA.
  - Costa Rica, CRCibernética: classic ESP32 at $14.95 + IVA; its S3 was sold out.
  - Costa Rica, Electro CR: WROOM-32 or S3 at ₡8 500.
- **Alexa and Google:** the realistic path is hub → Home Assistant light entity → Matter bridge → Alexa and Google. The existing HA integrations for similar strips (ELK-BLEDOM, `7E…EF` frames) use a different protocol than the LEDDMX-03 (`7B…BF`), so DeleLuz likely needs its own small integration. Verify by testing elkbledom against the strip. An ESP32 that is itself a Matter light is possible, but it is more work.

## Phases

Each phase gets its own ODD task document when it starts.

1. **App polish** (Android only; the webapp follows once the Android app is complete and tested): saturation and white tones in Color; an effect list with search and favorites, with effects allowed in quick scenes; effect steps in "Mis escenas"; app-driven AUTO with the effect name and per-effect duration; timer sheet redesign.
2. **Two-strip spike, then groups:** open 2 links from Android, fan out one command, log the skew and reconnects. Build groups only if this holds up.
3. **Webapp parity and responsive layouts:** port phase 1, add the strip list, then the tablet layout, the desktop layout and a home dashboard. Check every width with screenshots.
4. **Hub spike on the Pi 3B+:** a Python service that talks BLE to the strips and serves a small local HTTP API (local network only, no cloud). Then move it to the ESP32-S3.
5. **Integrations on the hub:** Home Assistant, a Matter bridge for Alexa and Google, an MCP or tool API for AI assistants, and a CasaOS/Docker package.

## Open questions

- Do 2 Android links to 2 strips hold steady, and how much skew is visible?
- Can the vendor app's grouping be captured, to see whether it uses a sync command?
- Is there a color-temperature or white-channel command? Look in the vendor APK notes (`odd/tasks/device-research.md`).
- Does the elkbledom HA integration control this strip at all?
