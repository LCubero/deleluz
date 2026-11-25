# App polish (phase 1, roadmap RH-W-0001)

Phase 1 of `docs/PLAN.md`: white tones and saturation, effect list with search and favorites, effects in scenes and quick scenes, app-driven AUTO, timer redesign. Android only. The webapp is ported later, once the Android app has everything the owner wants and is tested (L15). Designs are approved before code.

## Specs

- S1 (white and gamut): "como se selecciona el color blanco ? algun otro color nos falta, algun selector de gama o algo?"
- S2 (effects in scenes): "no se pueden crear escenas con efectos de los que ya trae ?"
- S3 (app-driven AUTO): "en efectos integrados en el modo auto me gustaria que se muestre el nombre del efecto que está corriendo y el poder cambiar el tiempo que dura cada efecto no solo la velocidad del efecto mismo, bueno no sé si se puede esto ultimo. hay que revisar."
- S4 (effect favorites): "falta favoritos para los efectos incluidos aunq el acciones rapidas lo hace mas o menos algo asi"
- S5 (timer): "la ventada del temporizador se podría mejorar tmb"
- S6 (design proposals first): "me gusta la fase 1, si pero tienes ideas de diseños o cosas que mostrarme propuestas en design o stitch ?"
- S7 (quality bar): "no asumas, no creas, mejor comprueba ... sin sobreingenieria ... menos es más, pero bien hecho ... no usar rutas ni datos personales ... frontend debes revisar con tus herramientas, alineamientos, saltos raros en la pagina, orden, margenes, espacios, nada encima o pegado de otra cosa, simetrico y alineado, agradable a la vista, que se lea y se vea bien, contraste, letra, que funcione en cualquier pantalla"

- S8 (quick actions): "En escenas rápidas mejor llamarlo acciones rápidas y poder elegir los efectos integrados tmb."
- S9 (quick actions add menu): "Ver si se puede Mejorar el menú de acciones rápidas al agregar, que se vea mejor y más fácil los colores y selector, las escenas etc, y separar mis escenas de escenas"
- S10 (home link): "Quitar el  link y texto "todas las escenas" de inicio."
- S11 (Bluetooth off notice): "El mensaje de que encienda el bluetooth debería ser más vistoso y notarse más que hace falta encender el bluetooth"

Constraints (verified, see `docs/PLAN.md`): the strip never reports which effect is running; no per-effect duration command exists; app-driven AUTO works only while the app is open and connected; white is plain RGB.

## Tasks

- T1 [S6, S1-S5, S7] Design proposals in `design/deleluz-phase1/`; owner picks the directions. Route: worker. Commit: b1e9cdb, d50a60e [x]
- T2 [S1] Color: saturation and white tones (Android). Route: worker. Commit: ad070b5 [x]
- T3 [S4] Effect list with search and favorites, favorites first (Android, Color → Efectos integrados). Route: worker. Commit: 22a0c70 [x]
- T4 [S2] Effect steps in "Mis escenas" (Android). Route: worker. Risk: item 1 (stored scene format). Commit: 64b5b8b, da46e3c [x]
- T5 [S3] App-driven AUTO: current effect name, per-effect duration (Android). Route: worker. Commit: 4546165 [x]
- T6 [S5] Timer sheet redesign (Android). Route: worker. Commit: 0257279 [x]
- T8 [S9, S11] Design proposals: quick-actions add sheet (Colores / Efectos / Escenas / Mis escenas) and a prominent Bluetooth-off notice. Route: worker. Commit: 9fb0105 [x]
- T9 [S8, S9, S10] Quick actions (Android): rename to "Acciones rápidas", built-in effects as targets, new add sheet, remove "Todas las escenas" from Inicio. After T3 and T8. Commit: -
- T10 [S11] Prominent Bluetooth-off notice (Android). After T8. Commit: -
- T7a [S1, S3, S4, S7] Webapp: color disc + whites, effect list with favorites, app-driven AUTO. Route: worker + parent visual check. Commit: 2fbcecb [x]
- T7b [S2, S5, S7] Webapp: scene steps (stored-format change, backward compatible) and timer sheet. Commit: -
- T7c [S8-S11] Webapp: quick actions and Bluetooth notice, after T9/T10. Commit: -

## Log

- L1 (2026-11-25, owner, verbatim): see S1-S5 and S7 (the full request list is quoted in `docs/PLAN.md`).
- L2 (2026-11-25, owner, verbatim): "me gusta la fase 1, si pero tienes ideas de diseños o cosas que mostrarme propuestas en design o stitch ?"
- L3 (2026-11-25): T1 delivered `design/deleluz-phase1/` with 7 artboards (01-color-anillo-saturacion, 02-color-disco-blancos, 03-efectos-lista-buscar, 04-efectos-favoritos-reproductor, 05-escena-pasos-efecto, 06-temporizador-anillo, 07-temporizador-rueda). Checked at 390x844 and 320x640 with device emulation: no overflow, clipping or overlap; fixed the "Apagado gradual" switch in 06/07. Waiting for the owner to choose.
- L4 (2026-11-25, owner, verbatim): "color el 02 / efectos el 03 pero sin los favoritos en card, pára eso la estrella de la lista y que se pongan de primero los favoritos quizá. / escenas 05 me gusta, no veo como se escogen los colores o efectos pero va bien. / temprizador el 01 mientras se puedan poner segundos en personalizaod genial."
- L5 (2026-11-25, decision): chosen artboards: Color 02-color-disco-blancos; Effects 03-efectos-lista-buscar without the Todos/Favoritos chips (favorites marked with the star and listed first); Scenes 05-escena-pasos-efecto, plus showing how a color or an effect is picked; Timer 06-temporizador-anillo ("el 01" read as the first timer option), with minutes and seconds in Personalizado. Others are alternatives.
- L6 (2026-11-25): T2 done: color disc + Cálido/Neutro/Frío whites; flutter test 150/150, analyze clean; native assess not due. Slice boundary: branch passed ~400 authored lines at ad070b5.
- L7 (2026-11-25, owner, verbatim): "- En escenas rápidas mejor llamarlo acciones rápidas y poder elegir los efectos integrados tmb. - Ver si se puede Mejorar el menú de acciones rápidas al agregar, que se vea mejor y más fácil los colores y selector, las escenas etc, y separar mis escenas de escenas - Quitar el  link y texto \"todas las escenas\" de inicio. - El mensaje de que encienda el bluetooth debería ser más vistoso y notarse más que hace falta encender el bluetooth"
- L8 (2026-11-25): T3 done (22a0c70): flutter test 152/152, analyze clean. T8 artboards 08-11 checked at 390 and 320 px; fixed tab label crowding in 08 at 320 px. Waiting for the owner to choose 08/09 and 10/11.
- L9 (2026-11-25): T4 done (64b5b8b, da46e3c): flutter test 158/158, analyze clean. Independent verify: v1.0.0 scenes load and play unchanged; loading never rewrites storage. Native review (risk, reliability) approved, lineage review-4dc0f795da4f73fd; R3-001 refuted and pinned by a test, R3-002 test added. Left as is: >8 steps keep the first 8; shared `_integer` accepts 1.0 as before.
- L10 (2026-11-25): T5 done (4546165): flutter test 170/170, analyze clean; native assess not due. Firmware cycle relabelled "Ciclo de la tira" (still sends FF).
- L11 (2026-11-25): T6 done (0257279): flutter test 175/175, analyze clean. T7 split into T7a-T7c (webapp port).
- L12 (2026-11-25): T7a done (2fbcecb): node --test 97/97. Visual check at 412x915 and 320x640 (device emulation): no horizontal overflow or off-screen controls. Minor, left for T7b: the scroll-hint chevron overlaps content at the fold; "Efectos integrados" tab wraps to two lines at 320 px.
- L13 (2026-11-25, owner, verbatim): "pero mi rey primero concentrados en el app"
- L14 (2026-11-25): webapp work paused (T7b, T7c). T7b partial edits saved as `git stash` "T7b partial webapp work (paused: app first)". Next: T9/T10 on Android after the owner picks 08/09 and 10/11.
- L15 (2026-11-25, owner, verbatim): "esq nunca te dije que hicieramos lo web, era fase 1, y todo es para el app de android, la web lo hacemos cuando ya la app de android esté con todo como quiero y probada, lol"
- L16 (2026-11-25): scope corrected: phase 1 is Android only. T7a (2fbcecb) was out of scope; kept on the branch untouched for the later webapp phase unless the owner asks to revert it. T7b/T7c deferred to the webapp phase.
- L17 (2026-11-25, owner, verbatim): "9 y 10"
- L18 (2026-11-25, decision): quick actions use 09-acciones-rapidas-pasos (type tiles, then picker); Bluetooth-off uses 10-bluetooth-tarjeta (warning card on Inicio). 08 and 11 are alternatives.
