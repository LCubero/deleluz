# DeleLuz · Five phone-first directions

T5 · S2 and S5. Each self-contained board contains five 390×844 frames: Home/Devices, Control, Effects, Custom Mode, and Per-LED Editor. Open the HTML directly or use `/gentle:design open deleluz-mobile` if the canvas is available.

## Research and evidence

**Consulted directly:** [device research task](../../odd/tasks/device-research.md), including the rejection in L8; [LEDDMX-03 protocol](../../docs/PROTOCOL.md); and the private LED LAMP 4.3.7 UI inventory and effect transcription (`.ld9/research/ledlamp-app/ui.md`). The inventory documents the cramped perspective wheel, mixed language and clipped copy, and connection count buried inside grouping. Hardware state is not read back. The designs label the command receipt as **Last sent**, treat group output as best effort, and keep pixel mapping preview-only. No pairing, account, cloud, ads, or borrowed assets.

**External design references from prior knowledge, not live research:** Web search/fetch was unavailable. The following are inspiration hypotheses, not current screen observations or user-review findings. Live screenshot and review research is still outstanding.

| Reference | Pattern applied |
|---|---|
| Philips Hue | Room grouping and named scenes; put group readiness on the room itself. |
| Apple Home / Google Home | Large scene tiles; open secondary controls without making every option compete on Home. |
| Govee Home / Nanoleaf | Organize reusable looks by recognizable names; expose categories and favorites rather than one long unmarked catalog. |
| LIFX | Give color a dedicated control and keep level separate from the hue choice. |
| Twinkly | Show a spatial pixel preview before attempting physical output. |
| WLED | Address a range by index and reveal device-specific controls progressively. |
| Betaflight / BetaFPV LED config | Separate pixel address, color, and function. |
| Music-player mini bars | Keep the selected output and last command visible while browsing tools. |
| Magic Home / Happy Lighting / duoCo Strip | Keep music optional; give power and brightness priority over sound modes. |

**Five anti-patterns avoided:** Hidden connection state; ambiguous or silent connection errors; a cramped effect wheel; clipped or mixed-language controls; and a generic pixel grid that implies verified hardware output.

## Directions

| Direction | Home and route to control | Best for | Trade-off / relative complexity |
|---|---|---|---|
| [01 Classic Tabs](01-classic-tabs.html) | A device roster leads to the Control tab; five persistent icon tabs also provide direct entry. Room grouping and color controls draw on Hue and LIFX. | Mixed daily use and discoverability | Fixed navigation consumes height. Medium. |
| [02 Strip First](02-strip-first.html) | Select a target first; enter its workspace with the pinned amber receipt, then open scoped tools. WLED indices and a mini-player receipt guide the layout. | Avoiding wrong-target changes | Extra drill-down; pinned context costs space. Medium. |
| [03 Quick Scenes](03-quick-scenes.html) | A room’s saved scene tiles take priority; Adjust Light and the other tools are shown as bottom sheets. Draws on Home tiles and Hue scenes. | Repeating familiar looks | Deep editing has less space and is less discoverable. Medium. |
| [04 Mode Studio](04-mode-studio.html) | Start on a timed project track; tap clips for editing or open the output monitor for manual override. Pixel patch uses indexed function assignment. | Building precise loops | Highest complexity: timeline, playback cancellation, and connection changes. High. |
| [05 Light Remote](05-light-remote.html) | Power and dimming are the Home dial; open a shortcut for color or other tools. Combines remote controls with a mini-player-style receipt. | Quick one-thumb control | Target management is secondary; swipe ergonomics need phone testing. Medium. |

## Verification and limits

Chromium headless screenshots were captured and opened for all five boards at **1440×2000** and **390×4400**. Desktop shows three phones above two; mobile shows all five in order. Each Effects frame shows about eight named rows at rest, with more rows below, search, filters, and stars. Four pixel editors show a connected serpentine; Strip First uses a sideways-scrollable ribbon. Classic has five icon tabs. Quick Scenes leaves separation between the last control and the receipt. The final recapture also confirms Classic exposes both Effects sliders and Strip First separates the virtual effect ribbon from its last-sent receipt.

These are visual prototypes, not end-to-end simulations. Effects search uses transcribed samples rather than all 211 entries; preview motion is illustrative, not an emulator. Device commands, grouping, persistence, schedules, import/export, onboarding, and microphone permission are mocked or described; pixel selection accepts taps or typed ranges, not drag. There is no dedicated large-text mode, complete one-handed reach study, focus walkthrough, contrast audit, or device verification. The comparison shows distinct Home layouts and routes to control; the specialist list/editor views share expected interaction patterns, not markup. No outside assets are loaded.
