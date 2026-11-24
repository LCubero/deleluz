# Webapp screenshots (checkpoint 2026-11-24)

Taken on an Android phone (Chrome) over USB DevTools, fresh install, no strip connected. No simulation or Bluetooth chooser. Measured viewport: **411 × 778 CSS px** (device pixel ratio **2.625**). Scrollable pages were captured at full height using the phone renderer at the same CSS width; bottom sheets show their native viewport, with separate top and bottom views of the editor. The 21 JPEGs total **2.10 MB**. The T50 refresh used the same phone and viewport without resetting storage.

| File | Screen |
|---|---|
| [01-inicio.jpg](01-inicio.jpg) | Inicio recién instalado: sin conexión, escenas rápidas contraídas |
| [02-inicio-escenas-rapidas-abiertas.jpg](02-inicio-escenas-rapidas-abiertas.jpg) | Escenas rápidas abiertas: Blanco cálido, Blanco frío y + |
| [03-agregar-escena-rapida.jpg](03-agregar-escena-rapida.jpg) | Agregar escena rápida: ambas secciones contraídas |
| [04-agregar-escena-rapida-abierto.jpg](04-agregar-escena-rapida-abierto.jpg) | Agregar escena rápida: sección Escenas abierta |
| [05-agregar-escena-rapida-colores.jpg](05-agregar-escena-rapida-colores.jpg) | Agregar escena rápida: Colores, rueda y Favoritos |
| [06-escena-rapida-menu.jpg](06-escena-rapida-menu.jpg) | Opciones de Blanco cálido al mantener presionado |
| [08-temporizador.jpg](08-temporizador.jpg) | Hoja del temporizador de apagado, sin iniciarlo |
| [09-color-fijo.jpg](09-color-fijo.jpg) | Color fijo con Favoritos contraídos |
| [10-color-fijo-favoritos.jpg](10-color-fijo-favoritos.jpg) | Color fijo con Favoritos abiertos |
| [11-efectos-integrados.jpg](11-efectos-integrados.jpg) | Efectos integrados, ciclo automático inactivo |
| [13-escenas-incluidas.jpg](13-escenas-incluidas.jpg) | Escenas → Incluidas |
| [14-escena-incluida-menu.jpg](14-escena-incluida-menu.jpg) | Hoja de Navidad en movimiento, sin aplicar |
| [15-mis-escenas-vacio.jpg](15-mis-escenas-vacio.jpg) | Mis escenas, vacío |
| [16-mis-escenas-editor.jpg](16-mis-escenas-editor.jpg) | Editor de Navidad, arriba: nombre y colores iniciales (verde, amarillo y rojo) |
| [17-mis-escenas-editor-abajo.jpg](17-mis-escenas-editor-abajo.jpg) | Editor de Navidad, abajo: velocidad, intensidad y Guardar |
| [18-mis-escenas-con-escenas.jpg](18-mis-escenas-con-escenas.jpg) | Mis escenas con una sola escena guardada: Navidad |
| [19-musica.jpg](19-musica.jpg) | Música, modos 1–4 sin activar |
| [20-ajustes.jpg](20-ajustes.jpg) | Ajustes, todas las secciones contraídas |
| [21-ajustes-tira-total.jpg](21-ajustes-tira-total.jpg) | Ajustes → Tira: Total de LEDs, 150 editable |
| [22-ajustes-tira-por-metro.jpg](22-ajustes-tira-por-metro.jpg) | Ajustes → Tira: Por metro, 30 × 5 = 150 de solo lectura |
| [23-ajustes-idioma-ayuda-privacidad.jpg](23-ajustes-idioma-ayuda-privacidad.jpg) | Ajustes con Idioma, Ayuda y Privacidad y permisos abiertos |

**Skipped:** Tira encendida, Ciclo automático activo y envío o reproducción en la tira (sin conexión). El selector Bluetooth no se abrió. El teléfono quedó en Mis escenas; se comprobó después de recargar que solo está guardada Navidad.

**Visual review (S12):** Se reprodujeron y corrigieron los tres problemas del checkpoint: Velocidad, Brillo e Intensidad muestran un espacio inseparable antes de `%` en español y ninguno en inglés; Cerrar permanece visible al bajar en `05` y `17`; y el contorno de foco del título se ve completo en `05`. Se revisaron las 13 capturas renovadas en Android por USB: alineación, márgenes, legibilidad, contraste y ausencia de datos personales. En `17` se ve parte de los botones que salen por debajo del encabezado al desplazar; se leen completos al subir. Chrome headless con `?sim` comprobó las etiquetas y el clic en Cerrar después de desplazar a 320, 360, 390 y 412 px. A 320 px, el título largo de la hoja usa puntos suspensivos; no se recorta su contorno de foco. Navidad sigue siendo la única escena guardada.

S7: Español seleccionado por defecto (los nombres de efectos del fabricante se conservan). Las capturas también documentan S4, S13, S17–S21, S23–S24, S27–S28, S30–S31, S35–S36, S41–S50 y S52–S54 en los estados visibles, no como pruebas funcionales de cada requisito.
