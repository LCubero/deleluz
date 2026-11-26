# DeleLuz Glow Glass

Source snapshot for [T14 / S18](../odd/tasks/app-polish.md). Flutter is the Android reference; the web root provides the CSS counterparts, not a mandate to port Android work. Dart colors use `0xAARRGGBB`; Flutter dimensions are logical pixels. CSS alpha values are recorded independently, not rounded back into Dart hex. The [1440 px artboard](system.html) is a browser representation, not a screenshot or a pixel-perfect Flutter rendering.

## Colors

| Token | Value | Use | Source |
|---|---|---|---|
| `glowBackground` | `0xff0a0918` | Scaffold | `app/lib/ui/glow_glass.dart` |
| `glowInk` | `0xfff5f3ff` | Main text | `app/lib/ui/glow_glass.dart` |
| `glowMuted` | `0xffbdb6dc` | Secondary text | `app/lib/ui/glow_glass.dart` |
| `glowFaint` | `0xff8f88b3` | Inactive navigation and idle status | `app/lib/ui/glow_glass.dart` |
| `glowViolet` | `0xffa855f7` | Seed and effects | `app/lib/ui/glow_glass.dart` |
| `glowPink` | `0xffec4899` | Effects | `app/lib/ui/glow_glass.dart` |
| `glowLink` | `0xfff0abfc` | Highlighted icons | `app/lib/ui/glow_glass.dart` |
| `glowTheme.primary` | `0xffe3c2ff` | Material primary | `app/lib/ui/glow_glass.dart` |
| `glowTheme.surface` | `0xff1b1636` | Material surface | `app/lib/ui/glow_glass.dart` |
| `filledButton.backgroundColor` | `0xff7e22ce` | Primary action surface | `app/lib/ui/glow_glass.dart` |
| `filledButton.foregroundColor` | `Colors.white` | Primary action label | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.connecting` | `0xfffbbf24` | Connecting dot | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.connected` | `0xff4ade80` | Connected dot | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.lost` | `0xfff87171` | Lost dot | `app/lib/ui/glow_glass.dart` |
| `GlowStrip.empty` | `0xff2a2540` | Empty preview | `app/lib/ui/glow_glass.dart` |
| `_StripDots.paint` | `0x73000000` | Strip dot overlay | `app/lib/ui/glow_glass.dart` |
| `glowEffectColors` | `[[236, 72, 153], [168, 85, 247], [34, 211, 238]]` | Illustrative only; not reported strip colors | `app/lib/ui/glow_glass.dart` |
| `BluetoothCard._warn` | `0xfffbbf24` | Warning icon, title and border | `app/lib/ui/bluetooth_card.dart` |
| `BluetoothCard._surface` | `0xff251e2c` | Warning card surface | `app/lib/ui/bluetooth_card.dart` |
| `AppShell._navigation.color` | `0xff0a0818` | Bottom navigation surface | `app/lib/ui/app_shell.dart` |
| `_CountdownRing.fill` | `0xff1b1436` | Timer ring interior | `app/lib/ui/timer_sheet.dart` |
| `--bg` | `#0a0918` | Scaffold counterpart | `webapp/style.css` |
| `--ink` | `#f5f3ff` | Main text | `webapp/style.css` |
| `--muted` | `#bdb6dc` | Secondary text | `webapp/style.css` |
| `--faint` | `#8f88b3` | Subdued text | `webapp/style.css` |
| `--violet` | `#a855f7` | Accent | `webapp/style.css` |
| `--magenta` | `#ec4899` | Pink accent | `webapp/style.css` |
| `--cyan` | `#22d3ee` | Cyan accent | `webapp/style.css` |
| `--ok` | `#4ade80` | Success | `webapp/style.css` |
| `--warn` | `#fbbf24` | Warning | `webapp/style.css` |
| `--bad` | `#f87171` | Error | `webapp/style.css` |

## Glass and borders

| Token | Value | Use | Source |
|---|---|---|---|
| `glowLine` | `0x24ffffff` | Glass outline | `app/lib/ui/glow_glass.dart` |
| `glowGlass` | `0x11ffffff` | Translucent fill | `app/lib/ui/glow_glass.dart` |
| `glowGlassSelected` | `0x1cffffff` | Selected glass or status pill | `app/lib/ui/glow_glass.dart` |
| `_FlushSliderTrack.inactive` | `0x1fffffff` | Unfilled track | `app/lib/ui/glow_glass.dart` |
| `--glass` | `rgba(255,255,255,.065)` | Translucent fill | `webapp/style.css` |
| `--glass-2` | `rgba(255,255,255,.11)` | Stronger glass | `webapp/style.css` |
| `--line` | `rgba(255,255,255,.14)` | Glass outline | `webapp/style.css` |

Glass in `GlassCard` is tint plus border, not a backdrop filter. Blur values below belong to individual effects.

## Gradients

| Token | Value | Use | Source |
|---|---|---|---|
| `glowStrongGradient` | `topLeft → bottomRight; 0xff7e22ce → 0xffbe185d` | Strong action | `app/lib/ui/glow_glass.dart` |
| `_FlushSliderTrack.fill` | `glowViolet → glowPink; reverse direction in RTL; alpha .45 + .55 × enableAnimation.value` | Active slider track | `app/lib/ui/glow_glass.dart` |
| `_BackdropPainter.radial` | `radius .5; stops [0, .7]; source color → alpha 0` | Radial bloom falloff | `app/lib/ui/glow_glass.dart` |
| `_BackdropPainter.pink` | `0x2eec4899; center (width, height × .7); scale (400, 340)` | Lower right bloom | `app/lib/ui/glow_glass.dart` |
| `_BackdropPainter.violet` | `0x4da855f7; center (width × .1, 0); scale (420, 300)` | Upper left bloom, painted last | `app/lib/ui/glow_glass.dart` |
| `TimerSheet.surfaceGradient` | `topCenter → bottomCenter; 0xff201840 → 0xff120e26` | Timer sheet panel | `app/lib/ui/timer_sheet.dart` |
| `_CountdownRing.progress` | `SweepGradient(glowViolet → glowPink); rotation -π/2` | Timer progress | `app/lib/ui/timer_sheet.dart` |
| `--grad` | `linear-gradient(135deg,#a855f7 0%,#ec4899 100%)` | Accent gradient | `webapp/style.css` |
| `--grad-strong` | `linear-gradient(135deg,#7e22ce 0%,#be185d 100%)` | Strong gradient | `webapp/style.css` |

## Radii

| Token | Value | Use | Source |
|---|---|---|---|
| `GlassCard.radius` | `24` | Card and confirmation dialog | `app/lib/ui/glow_glass.dart` |
| `GlowTile.radius` | `16` | Tappable tile | `app/lib/ui/glow_glass.dart` |
| `filledButton.radius` | `14` | Action and segment container | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.itemRadius` | `10` | Individual segment | `app/lib/ui/glow_glass.dart` |
| `GlowStrip.radius` | `99` | Strip, track and status pill | `app/lib/ui/glow_glass.dart` |
| `--r-lg` | `24px` | Large radius | `webapp/style.css` |
| `--r-md` | `16px` | Medium radius | `webapp/style.css` |

## Shadows and glows

| Token | Value | Use | Source |
|---|---|---|---|
| `_GlowThumb.shadow` | `0x66000000; offset (0, 4); MaskFilter sigma 6` | Thumb depth | `app/lib/ui/glow_glass.dart` |
| `_GlowThumb.halo` | `glowViolet; radius 18; alpha .4 × enabled alpha` | Thumb halo | `app/lib/ui/glow_glass.dart` |
| `GlowStrip.glow` | `provided color at alpha .55; blurRadius 22` | Optional preview glow | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.dotGlow` | `status color; blurRadius 10; none when idle` | Status indicator | `app/lib/ui/glow_glass.dart` |
| `_connectButton.shadow` | `0x59ec4899; offset (0, 8); blurRadius 24` | Enabled non-neutral action | `app/lib/ui/home.dart` |
| `ColorDisc.glow` | `0x40a855f7; blurRadius 38` | Color disc bloom | `app/lib/ui/color_disc.dart` |
| `ColorDisc.markerShadow` | `0xaa0a0918; offset (0, 2); blurRadius 8` | Picker marker depth | `app/lib/ui/color_disc.dart` |

## Spacing and sizes

| Token | Value | Use | Source |
|---|---|---|---|
| `glassInset` | `16.0` | Card inset | `app/lib/ui/glow_glass.dart` |
| `glowScreenPadding` | `LTRB(18, 16, 18, 18)` | Screen gutters | `app/lib/ui/glow_glass.dart` |
| `GlowGrid.spacing` | `10` | Row and column gaps | `app/lib/ui/glow_glass.dart` |
| `GlowTile.inset` | `10` | Tile padding | `app/lib/ui/glow_glass.dart` |
| `GlowTile.minHeight` | `64` | Tile baseline | `app/lib/ui/glow_glass.dart` |
| `filledButton.minimumSize` | `48 × 48` | Action touch target | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.inset` | `4` | Outer inset | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.labelInset` | `horizontal 2; vertical 8` | Segment padding | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.minHeight` | `48` | Segment touch target; all segments share one height | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.checkSlot` | `18 + gap 4` | Reserved in every segment so labels never move | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.padding` | `horizontal 12; vertical 6` | Status pill inset | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.metrics` | `minHeight 36; dot 8; gap 8` | Noninteractive status | `app/lib/ui/glow_glass.dart` |
| `slider.trackHeight` | `10` | Flush track | `app/lib/ui/glow_glass.dart` |
| `slider.thumbRadius` | `14` | White thumb | `app/lib/ui/glow_glass.dart` |
| `slider.overlayRadius` | `24` | Slider overlay, not a touch-target guarantee | `app/lib/ui/glow_glass.dart` |
| `GlowStrip.height` | `10` | Strip preview | `app/lib/ui/glow_glass.dart` |
| `GlowValueLabel.spacing` | `8` | Label row gap | `app/lib/ui/glow_glass.dart` |
| `TimerSheet.padding` | `LTRB(16, 0, 16, 16)` | Scroll content | `app/lib/ui/timer_sheet.dart` |
| `TimerSheet.choiceSpacing` | `spacing 8; runSpacing 4` | Wrapped choices | `app/lib/ui/timer_sheet.dart` |
| `QuickActionsSheet.padding` | `LTRB(16, 8, 16, 12)` | Sheet content | `app/lib/ui/quick_actions_sheet.dart` |
| `QuickActionsSheet.maxWidth` | `480` | Sheet width cap | `app/lib/ui/quick_actions_sheet.dart` |
| `AppShell.navigationSize` | `maxWidth 480; minHeight 72` | Safe-area navigation row | `app/lib/ui/app_shell.dart` |
| `AppShell.navigationPadding` | `horizontal 10; vertical 6` | Outer nav padding | `app/lib/ui/app_shell.dart` |
| `AppShell.navItemSpacing` | `4` | Icon and label gap | `app/lib/ui/app_shell.dart` |
| `BluetoothCard.padding` | `14` | Warning card inset | `app/lib/ui/bluetooth_card.dart` |
| `BluetoothCard.spacing` | `10` | Warning content and icon gaps | `app/lib/ui/bluetooth_card.dart` |
| `BluetoothCard.iconBox` | `44 × 44` | Decorative icon well | `app/lib/ui/bluetooth_card.dart` |

## Typography

| Token | Value | Use | Source |
|---|---|---|---|
| `titleLarge` | `22; w700; letterSpacing -.44` | Screen and sheet titles | `app/lib/ui/glow_glass.dart` |
| `GlowHeader.leadingTitle` | `20; w700; letterSpacing -.2` | Title paired with leading glyph | `app/lib/ui/glow_glass.dart` |
| `titleMedium` | `15; w700; height 1.4` | Card titles | `app/lib/ui/glow_glass.dart` |
| `bodyMedium` | `15; height 1.4` | Main copy | `app/lib/ui/glow_glass.dart` |
| `bodySmall` | `13; height 1.4` | Muted copy | `app/lib/ui/glow_glass.dart` |
| `filledButton.textStyle` | `15; w700` | Primary actions | `app/lib/ui/glow_glass.dart` |
| `GlowSegments.labelStyle` | `14 for three segments, otherwise 15; w600` | Segment labels | `app/lib/ui/glow_glass.dart` |
| `ConnectionChip.textStyle` | `13; height 1.4; w600` | Status | `app/lib/ui/glow_glass.dart` |
| `AppShell.navLabel` | `12; w600` | Navigation labels | `app/lib/ui/app_shell.dart` |
| `--font` | `system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif` | Web stack; Flutter theme does not override font family | `webapp/style.css` |

## Component rules

| Component | Source pattern and usage | Source |
|---|---|---|
| Cards and tiles | Use `GlassCard` for sections and `GlowTile` for tap actions; align paired tiles with `GlowGrid`. | `app/lib/ui/glow_glass.dart` |
| Segmented tabs | Use `GlowSegments`: equal-width, equal-height siblings; every segment reserves the check slot; labels and check centered vertically; selected cyan tint, cyan border and check plus semantic selection. Selecting must not move, rewrap or resize any label. | `app/lib/ui/glow_glass.dart` |
| Chips | Status combines a dot with a text label; timer presets are wrapping `ChoiceChip`s. Add a visible selection cue for interactive choices. Do not copy existing status ellipsis into new work. | `app/lib/ui/glow_glass.dart`, `app/lib/ui/timer_sheet.dart` |
| Sliders | Use the shared flush track and glowing thumb with a label and current value. `SliderZone` keeps horizontal control drags out of tab swipe. | `app/lib/ui/glow_glass.dart`, `app/lib/ui/home.dart` |
| Bottom sheets | Use safe areas, keyboard insets, scrollable content and a labeled close action. Timer uses a vertical gradient; quick actions separates type selection from the picker and confirmation. | `app/lib/ui/timer_sheet.dart`, `app/lib/ui/quick_actions_sheet.dart` |
| Navigation | Use equal-width Home, Color, Scenes and Settings items; combine icon and label, expose selected state and respect bottom safe area. | `app/lib/ui/app_shell.dart` |
| Warning card | Put the Bluetooth-off notice above the device controls. Use the amber border, icon and heading with explanatory copy, a clear enable action and live announcements. | `app/lib/ui/home.dart`, `app/lib/ui/bluetooth_card.dart` |
| Color and effects | Reuse the shared color picker and `EffectList` across entry points instead of cloning them. Treat current implementation differences as gaps, not new variants. | `app/lib/ui/color_disc.dart`, `app/lib/ui/effect_list.dart`, `app/lib/ui/quick_actions_sheet.dart` |
| Status slots | Text that appears or changes (last sent, countdown, now playing) lives in `GlowStatusSlot` with reserved lines; transient command errors float (`showGlowNotice`) instead of pushing content. | `app/lib/ui/glow_glass.dart`, `app/lib/ui/notice.dart` |
| Runtime tag | Scene cards show icon + text: «Necesita la app» (app-driven timers; app open and strip connected) or «En la tira» (native strip effect), with a legend above the list. Pickers of app-driven scenes repeat the note. | `app/lib/ui/scenes/scenes_screen.dart`, `app/lib/ui/quick_actions_sheet.dart` |
| Sheet headers | Reserve the Back slot on every step so the title keeps its axis. | `app/lib/ui/quick_actions_sheet.dart` |

For new work, the design-rules skill sets the accessibility bar: 48 dp interactive targets, WCAG AA contrast on the composited surface, non-color selection cues, wrapped Spanish/English labels, meaningful semantics and a scroll hint when content continues. Source values above describe current code, not blanket accessibility conformance.
