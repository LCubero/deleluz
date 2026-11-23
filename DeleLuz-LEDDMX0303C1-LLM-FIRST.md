# LEDDMX-03 — Brief maestro para agente CLI (LLM-first)

> **Fecha de contexto:** 2026-11-22  
> **Propietario:** usuario del dispositivo  
> **Estado:** investigación + prototipo; **NO** afirmar compatibilidad ni funciones sin pruebas sobre la unidad real.  
> **Objetivo principal:** crear una **app Android nativa, local y confiable** para controlar las luces, con conexión BLE sencilla y **modos personalizados**. Utilizar la PC Windows 11 y un agente CLI para investigar, desarrollar, automatizar y probar; una app de escritorio es opcional, **no** el objetivo inicial.

## 0. Instrucción de ejecución para el agente

Eres el agente encargado de implementar este proyecto. **Primero lee este documento completo.**

1. Examina el repositorio/directorio actual antes de crear o cambiar archivos. No sobreescribas trabajos existentes.
2. Distingue **CONFIRMADO EN LA UNIDAD**, **DOCUMENTADO EN HARDWARE SIMILAR** y **PENDIENTE DE VALIDACIÓN**. No conviertas hipótesis en hechos.
3. Haz avances **incrementales y verificables**: diagnóstico -> control básico -> conexión estable -> app Android -> modos DIY -> extras.
4. Prioriza una solución simple y mantenible, sin nube, cuentas, anuncios ni servicios externos.
5. Implementa tests para codificación de bytes y lógica de estados. Para pruebas físicas, pide al usuario solo la observación indispensable (por ejemplo, qué color apareció).
6. Conserva un `PROGRESS.md` con hechos probados, entorno, errores exactos, comandos enviados y resultados. Actualízalo al terminar cada fase.
7. No intentes actualizar firmware, hacer factory reset, escribir características desconocidas ni lanzar barridos indiscriminados de opcodes. Probar únicamente paquetes identificados y reversibles.
8. Entrega instrucciones de uso **breves**, comandos reproducibles, y al final un **APK instalable** cuando el entorno permita compilarlo. Distingue compilación de prueba real en hardware.
9. Si Windows no permite acceder a GATT, **no atasques el proyecto**: pasa a pruebas BLE desde Android controladas por ADB; Linux/BlueZ también es una alternativa.
10. Da preferencia a documentación oficial y a evidencia práctica en esta familia; antes de copiar código de terceros, revisa la licencia.

---

## 1. Contexto recuperado de esta conversación

### CONFIRMADO EN LA UNIDAD (reportado por el usuario)

- **Nombre BLE visible:** `LEDDMX-03-03C1`.
- Se conectó desde Android usando **nRF Connect**.
- Se identificaron el **servicio `0xFFE0`** y la **característica `0xFFE1`** para las pruebas BLE.
- Se introdujo y envió el paquete **`7B FF 04 01 FF FF FF FF BF`**.
- **Resultado observado:** «se puso roja el led».
- Interpretación cautelosa: se **confirmó una reacción visible** de las luces ante el envío; en los protocolos documentados este paquete es **POWER ON**, no un ajuste de color rojo. El rojo pudo ser un estado previo. **Aún NO está comprobado que un paquete RGB haya cambiado correctamente el color.**
- No se dispone del chat anterior eliminado ni de un registro completo de otras pruebas.

### Pendiente de verificar en este modelo concreto

- Qué bytes exactos utiliza para **RGB** y su orden de canales.
- Brillo, apagado, modo de efecto, velocidad y dirección.
- Si admite *pairing/bonding* BLE. **Conexión GATT no es lo mismo que emparejamiento.**
- Comportamiento al reconectar, intervalos sostenibles entre escrituras, estabilidad en segundo plano.
- Si el hardware permite **control por píxel/zona** o solamente toda la tira; no asumir pixel-art o patrones espaciales programables.
- Si las luces pueden leer/devolver el estado real (varios modelos similares no lo permiten).

---

## 2. Objetivos del producto

### MVP obligatorio

- Escanear automáticamente dispositivos BLE compatibles (`LEDDMX-...`) y elegir uno.
- Conectar con un toque, guardar el identificador local y volver a conectar de manera automática cuando sea posible.
- Mostrar estado real de la **conexión**: buscando, conectando, conectado, desconectado, recuperando, error.
- Encender/apagar; selector RGB; regulador de brillo; favoritos/presets locales, **solo después de verificar cada comando**.
- Controles responsivos sin saturar el enlace BLE.
- Desconexión limpia, botón de reconectar y mensajes útiles cuando otro cliente ocupa el dispositivo.
- Android en **Kotlin + Jetpack Compose**, BLE con APIs nativas Android (`BluetoothLeScanner`, `BluetoothGatt`).
- Arquitectura que permita cambiar el formato exacto de trama sin reescribir la UI.

### Personalización y modos (después del MVP)

- **Arcoíris:** desplazamiento continuo por matiz HSV.
- **Respiración:** variación suave de brillo.
- **Policía:** alternancia rojo/azul.
- **Fuego:** tonos cálidos pseudoaleatorios.
- **Estrobo:** destellos con frecuencia regulable y advertencia visual.
- **Creador de modos:** pasos `{color, brillo, duración, transición}`; guardar, editar, eliminar, iniciar/detener, repetir.
- **Música:** opcional; reaccionar al **micrófono del teléfono** con permiso expreso. No prometer acceso al audio interno de Spotify/u otras apps: Android puede restringirlo.
- Opcional: lista de efectos nativos y velocidad, una vez identificados sus IDs reales.

**Distinción esencial:**

1. **Efectos nativos:** un comando configura un efecto dentro del controlador; podría seguir funcionando sin teléfono.
2. **Efectos host-driven:** la app envía sucesivos colores/brillos; requieren BLE conectado y, si funcionan en segundo plano, un servicio Android apropiado. Su suavidad depende de la latencia y del firmware.
3. **Efectos por píxel:** solo si se comprueba un protocolo específico compatible; no garantizados para LEDDMX-03.

---

## 3. Protocolo BLE y paquetes de referencia

### UUID conocidos para la familia LEDDMX-00/03

```text
Servicio:       0000ffe0-0000-1000-8000-00805f9b34fb
Característica: 0000ffe1-0000-1000-8000-00805f9b34fb
Formato común:  9 bytes: 7B ... BF
```

**No confundir** con otros controladores `7E ... EF`. Examinar propiedades reales de `FFE1`: `write`, `write-without-response` u otras; elegir el tipo de escritura soportado. Los modelos similares muestran diferencias incluso entre firmwares.

| Función | Paquete (hexadecimal) | Estatus y advertencia |
|---|---|---|
| Encender | `7B FF 04 01 FF FF FF FF BF` | **Reacción visual confirmada** en esta unidad (quedó roja). |
| Apagar | `7B FF 04 00 FF FF FF FF BF` | Documentado para LEDDMX-00/03; **pendiente de prueba**. |
| RGB, variante A | `7B FF 07 RR GG BB FF FF BF` | Documentado en `aarshivv/leddmx-controller`; **pendiente**. |
| RGB, variante B | `7B FF 07 RR GG BB 00 FF BF` | Documentado en `led-ble-car`; **pendiente**. |
| RGB, orden alternativo | `7B FF 07 RR BB GG 00 FF BF` | Confirmado **en otra tira**, no en esta; **pendiente**. |
| Brillo, variante A | `7B FF 01 XX FF FF FF FF BF` | Otro proyecto LEDDMX-03; significado de `XX` indicado como 0–100; **pendiente**. |
| Brillo, variante B | `7B FF 01 FINE PCT 01 FF FF BF` | `FINE = floor(PCT*32/100)` documentado en otra implementación; **pendiente**. |
| Brillo, variante C | `7B FF 01 FINE PCT 00 FF FF BF` | Otra revisión de firmware; **pendiente**. |
| Efecto nativo | `7B FF 03 ID FF FF FF FF BF` | IDs dependen de la variante; **pendiente**. |
| Velocidad, variante A | `7B FF 02 XX FF FF FF FF BF` | Documentada en una implementación; **pendiente**. |
| Velocidad, variante B | `7B FF 02 S 00 FF FF FF BF` | Documentada en otra implementación; **pendiente**. |

**Nota:** algunos firmwares usan `03/02` para on/off, pero **nuestro candidato prioritario** es `01/00` porque el paquete `01` ya produjo respuesta. No reemplazarlo sin evidencia.

### Pruebas RGB iniciales, conservadoras

1. Reconectar, comprobar propiedades GATT y confirmar `POWER ON`.
2. Probar **una variante de RGB cada vez** y registrar su salida.
3. Usar colores primarios para verificar el orden físico:
   - Rojo: `RR=FF, GG=00, BB=00`.
   - Verde: `RR=00, GG=FF, BB=00`.
   - Azul: `RR=00, GG=00, BB=FF`.
4. Probar la variante **A** primero por su coincidencia con un proyecto probado en LEDDMX-03 y comparar con variante **B** solo si no responde. En ambas, observar verde/azul antes de fijar el orden de canales.
5. Registrar la trama exacta, método `response=True/False`, resultado y cualquier excepción; nunca marcar «funciona» basándose solo en que la API no lanzó error.
6. Si se producen colores mezclados, investigar orden `RGB`, `RBG`, etc. Una variante no comprobada no debe convertirse en predeterminada.
7. Reservar operaciones de configuración de chip/píxeles, password, reset y otros opcodes para una fase de investigación específica y autorizada.

**Ejemplos para prueba manual, variante A:**

```text
Rojo:   7B FF 07 FF 00 00 FF FF BF
Verde:  7B FF 07 00 FF 00 FF FF BF
Azul:   7B FF 07 00 00 FF FF FF BF
Apagar: 7B FF 04 00 FF FF FF FF BF
```

Las tramas anteriores son **candidatas**, no se han confirmado en este dispositivo. Tratar los espacios como presentación: enviar los 9 bytes reales, **no** la cadena ASCII.

---

## 4. BLE robusto y facilidad de conexión

### Máquina de estados recomendada

```text
IDLE -> SCANNING -> FOUND -> CONNECTING -> DISCOVERING_GATT -> READY
  ^                                 |                         |
  |                                 v                         v
  +----------------------- DISCONNECTED <----------------- LINK_LOST
                                      |
                                      v
                           BACKOFF -> SCANNING
```

- Discriminar por nombre compatible **y comprobar FFE0/FFE1**, no depender solo de un nombre que cualquiera puede anunciar.
- Cachear identificador del dispositivo seleccionado (en Android, manejar permisos y cambios en identificadores/advertisements sin asumir una MAC estable universalmente).
- Al reconectar, hacer **scan nuevo** y usar un periférico descubierto recientemente, si la plataforma lo exige.
- Política de reconexión con *backoff* y límites, por ejemplo 1, 2, 4, 8, 15 s con jitter; detener al perder permisos o desactivar Bluetooth. No lanzar infinitos scans simultáneos.
- Serializar escrituras GATT: **una en curso**, según el tipo de escritura y callbacks soportados; usar cola y **coalescing latest-wins** para sliders de color/brillo. No acumular cambios obsoletos.
- Empezar con intervalos conservadores de ~100–200 ms en animaciones; medir pérdida, retraso y estabilidad antes de acelerar. No presentar tasas específicas como garantizadas.
- Gestionar `onConnectionStateChange`, `discoverServices`, callbacks de escritura, timeouts, cerrar `BluetoothGatt` correctamente, cancelación y reconexión.
- Aplicar un único «dueño» del enlace BLE por dispositivo. Si nRF Connect o la app original están conectados, desconectarlos antes de probar desde PC.
- Mostrar qué se **envió** y qué se **observó** por separado; no inventar un «estado físico confirmado» cuando no existe read-back.

### Pairing y bonding

**No asumir que el dispositivo soporta pairing.** BLE/GATT puede funcionar sin bonding. Algunos módulos de esta familia no implementan SMP y fallan al intentar forzar emparejamiento.

- **Por defecto:** conectar mediante GATT sin pairing explícito.
- **Función opcional «Emparejar»:** mostrarla solo si se constata compatibilidad o el sistema requiere autenticación. En Android, revisar `createBond()` y las notificaciones del sistema; no suplantar diálogos de seguridad.
- **En Python Bleak:** probar `pair=True` **únicamente** en una rama diagnóstica o si se demuestra necesario. No meter `pair=True` por defecto.
- **UX preferida:** botón Conectar, guardar último dispositivo y reconectar sin pedir nada más.
- Si pairing empeora la conexión, documentar el fallo y volver a conexión BLE directa; no prometer reparar el firmware desde la app.

---

## 5. Ruta de desarrollo desde la PC Windows 11

### Fase 1: diagnosticar primero, sin construir app completa

- Comprobar adaptador BLE local, drivers, permisos y disponibilidad de Python.
- Cerrar nRF Connect, app LED LAMP y cualquier otro cliente conectado al controlador.
- Escanear con **Bleak**, imprimir `name`, `address`, advertisement/service UUIDs y RSSI disponible, con logs útiles.
- Intentar conectar y descubrir `FFE0/FFE1`, listar propiedades de la característica, luego enviar **solo POWER ON conocido**.
- Si llega a GATT correctamente, probar por separado RGB y apagado; documentar comportamiento real.
- Si hay error de GATT en Windows, no asumir que el problema es del código, ni que un pairing forzado lo solucionará.

Comandos sugeridos desde PowerShell **en la carpeta del proyecto**:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install bleak
# El agente crea primero scripts/scan_ble.py, scripts/probe_gatt.py y scripts/send_hex.py
.\.venv\Scripts\python.exe scripts/scan_ble.py
```

**Para `send_hex.py`:** validar exactamente 9 bytes, aceptar `--device`, `--hex`, `--response auto|true|false`, `--dry-run`; mostrar el paquete previo al envío; limitarse al dispositivo elegido y a la característica reconocida; errores con salida útil. No usar un script de ráfagas agresivas.

### Atención: Windows 11 puede ser un bloqueo de firmware/GATT

Dos proyectos probados en otras unidades LEDDMX-03 documentan que Windows puede **escanear y conectar pero fallar al descubrir la característica `FFE1`**; se reportó `0x8007003A` / `WinError -2147024838`. Esto **no demuestra** que ocurra en `LEDDMX-03-03C1`, pero debe verificarse temprano.

Si pasa:

1. Guardar error exacto, adaptador/driver, servicios enumerados y las propiedades que Windows logra ver.
2. Comprobar el descubrimiento con una segunda herramienta BLE (por ejemplo, Bluetooth LE Explorer), sin repetir indiscriminadamente intentos.
3. Probar actualización de controlador Bluetooth o adaptador USB BLE **solo como diagnóstico opcional**; no garantizar solución.
4. **Ruta preferida de contingencia:** desarrollar desde Windows con CLI + **Android conectado por ADB**, usando BLE nativo del teléfono para ejecutar las pruebas físicas. El agente compila, instala y lee `adb logcat`.
5. Otra ruta: **Linux + BlueZ/Bleak**, si la PC puede iniciarlo y dispone de adaptador BLE.
6. Considerar dongle dedicado y pila no-WinRT (p. ej. Bumble) solamente como investigación posterior y aislada. No mezclar drivers ni aplicar cambios invasivos sin aprobación.

**Separar dos conexiones:**

- **ADB (USB o depuración inalámbrica):** PC ↔ Android, para desarrollo y logs.
- **BLE:** Android ↔ LEDDMX-03, para controlar las luces.

`adb pair` **no empareja el controlador LED**; sirve únicamente para configurar depuración inalámbrica Android.

---

## 6. Arquitectura propuesta (mínima, testeable)

```text
LEDDMX03/
├── AGENTS.md                    # Puede copiarse un resumen de estas reglas
├── README.md                    # Configuración/uso del proyecto
├── PROGRESS.md                  # Evidencia y avances por fases
├── docs/
│   ├── PROTOCOL.md              # Tabla de tramas y su estado: confirmado/candidato
│   └── BLE-TROUBLESHOOTING.md   # Errores reales de Windows/Android
├── protocol/
│   └── test-vectors.json        # Tramas y casos de prueba independientes de plataforma
├── tools/
│   ├── requirements.txt
│   ├── scan_ble.py
│   ├── probe_gatt.py
│   └── send_hex.py
└── android/                     # Proyecto Android Gradle, Kotlin + Compose
    └── app/src/main/...
```

Arquitectura funcional Android:

- `protocol/`: constructores puros de tramas, normalización de colores, orden de canales configurable, validaciones, tests.
- `ble/`: scanner, dispositivo seleccionado, conexión, reconexión, discovery, cola de escrituras, cancelación y logs.
- `domain/`: acciones `power`, `setColor`, `setBrightness`, `setNativeEffect`, `setSpeed` y estados de conexión.
- `effects/`: motor local de animaciones y secuencias con control de ritmo; se cancela al desconectar.
- `data/`: dispositivo preferido, últimos valores, presets y modos definidos por usuario.
- `ui/`: Compose; pantalla principal simple, estado BLE, selector RGB, brillo, favoritos, efectos, creador DIY, ajustes/diagnósticos.

Mantener **datos de protocolo compartibles** mediante vectores JSON para Python y Kotlin. No es obligatorio compartir código entre lenguajes; evitar sobreingeniería.

### Permisos Android

- Android 12+ (`API 31+`): solicitar en tiempo de ejecución `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT` según corresponda.
- Para compatibilidad con versiones anteriores, atender permisos BLE/ubicación según nivel API y declaración del manifest.
- `RECORD_AUDIO` **solo** si se implementa reacción a micrófono.
- Si se requieren modos persistentes con pantalla apagada: evaluar foreground service, sus permisos/tipo y notificación visible según las reglas actuales de Android. No prometer ejecución irrestricta en background.
- No solicitar permisos que el MVP no necesita.

---

## 7. Modos personalizados: contrato y algoritmo

### Modelo sugerido (persistencia JSON o DataStore)

```json
{
  "id": "warm-cycle",
  "name": "Fuego suave",
  "loop": true,
  "steps": [
    { "color": "#FF3300", "brightness": 70, "durationMs": 500, "transition": "linear" },
    { "color": "#FF9000", "brightness": 85, "durationMs": 350, "transition": "step" },
    { "color": "#D01000", "brightness": 60, "durationMs": 450, "transition": "linear" }
  ]
}
```

- `transition=step`: cambio inmediato al siguiente color.
- `transition=linear`: interpolación RGB/HSV realizada por la app, enviando frames con cadencia ajustable.
- El motor debe respetar el *rate limit* observado, aplicar último-valor-gana y descartar los frames anteriores si hay retraso.
- Guardar versión de esquema y validar rangos.
- Usar `durationMs` para la duración objetivo, **no** suponer exactitud temporal si el BLE se atrasa.
- Si falta soporte de brillo, aproximar brillo escalando componentes RGB y comunicar la limitación.
- Al detener un modo, preservar o restaurar el último color elegido según ajuste explícito.
- Modos host-driven pueden no verse perfectamente fluidos; medir y ofrecer velocidad/cadencia realista.

### Requisitos para música

- MVP: **micrófono** de Android, amplitud/RMS + suavizado -> cambios controlados de color/brillo, con permiso visible.
- Opcional: bandas FFT para graves/medios/agudos, una vez comprobada la estabilidad BLE.
- No implementar captura oculta de audio de otras aplicaciones ni prometer compatibilidad con servicios de streaming.

---

## 8. Fases de implementación y criterios de aceptación

### F0 — Inventario y reproducción

- [ ] Crear repositorio base y `PROGRESS.md`; identificar Windows, Bluetooth y herramientas Android disponibles.
- [ ] Revisar fuentes listadas abajo, anotar contradicciones de protocolo.
- [ ] Preparar tests de tramas y parser de 9 bytes.
- **Listo cuando:** existe un diagnóstico reproducible y una tabla de capacidades `confirmada / no confirmada / incompatible`.

### F1 — Control BLE desde terminal / ruta alternativa

- [ ] Escaneo de LEDDMX-03-03C1.
- [ ] Discovery/propiedades FFE0/FFE1 o reporte exacto de bloqueo en Windows.
- [ ] Envío de POWER ON y comprobación visual.
- [ ] Pruebas RGB con rojo, verde y azul; calibración de orden y de variante.
- [ ] POWER OFF; brillo y al menos un efecto nativo, si la investigación y la unidad lo permiten.
- **Listo cuando:** cada función implementada tiene **evidencia de comportamiento real**, no solo ausencia de excepciones. Si Windows está bloqueado, pruebas físicas se realizan desde Android.

### F2 — App Android básica

- [ ] Crear proyecto Kotlin/Compose; manejar permisos Android.
- [ ] Lista de dispositivos, conectar, guardar dispositivo, reconectar, desconectar.
- [ ] Encender, apagar, seleccionar color y brillo **según capacidades comprobadas**.
- [ ] UI de errores y conexión; logs de GATT; tests del protocolo.
- [ ] Compilar e instalar APK de depuración en el teléfono.
- **Listo cuando:** el usuario puede abrir la app y controlar la unidad sin nRF Connect, de forma repetible.

### F3 — Conexión y resiliencia

- [ ] Backoff, desconexión limpia, timeout, cola serial, coalescing de sliders.
- [ ] Pruebas de ciclos conectar/desconectar, app en foreground/background, Bluetooth apagado/encendido y dispositivo fuera de rango.
- [ ] Pairing **solo** si se demuestra compatible y útil; registrar resultados.
- **Listo cuando:** reconecta tras pérdidas comunes sin reiniciar manualmente la app y sin colgar UI.

### F4 — Modos DIY

- [ ] Arcoíris, respiración, policía, fuego, estrobo; botones iniciar/detener.
- [ ] Editor de secuencias + presets persistentes.
- [ ] Evaluar latencia, suavidad, carga y consumo; reducir tasa al detectar pérdidas.
- [ ] Music/mic opcional y tras permiso explícito.
- **Listo cuando:** los modos no bloquean la app y su comportamiento observado coincide razonablemente con la configuración.

### F5 — Entrega

- [ ] Tests automáticos y una sesión física de validación con el usuario.
- [ ] APK debug/release (según disponibilidad y firma); fuente y guía corta de instalación.
- [ ] `README.md` de usuario y documentación técnica final con limitaciones explícitas.
- [ ] Plan de mantenimiento y registro de bugs, sin prometer funciones no probadas.

---

## 9. Pruebas mínimas automáticas

- Cada trama tiene **exactamente 9 bytes**, con encabezado `0x7B`, final `0xBF` y opcode correcto.
- Encendido = bytes exactos `7B FF 04 01 FF FF FF FF BF`.
- Validar bytes RGB `0..255`; normalizar `#RRGGBB`; permutar canales de manera parametrizable.
- `brightness` entre 0 y 100; interpolación no supera esos límites.
- Test con transporte falso: conectar -> enviar -> perder conexión -> intentar reconectar, sin duplicar escrituras pendientes.
- Test de slider: 100 cambios rápidos no producen 100 frames obsoletos después de 10 segundos.
- Test de stop: finalizar modo cancela cola de animación y no manda frames residuales.
- No declarar éxito físico solo porque `write_gatt_char` o Android GATT retornan sin error.

## 10. Bloqueos, decisiones y preguntas que realmente requieren pruebas

1. **¿Windows 11 puede enumerar FFE1 en esta unidad?** Si no, usar Android/ADB inmediatamente.
2. **¿Qué codificación RGB funciona (variante A/B, orden RGB/RBG)?** Usar tres colores puros.
3. **¿El controlador admite pairing?** No necesario para el MVP; investigar solo si aparecen problemas reales de autenticación.
4. **¿Existe read-back de estado?** Si no, UI mostrará estado estimado del último comando enviado, claramente diferenciado del estado BLE.
5. **¿Tira completa o píxeles independientes?** No anunciar zonas personalizadas si solo hay RGB global.
6. **¿Cadencia sostenible?** Calibrar para modos DIY, sin suponer 30 FPS.
7. **¿Qué app Android original se usa?** Hay referencias al ecosistema `LED LAMP` para familias similares, pero **no está confirmado** que sea la app exacta de esta unidad.

---

## 11. Fuentes verificadas y prioridad de lectura

1. **[aarshivv/leddmx-controller](https://github.com/aarshivv/leddmx-controller)** — hardware LEDDMX-03 probado, 9 bytes, FFE0/FFE1, arquitectura desacoplada, tabla de efectos y problemas Windows.
   - [PROGRESS.md](https://github.com/aarshivv/leddmx-controller/blob/main/PROGRESS.md) — consultar especialmente diagnóstico `0x8007003A`, límites del hardware y reconexión.
2. **[Rishi-Goyal/led-hue-cycle](https://github.com/Rishi-Goyal/led-hue-cycle)** — Android + Python, control continuo, calibración de orden RGB, BLE y alternativas cuando Windows falla.
   - [Android README](https://github.com/Rishi-Goyal/led-hue-cycle/blob/main/android/README.md) — control de escritura y actualización de modos.
3. **[LycheeAPPF/led-ble-car — PROTOCOL.md](https://github.com/LycheeAPPF/led-ble-car/blob/main/PROTOCOL.md)** — variantes LEDCAR/LEDDMX: potencia, RGB, brillo, velocidad, efectos y opcodes peligrosos. **No confundir los dialectos A/B ni diferentes modelos.**
4. **[user154lt/LEDDMX-00](https://github.com/user154lt/LEDDMX-00)** — UUIDs y referencia base para LEDDMX-00/03.
5. **[Pbharathwajan/led-control-mac](https://github.com/Pbharathwajan/led-control-mac)** — otras observaciones en LEDDMX-03, reconexión, límites de DIY y read-back.
6. **[Bleak: documentación oficial](https://bleak.readthedocs.io/en/stable/)** — APIs de escaneo, GATT, `response=`, pairing opcional y diferencias de Windows.
   - [BleakClient](https://bleak.readthedocs.io/en/stable/api/client.html).
7. **[Android Developers: permisos Bluetooth](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)** — Bluetooth Scan/Connect y compatibilidad Android 12+.
   - [Android BLE overview](https://developer.android.com/develop/connectivity/bluetooth/ble/ble-overview).

**Regla de precedencia:** evidencia del **LEDDMX-03-03C1 real** > documentación de LEDDMX-03 semejante > otros LEDDMX/LEDCAR > suposiciones.

## 12. Primera acción concreta del agente

> Inspecciona el entorno actual y crea el esqueleto mínimo del proyecto. Empieza por **detectar el BLE en Windows 11 y comprobar si es posible descubrir FFE0/FFE1**. Crea un script CLI de diagnóstico con logs reproducibles. Si Windows falla al descubrir GATT, documenta el error y configura el flujo **Windows + ADB + Android BLE**; después verifica POWER ON y prueba RGB por colores primarios. **No construyas toda la interfaz antes de confirmar el protocolo**. Mantén el informe al usuario breve: *qué probaste, qué funcionó, qué sigue*.
