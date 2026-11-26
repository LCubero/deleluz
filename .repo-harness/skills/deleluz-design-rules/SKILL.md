---
name: deleluz-design-rules
description: "Trigger: any DeleLuz UI change (Android app or webapp): screens, sheets, pickers, components. Apply the Glow Glass standard."
license: "MIT"
metadata:
  author: DeleLuz
  version: "1.2"
  canonical-source: core/deleluz-design-rules:1.0
---

## Activation Contract

Read `design/system.md` before changing DeleLuz UI. Skip for non-UI work.

## Hard Rules

- Use only `design/system.md` tokens. Keep rounded corners, effects, glows and shadows consistent. Align edges and use symmetric spacing; nothing touches or overlaps unintentionally.
- Reuse one shared component per job: one color picker across Color, quick actions and scene steps; one effect list across entry points.
- Show selection with a cyan-tinted surface, a cyan (`#22d3ee`) border and a check. Never rely on color alone. Focus outlines are cyan. Progress bars and rings keep the violet→magenta gradient; primary buttons keep the gradient fill. Expose selection, roles and labels to assistive technology.
- Give every interactive target at least 48 × 48 dp (48 × 48 CSS px on web). Meet WCAG AA contrast on actual composited surfaces; preserve visible focus.
- Localize every user-facing string in Spanish and English, including tooltips and semantic labels. Wrap text; do not clip, ellipsize or shrink it to fit. Show a discreet, non-overlapping scroll hint when more content is below.
- Use one notice style for info, warnings and errors: icon plus text, token colors, never larger than body text. Status text that appears or changes uses `GlowStatusSlot`; transient errors float. Nothing below may move when such text appears.
- Selection never changes geometry: tabs, chips and rows reserve the check slot in every state; siblings keep one height; labels never move or rewrap on select.
- Tell the user how a scene runs before they play it: icon + text tag «Necesita la app» (app-driven; app open and strip connected) or «En la tira» (native effect).
- Localize effect names (Spanish in the Spanish locale); store IDs, never display names. Truncate only user-given names (aliases, scene names) to at most two lines.
- Use `GlowPrimaryButton` for the primary action of every screen, sheet and dialog; never a plain `FilledButton`.
- Never split a word across lines. When width / text scale < 300 dp (`glowCompactLayout`), stack segments full width, use one column for card grids, and move side pills or labels above or below the text instead of squeezing it.
- Cards in the same grid row share the tallest height; swatches and tags align to the bottom.
- Mark what is playing: the last successfully started scene, effect or music mode shows the selection style; one at a time; a failed send keeps the previous one.
- List strip-native effects («En la tira») before app-driven scenes («Necesita la app»).
- A reserved status slot never shows as an empty hole: when idle it shows a useful hint (e.g. the effect range).

## Decision Gates

- Missing token or component? Check existing sources and reuse before proposing an addition; do not invent a local variant.

## Execution Steps

- [ ] Android: run widget tests at 320 and 412 dp with enlarged text; check both languages, selection, semantics and overflow. Add a geometry test (rects stay equal) for every selection or status change.
- [ ] Review the app first, without the strip: emulator screenshots at 320/412 dp, ES/EN, enlarged text, disconnected, simulated connected and error states.
- [ ] Webapp: run `node --test webapp/ lab/web/`, then check the changed controls in browser device emulation at 320 and 412 px: selection, keyboard focus, labels and horizontal overflow.
- [ ] Capture device or emulator screenshots (browser device emulation for web). Compare alignment, spacing, colors, radii and effects against `design/system.md`.

## Output Contract

Report changed files, tests, screenshot locations and any unverified checks.

## References

- `design/system.md` — source-backed tokens and component rules.
