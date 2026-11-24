# DeleLuz webapp

End-user phone webapp (Web Bluetooth, Android Chrome) for the LEDDMX-03-03C1 strip, built from `lab/web`. Mockup first, then code.
Worktree `<workspace>/deleluz-app`, branch `feat/app` (another agent works on `main`).

## Specs

- S1 — Work in a worktree: "quiza mejor en worktree xq tengo otro agente en main".
- S2 — Design base: "Thumb First + agregados (recomendado)": large power control, brightness near the thumb, one-tap white; plus scene preview before apply (Scene Gallery), symptom help + Reconnect (Soft Friendly), simple off timer (Glass Premium).
- S3 — Visual style: "Neón/glass como las referencias" (`.ld9/design-refs/otros/`).
- S4 — V1 scope: "Escenas/modos de la página", "Temporizador de apagado", "Ayuda por síntoma + Reconectar", "Escenas propias guardadas".
- S5 — Order: "Mockup primero, luego código".
- S7 — Language: "y hay que agregar idioma español y por defecto en español."
- S6 — Truthful to device limits (docs/CAPABILITIES.md): no state read-back, no per-pixel, page-sequenced modes and timer only run while the page is open; no music sync, no groups in V1.
- S8 — "R4-003: si falla guardar en localStorage, no debería impedir apagar la tira."
- S9 — "R3-004: los pasos atrasados de una escena salen cada 50 ms si el teléfono despierta tarde."
- S10 — "En pantallas bajas (360x640, 390x700) el control de brillo de Inicio queda bajo la barra de navegación (L19)."
- S11 — "Main tiene hallazgos nuevos que la webapp no usa todavía: modos de voz por micrófono 1-4 confirmados por BLE (docs/PROTOCOL.md, odd/tasks/led-lab.md L53-L54)."
- S13 — Effect names: agent proposal "Nombres de los efectos en la webapp. Hoy la pantalla dice 'Sus nombres aún no se conocen', pero ya los tenemos (210, de la app oficial)"; user: "dale dale".
- S15 — "sin conexion, en escenas al aplicar alguna escena no avisa que no está conectado, como en las otras cosas que si lo hace."
- S16 — "me parece que falta las opciones de configuracion del chip. cuantos leds por metro y de cuantos metros es la tira."
- S17 — "en lugar de escenas rapidas quiza shortcuts o con ese mismo nombre escenas rapidas, pero que el usuario pueda poner las que quiere o quitarlas y que se acomode segun la cantidad. por defecto blanco calido, blanco frio, azul, verde, amarillo y rojo, pero que permita, borrarlas, reordenarlas, o camiarlas de posicion, de preferencia arrastrando, y dejar precionado para tener el menu de opciones tmb. maximo 6."
- S18 — "una pestaña para \"Mis Escenas\"  y no s´´e, dame ideas usa gentle design quiza o stich o algo para ver que usamos de ui para eso"; sequences as described in L37 ("cuadritos cada cuadro es un color y se tocan para cambiar el color ... solo se puede cambiar la velocidad e intensidad").
- S19 — "bueno primero no respetan el layout y diseño actual que tenemos, pero dejando eso de lado, galeria + hoja se ve bien"
- S20 — "el botón de nueva escena no me convence, cuando no hay escenas y quiero una opcion de un + para agregar, quiza en una equina o siembre abao o no sé"
- S21 — "velocidad no está bien representado, los ms no deberia ser, mejor un 10% y ya, menor porcentaje mas lento mayor porcentaje mas rápido, hay minimo y maximo para el 0% y 100%."
- S22 — "las escenas de mis escenas se deben poder selecionar en las escenas rapidas del inicio"
- S23 — "las escenas por defecto de escenas rapidas deberias poder vovlerse a agregar, en menu que sale al hacer nuevo shortcut deberia salir escenas (con las predefinidas de primeras y separadas con una ligera linea), color, y que se puedan cerrar y abrir (como dropbox o combo box o minimizar o ya tu sabes.)"
- S24 — "en mis escenas si le doy a nueva escena y no toqué nada y cierro, se crea la escena de todos modos, entonces mejor quier un botón de guardar"
- S25 — "en mis escenas deberia poder activarse la escena con solo tocarla, y si quiero editarla o borrarla que aparesca el menu o lo que sea al dejar apretado y un icono de borrar a la izq de la equiz y que pida combrobación, seria nice"
- S27 — "en secuencias rápidas todo debe estar minimizado es decir contraido ambos , no solo colores"
- S28 — "cuando escenas rapidas está contraido que aparezca el control de velocidad abajo e igual que el de brillo."
- S29 — "cuando está el ciclo automatico activo, el numero de efecto deberia decir todos o ponerse gris que se yo. que indique que está el auto activo."
- S30 — "en la seccion color, el brillo deberia estar arriba de velocidad, y qtuiza pasar al modo musica en una pestaña mas en escenas quiza mejor"
- S31 — "en mis escenas cuando estoy haciendo o editando una, el selector de color, la forma en que se escoge el color no deberia ser mejor como lo que muestra la seccion Color ? es decir un circulo. y otro color deberia ser un circulo más en donde están los colores en circulo linea punteada con un más algo asi no ? y poder guardar unos 4 más, el ultimo se sobreescribe si ya están los 4. el botón de agregar cuadro no me gusta y deberia decir agregar color, pero igual no me gusta del otodo asi como está."
- S32 — "de momento todo va de maravilla al final hay que revisar, que pasa cuando se borra algo que está activo, que pasa si hay error, logs, manejo de errores, seguridad, permisos si es que necesita que estén claros y transparentes."
- S12 — "frontend debes revisar con tus herramientas, alineamientos, saltos raros en la pagina, orden, margenes, espacios, nada encima o pegado de otra cosa, simetrico y alineado, agradable a la vista, que se lea y se vea bien, contraste, letra, que funcione en cualquier pantalla y sobre todo que revises." Also: "Nada de rutas ni datos personales en archivos o commits: usa placeholders." "Español neutro con \"tú\" en la interfaz."

## Tasks

- T1 — S2,S3,S4,S6 — mockup `design/deleluz-webapp/` — inline — done (see L5)
- T2 — S5 — user approves one mockup direction — human — done: 01 Glow Glass (L6)
- T3 — S2,S3,S6 — `webapp/` shell: connect/reconnect/simulate, throttled latest-wins sender, Home (power, brightness, White/Warm white, quick scenes), Color (wheel, swatches, built-in effects + speed) — inline — done (L7)
- T4 — S2,S4,S6 — Scenes: included page modes from `lab/web/presets.js` + built-in effects, preview sheet (Try on strip / Apply / step interval), Mine saved in localStorage — inline — done (L8)
- T5 — S4,S6 — Off timer sheet (15/30/60/120 min, fade out, page-only notice) — inline — done (L8)
- T6 — S2,S4,S6 — Help: connection-lost banner, Reconnect, symptom accordion — inline — done (L8)
- T7 — S2,S6 — Smooth page scenes: interpolate fade presets (Christmas moving, Christmas glow, Siren, Rasta) at the 50 ms send gap, same cycle duration; Police/Flashing stay hard cuts — worker — done (L19)
- T8 — S2 — Home fits short screens: smaller power circle and tighter spacing so Brightness is reachable without scrolling on common phones — worker — done (L19)
- T9 — S4 — Off timer custom duration (minutes) besides 15/30/60/120 — worker — done (L19)
- T10 — S5 — Dev server without browser caching (`webapp/serve.py`), README updated — worker — done (L18)

- T11 — S7 — Spanish UI, Spanish by default, English selectable — worker — done (L26)
- T12 — S8 — Saving state to localStorage never blocks sending power-off (or any strip command) — worker — done 0094dce (L29)
- T13 — S9 — Scene player: after a late wake-up, resume at the current step instead of bursting overdue steps — worker — done 0b4bb61 (L29)
- T14 — S11,S12 — Voice modes 1-4 (onboard mic): `voiceMode` builder in `lab/web/protocol.js` + test; small Color-tab section with 4 buttons, link guard, es/en strings, README limits — worker — done af10563 (L29); real strip OK (L30)
- T15 — S10,S12 — Home Brightness reachable above the nav on short screens (320x568, 360x640, 390x700) without breaking 411x778/412x915; visual audit 320-412 px — worker + parent check — done (L29)
- T16 — S13,S12 — Effect names 1-210 in Color → Efectos integrados and in the scenes list; Home keeps the short 'Efecto N' — inline — done (L32)
- T21 — S15 — Scene Try/Apply while disconnected closes the sheet and shows the same top toast as other actions — inline — done (L35)
- T22 — S17,S12,S7 — Customizable quick scenes (max 6, defaults, add/change/remove, drag to reorder, long-press menu, layout by count) — inline (worker failed: provider_unavailable) — done (L36)
- T23 — S16 — Strip configuration (LEDs per meter × meters = pixel count) — blocked: needs a dedicated reversible test of the config frame on the real strip (docs/PROTOCOL.md rule) — pending
- T24 — S18,S12,S7 — Design directions for a 'Mis Escenas' tab of color-square sequences, as gentle-design artboards in `design/deleluz-sequences/` matching Glow Glass — worker — done (L38); user choice pending
- T25 — S18,S19,S12,S7,S6 — 'Mis escenas' (Galería + hoja) in the real webapp with the existing Glow Glass components and layout: Escenas tab gets the existing segmented control 'Incluidas | Mis escenas'; grid of sequence cards; bottom sheet editor with color squares, Velocidad, Intensidad, Reproducir/Detener — worker — done (L40)
- T26 — S20-S25,S12,S7 — Mis escenas and quick-scene chooser refinements — worker — done (L41)
- T29 — S27-S31,S12,S7 — UI refinements: chooser sections collapsed, Home speed card when quick scenes are collapsed, AUTO state on the effect number, Color: brightness above speed, Música as an Escenas segment, editor color picker = wheel + swatches + dashed "+" custom circle with 4 saved custom colors, better "Agregar color" control — worker — pending
- T30 — S32 — Final review: deleting active items, error handling, logs, security, permissions transparency — parent — pending
- L43 — User feedback after T27/T28 (S27-S32): "de momento todo va de maravilla". Planned T29 (worker) and T30 (final review).
