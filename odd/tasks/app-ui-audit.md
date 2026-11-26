# App UI audit (Android, before T21 screenshots)

Visual and UX audit of the Android app (`app/`) before the 1.1.0 screenshots (app-polish T21). Android only; no strip or phone test until the owner says the app is visually right.
Branch `feat/ui-polish-2`. Standard: `design/system.md` and the `deleluz-design-rules` skill.

## Specs

- S1 (general audit): "antes hay que revisar la ui o uix o lo que sea, la interfeaz en generaral, que no tenga consas mal puestas, que se vea alineado congrueste, etc tyodo lo que debes investigar y anotar de front end."
- S2 (skill): "actualizar la skill"
- S3 (scope): "revisar el app siempre en el app de momento."
- S4 (scene tabs check): "hay cosas como el check de las tabs de escenas, (incuidas, mis escenas, musica) que salen mal"
- S5 (app-driven scenes): "ademas esas escenas no son del todas incluida, hay que avisar cuales funcionan solo con el el app abierta y conectada."
- S6 (no strip yet): "no voy a conectar la tira aun, hasta que el app esté perffecta visualmente"

## Findings (audit L2)

- F1 Scene tabs: the check is inserted only in the selected segment (`glow_glass.dart` GlowSegments), so the label shifts, may wrap only when selected, and segments can differ in height. (S4)
- F2 Scenes "Incluidas": six presets (Navidad en movimiento, Brillo navideño, Policía, Sirena, Rasta, Destellos) are app-driven timers (need the app open and connected); Ciclo automático, Forward/Backward Dreaming are strip effects. Cards do not say which; the preview note omits "connected"; quick actions scene picker says nothing. (S5)
- F3 Selection: Music cards never show selected; Scenes "Nueva escena"/"Aplicar"/"Guardar" use plain FilledButton instead of the gradient primary button. (S1)
- F4 Layout shift: Scenes error above tabs, Scenes last-sent, Home counter, Color active-effect name are inserted without reserved space. (S1)
- F5 Strip selector action buttons: min 34 dp + shrinkWrap, below 48 dp. (S1)
- F6 Quick actions header: Back button removed on step 1 without reserving width, title moves. Scene preview uses a local strip bar instead of GlowStrip. (S1)
- F7 Localization: About tagline fixed in Spanish; effect names shown in English in Spanish locale. (S1)
- F8 Standard drift: system.md still lists white border and 44 dp for segments; slider overlay 22 vs 24 in code; no rule for reserved check space, runtime labels, truncation exceptions. (S2)

## Tasks

- T1 [S4, F1] Scene tabs: reserve check space in every segment, equal height, stable label; widget test. Route: inline. Commit: fcf6938
- T2 [S5, F2] Runtime tag on scene cards ("Necesita la app" / "En la tira") plus legend; notes in Mis escenas and quick-action scene pickers; test. Route: inline. Commit: b662d78
- T3 [S1, F3] Selection and primary buttons consistent (Music selected, gradient primary). Route: gentle-ai-worker. Commit: see L6
- T4 [S1, F4] Reserve space for changing status/notice text (Scenes, Home, Color). Route: gentle-ai-worker. Commit: see L6
- T5 [S1, F5, F6] 48 dp targets in strip selector; quick actions header alignment; preview uses GlowStrip. Route: gentle-ai-worker. Commit: see L6
- T6 [S1, F7, L5] Localize About tagline; translate effect names to Spanish in the Spanish locale. Route: inline. Commit: -
- T7 [S2, F8] Update `deleluz-design-rules` skill (canonical + runtime copies, `check.py`) and `design/system.md`. Route: inline. Commit: -
- T8 [S1, S3, S6] Full UI test suite + emulator or simulated screenshots at 320/412 dp, ES/EN, large text; no strip. Route: inline. Commit: -

## Log

- L1 (owner, 2026-11-26): "antes hay que revisar la ui o uix o lo que sea, la interfeaz en generaral, que no tenga consas mal puestas, que se vea alineado congrueste, etc tyodo lo que debes investigar y anotar de front end.

actualizar la skill
revisar el app
siempre en el app de momento.


hay cosas como el check de las tabs de escenas, (incuidas, mis escenas, musica) que salen mal, ademas esas escenas no son del todas incluida, hay que avisar cuales funcionan solo con el el app abierta y conectada.


no voy a conectar la tira aun, hasta que el app esté perffecta visualmente"
- L2 (audit, 2026-11-26): read-only explorer audit; findings F1-F8 above, evidence in code paths cited per finding. Not observed at runtime yet.
- L3 (T1, 2026-11-26): RED observed: selecting a scene tab moved its label 22 dp and at 320 dp wrapped "Incluidas" (40 -> 60 dp tall). Fix: every segment reserves the 18 dp check slot; equal-height segments; labels and check centered vertically. Changed pinned home_test rule "first line tops align" to "labels share one vertical center" (segments now equal height). Full suite 340 pass.
- L4 (T2, 2026-11-26): RED observed (no tag). Every Incluidas card shows an icon + text tag: six presets "Necesita la app", Ciclo automático / Forward / Backward Dreaming "En la tira"; legend notice above the grid; Mis escenas cards tagged and a note when scenes exist; quick-action scene pickers show the same note; preview/editor hint now says "solo con la app abierta y la tira conectada". Test helper scrolls lazily built cards/tabs into view. Full suite 342 pass.
- L5 (owner decision, 2026-11-26): effect names -> "Traducirlos al español" (Spanish names when the app is in Spanish, English when in English). Screenshots -> "Ambos" (emulator for sizes; owner's phone over USB for final confirmation, asking right before).
- L6 (T3-T5, 2026-11-26): worker mwxs0ez3-2-ety0, RED then GREEN per rule. Music cards mark last sent voice mode (session only; failed send keeps previous). Scenes new/apply/save use GlowPrimaryButton. Scenes command-failure notice floats; shared GlowStatusSlot reserves height for last-sent, Home countdown, Color now-playing (RED shifts 101/18/89 dp). Strip selector actions >=48 dp (was 44); quick actions Back slot reserved (title shifted 48 dp); preview uses GlowStrip. Full suite 348 pass (parent rerun).
- L7 (slice, 2026-11-26): review slice 1 = fcf6938..10c30cc (454 authored lines, T1-T5). T6 onward starts slice 2.
