# App polish (phase 1, roadmap RH-W-0001)

Phase 1 of `docs/PLAN.md`: white tones and saturation, effect list with search and favorites, effects in scenes and quick scenes, app-driven AUTO, timer redesign. Android first, then the same in `webapp/`. Designs are approved before code.

## Specs

- S1 (white and gamut): "como se selecciona el color blanco ? algun otro color nos falta, algun selector de gama o algo?"
- S2 (effects in scenes): "no se pueden crear escenas con efectos de los que ya trae ?"
- S3 (app-driven AUTO): "en efectos integrados en el modo auto me gustaria que se muestre el nombre del efecto que está corriendo y el poder cambiar el tiempo que dura cada efecto no solo la velocidad del efecto mismo, bueno no sé si se puede esto ultimo. hay que revisar."
- S4 (effect favorites): "falta favoritos para los efectos incluidos aunq el acciones rapidas lo hace mas o menos algo asi"
- S5 (timer): "la ventada del temporizador se podría mejorar tmb"
- S6 (design proposals first): "me gusta la fase 1, si pero tienes ideas de diseños o cosas que mostrarme propuestas en design o stitch ?"
- S7 (quality bar): "no asumas, no creas, mejor comprueba ... sin sobreingenieria ... menos es más, pero bien hecho ... no usar rutas ni datos personales ... frontend debes revisar con tus herramientas, alineamientos, saltos raros en la pagina, orden, margenes, espacios, nada encima o pegado de otra cosa, simetrico y alineado, agradable a la vista, que se lea y se vea bien, contraste, letra, que funcione en cualquier pantalla"

Constraints (verified, see `docs/PLAN.md`): the strip never reports which effect is running; no per-effect duration command exists; app-driven AUTO works only while the app is open and connected; white is plain RGB.

## Tasks

- T1 [S6, S1-S5, S7] Design proposals in `design/deleluz-phase1/`; owner picks the directions. Route: worker. Commit: -
- T2 [S1] Color: saturation and white tones (Android). Route: TBD after T1. Commit: -
- T3 [S4] Effect list with search and favorites; effects as quick-scene targets (Android). Commit: -
- T4 [S2] Effect steps in "Mis escenas" (Android). Commit: -
- T5 [S3] App-driven AUTO: current effect name, per-effect duration (Android). Commit: -
- T6 [S5] Timer sheet redesign (Android). Commit: -
- T7 [S1-S5] Port T2-T6 to `webapp/`. Commit: -

## Log

- L1 (2026-11-25, owner, verbatim): see S1-S5 and S7 (the full request list is quoted in `docs/PLAN.md`).
- L2 (2026-11-25, owner, verbatim): "me gusta la fase 1, si pero tienes ideas de diseños o cosas que mostrarme propuestas en design o stitch ?"
- L3 (2026-11-25): T1 delivered `design/deleluz-phase1/` with 7 artboards (01-color-anillo-saturacion, 02-color-disco-blancos, 03-efectos-lista-buscar, 04-efectos-favoritos-reproductor, 05-escena-pasos-efecto, 06-temporizador-anillo, 07-temporizador-rueda). Checked at 390x844 and 320x640 with device emulation: no overflow, clipping or overlap; fixed the "Apagado gradual" switch in 06/07. Waiting for the owner to choose.
- L4 (2026-11-25, owner, verbatim): "color el 02 / efectos el 03 pero sin los favoritos en card, pára eso la estrella de la lista y que se pongan de primero los favoritos quizá. / escenas 05 me gusta, no veo como se escogen los colores o efectos pero va bien. / temprizador el 01 mientras se puedan poner segundos en personalizaod genial."
- L5 (2026-11-25, decision): chosen artboards: Color 02-color-disco-blancos; Effects 03-efectos-lista-buscar without the Todos/Favoritos chips (favorites marked with the star and listed first); Scenes 05-escena-pasos-efecto, plus showing how a color or an effect is picked; Timer 06-temporizador-anillo ("el 01" read as the first timer option), with minutes and seconds in Personalizado. Others are alternatives.
