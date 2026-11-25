---
name: deleluz-design-rules
description: "Trigger: any DeleLuz UI change (Android app or webapp): screens, sheets, pickers, components. Apply the Glow Glass standard."
license: "MIT"
metadata:
  author: DeleLuz
  version: "1.0"
  canonical-source: core/deleluz-design-rules:1.0
---

## Activation Contract

Read `design/system.md` before changing DeleLuz UI. Skip for non-UI work.

## Hard Rules

- Use only `design/system.md` tokens. Keep rounded corners, effects, glows and shadows consistent. Align edges and use symmetric spacing; nothing touches or overlaps unintentionally.
- Reuse one shared component per job: one color picker across Color, quick actions and scene steps; one effect list across entry points.
- Show selection with a filled or tinted surface plus a check or distinct border. Never rely on color alone. Expose selection, roles and labels to assistive technology.
- Give every interactive target at least 48 × 48 dp (48 × 48 CSS px on web). Meet WCAG AA contrast on actual composited surfaces; preserve visible focus.
- Localize every user-facing string in Spanish and English, including tooltips and semantic labels. Wrap text; do not clip, ellipsize or shrink it to fit. Show a discreet, non-overlapping scroll hint when more content is below.
- Use one notice style for info, warnings and errors: icon plus text, token colors, never larger than body text. Reserve space for status text that changes, so the layout never shifts.

## Decision Gates

- Missing token or component? Check existing sources and reuse before proposing an addition; do not invent a local variant.

## Execution Steps

- [ ] Android: run widget tests at 320 and 412 dp with enlarged text; check both languages, selection, semantics and overflow.
- [ ] Webapp: run `node --test webapp/ lab/web/`, then check the changed controls in browser device emulation at 320 and 412 px: selection, keyboard focus, labels and horizontal overflow.
- [ ] Capture device or emulator screenshots (browser device emulation for web). Compare alignment, spacing, colors, radii and effects against `design/system.md`.

## Output Contract

Report changed files, tests, screenshot locations and any unverified checks.

## References

- `design/system.md` — source-backed tokens and component rules.
