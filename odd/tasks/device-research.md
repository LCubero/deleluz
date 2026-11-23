# Device research: LEDDMX-03 + LED LAMP app

Research the RIXME 5 m strip controller (`LEDDMX-03-03C1`) and the vendor app LED LAMP 4.3.7 over ADB,
record observed protocol facts, document the vendor UI, and propose 5 better app designs.

## Specs

- S1: "toma todas las screenshots que necesites para dejar registro como es el app" — capture every vendor app screen and keep a private index.
- S2: "y hacerla mejor darme unas 5 opciones, faciles de usar, que funcione fluido, con las cosas que quiero etc." — 5 design options covering: multiple strips as one, improved BLE (remember, forget, pairing mode), new/custom modes, BetaFPV-style per-LED color/function selection by grid and/or number.
- S3: "obten los datos que pueda todo lo que puedas por el adb sobre el app y led, como funciona que usa etc." — extract app metadata, permissions, BLE usage, and the bytes written to the device.
- S4: "docume4ntalo en .ld9 o donde creas necesario" — vendor-derived material stays private (`.ld9/`, `_private/`); protocol facts go to repo docs without personal data (no MACs, serials, user paths).

- S5: "primero quiero el diseño del app, para celular esa es la prioridad diria yo" — design the phone app first (phone-sized screens are the primary artboards).
- S6: "creame opciones para ver de lo que pienses que sea mejor combinando lo bueno de todas las opciones, que se vea bonito redondeado o uix moderna, alineado, con buenas letras, colores, sombras, bordes, transparencias, etc etc etc" — new phone directions that combine the best of option 1 and the four AI references in `.ld9/design-refs/` (GPT segmented strip ribbon, Stitch power dock and scene tiles, Claude reconnect copy and calm hierarchy, Gemini strip ruler and ± steppers), keeping option 1's five tabs.
- S7: "podriamos hacer 3 opciones de skin por el momento" — exactly 3 skins: warm, cool-technical, neutral (light color supplies the accent).
- S8: "diria que escenas y apagar y brillo, quiza hacer un botón flotante que muestra las opciones que nosotros le selecionamos (esto no es tan importante, pero nice to have)" — on Devices, scenes plus power-off and brightness sit nearest the thumb; optional floating button that opens user-chosen quick actions.

## Tasks

- T1 [S3,S4] Decode HCI log from bugreport; map writes to session-log actions → `docs/PROTOCOL.md`. route: inline. commit: —
- T2 [S1,S4] Capture all vendor app screens → `.ld9/research/ledlamp-app/`. route: inline. commit: —
- T3 [S3,S4] ADB/APK metadata: manifest, permissions, BLE UUIDs, mode list → `.ld9/research/ledlamp-app/apk.md` + facts in docs. route: inline. commit: —
- T4 [S3] `PROGRESS.md` with confirmed facts and environment. route: inline. commit: —
- T6 [S3] Windows BLE probe via tools/leddmx.py (send on/off without the 2A..AF handshake). route: inline. commit: —
- T5 [S2,S5] 5 design directions → `design/<slug>/`. First pass (desktop-leaning, `design/deleluz-app/`) superseded by L7; redo phone-first in `design/deleluz-mobile/`. route: worker. commit: —
- T7 [S5,S6,S7,S8] v3: 3 combined phone directions, one skin each → `design/deleluz-mobile-v3/`. route: 3 parallel writers (one artboard each). Done: 01-ember, 02-graphite, 03-prism written and screenshot-verified by each writer. commit: —

## Log

- L1: "- toma todas las screenshots que necesites para dejar registro como es el app, y hacerla mejor darme unas 5 opciones, fdaciles de usar, que funcione fluido, con las cosas que quiero etc. - obten los datos que pueda todo lo que puedas por el adb sobre el app y led, como funciona que usa etc. docume4ntalo en .ld9 o donde creas necesario"
- L2: Earlier wants: multiple strips as one; better BLE (remember, forget, pairing mode); new modes; BetaFPV-style per-LED color by grid/number; platforms web, Windows, Linux/mac first, Android/iOS last.
- L4: T1 result: protocol decoded from HCI capture into docs/PROTOCOL.md (power, RGB `07 RR GG BB 00`, brightness `01 FINE PCT 00`, effect `03 ID`, speed `02 SPD`, chip config `05 04 00 96 03`, handshake `2A..AF`). LED is conn 0x041; FEF5 belonged to another device.
- L5: T2 result: 33 screens + ui.md; 210 numbered effects + AUTO; vendor app already has device grouping (Agrupación) and phone-music color sequence. Not exercised by safety rule: login, config save, timer send, media permission. T3 result: apk.md; static candidate opcodes 0B (music/mic), 0C (sensitivity), 10 (timer), 14 (subarea, other family); Graffiti/per-pixel strings exist but no DMX03 per-pixel frame; FastBle, Baidu Push, vendor API domains.
- L6: User delegated next-step choice ("no sé dime tu"). Chosen: Windows BLE probe first. tools/leddmx.py + 4 tests GREEN. Live scan blocked: no Bluetooth adapter present on Windows (adapter unplugged).
- L7: "nonono, primero quiero el diseño del app, para celular esa es la prioridad diria yo" — layout-fix worker cancelled; designs redone phone-first.
- L8: Parent review of design/deleluz-mobile/ REJECTED: the 5 directions are one template recolored (same screens, copy, layout); effects list shows only AUTO; pixel grid is not strip-like; tab bar has no icons; effects card touches the action bar in 03. Redo with web research of similar apps (user request: "busque en internet apps similares y que se inspire en el diseño, que lo quiero con buena calidad de vida para el usuario, facil y con todas las herramientas posibles").
- L9: v2 reviewed by parent at 1440: 5 distinct architectures (tabs / strip-first no tabs / scene tiles + sheets / timeline studio / power-dial remote), real effect list, serpentine 150-LED ribbon. Remaining defects: checkboxes split from their labels (02-05), filter chips and button rows spread with uneven gaps (02-05), 01 strip rows outside card padding, sheet screens in 03 show empty backdrop, large empty areas. Plan: user picks a direction, then one polish pass on that one only. Web research was unavailable to the worker (patterns from prior knowledge).
- L10: "de esas que pasaste la 1 es como la unica mejor pero no me gusta del todo. la veo muy ia, no sé." User will bring design options from other AIs; drop location `.ld9/design-refs/<ai-name>/`.
- L11: Explorer review of `.ld9/design-refs/` (GPT, Stitch, claude, gemini): keep option 1's tabs; borrow GPT ribbon, Stitch dock/scene tiles, Claude reconnect copy ("Reconnecting… attempt 2 of 5" vs failure with Retry), Gemini ruler/± steppers. Mockups number "Forward Run 7 Colors" as 042; our transcription says 95: never import effect IDs from mockups. User answers to style questions are S6-S8 (verbatim).
- L3: Session 1 observed: power toggle x4, red/green/blue/white swatches, brightness max/mid/min all matched on the strip. Chip settings: GRB, 150 px (range 0-1024).
