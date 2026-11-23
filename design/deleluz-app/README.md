# DeleLuz — Compare the directions

T5 / S2 · Start with the same scenario in each direction: a 5 m shelf strip is connected, a planned 10 m ceiling strip is reconnecting, and the target can be one strip or their Living room group. Only the 5 m / 150 LED unit is the initial hardware target.

| Direction | Idea | Best for | Trade-off | Relative build complexity |
| --- | --- | --- | --- | --- |
| [Control Deck](01-control-deck.html) | Present connection and control side by side. | First setup, diagnostics, and frequent manual tuning. | Less immediate than a favorites screen, especially on phones. | Medium: target selection and per-strip delivery feedback. |
| [Strip Canvas](02-strip-canvas.html) | Make the strip map the starting point, with a segment inspector alongside it. | People who think in LED positions and want precise ranges. | Main value remains draft-only on the initial controller. | Very high: spatial selection, virtual mapping, and unconfirmed hardware support. |
| [Quick Scenes](03-quick-scenes.html) | Lead with large, named scene tiles and a visible target. | Daily one-tap use, especially on a phone. | Less visibility into advanced controls; they sit behind disclosures. | Low–medium: local favorites and a shared control model. |
| [Mode Studio](04-mode-studio.html) | Show the sequence first, with a dedicated step inspector. | Designing and comparing timed routines. | Adds an editing model when the user may just want a color. | High: sequence editor, scheduler, timing limits, and interruption handling. |
| [Rooms & Groups](05-rooms-and-groups.html) | Make the group and each member’s connection/delivery visible together. | Multi-strip households and troubleshooting partial delivery. | Additional structure for a single strip. | High: group fan-out, best-effort timing, and per-member errors; joined mapping is gated. |

**Recommended starting point:** Control Deck for commissioning and Quick Scenes for everyday use. Treat Strip Canvas as a local draft surface until pixel writes are confirmed. Mirroring must not promise synchronized playback. A write attempt is not proof of physical output.

**Prototype boundaries:** The artboards are offline design previews, not device clients. The effect browser shows sample rows from a planned flat catalog of 210 numbered entries plus AUTO, not a working full-catalog search. No Bluetooth, microphone, or persistent storage is used. Brightness, selection, and similar interactions are illustrative; hardware controls and some editing actions are visual only. No flashing preview is provided. Each board uses exploratory styles, not an established DeleLuz design system.

**Canvas:** `/gentle:design open deleluz-app`
