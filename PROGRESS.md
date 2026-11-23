# Progress

Evidence log by phase. Protocol details live in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Environment

| Item | Value |
|---|---|
| Dev host | Windows 11, Python 3.14, Node 26, Java 26, git, gh, adb 1.0.41 |
| Host BLE | generic Bluetooth adapter present; GATT access from Windows **not tested yet** |
| Phone | Android 13 (API 33), USB debugging, HCI snoop log enabled |
| Vendor app | LED LAMP `com.ledlamp` 4.3.7 (APK kept in git-ignored `_private/`) |

## F0 — Inventory and reproduction

- [x] Repository harness installed; `_private/` git-ignored for vendor APKs and captures.
- [x] Hardware identified from packaging/PCB: RGB-IC addressable strip, 5 m, 150 px, `GND/DAT/5+`, onboard mic, IR, button.
- [x] Vendor app session captured over HCI snoop (session 1, 2026-11-22).
- [x] `tools/btsnoop_att.py`: stdlib parser for ATT traffic from `btsnoop_hci.log` or a bugreport zip.
- [x] `tools/leddmx.py` (scan / probe / send confirmed frames, `--dry-run`) + `tools/test_leddmx.py` (4 frame tests passing).
- [ ] Windows BLE probe: first attempt failed with bleak `No Bluetooth adapter found` because the USB Bluetooth adapter was not present (all Bluetooth PnP devices `Unknown`). Retry with the adapter plugged in.
- [ ] Vendor UI inventory and APK static notes (private, `.ld9/research/`).

## Capability table (LEDDMX-03-03C1)

| Capability | State | Evidence |
|---|---|---|
| GATT `FFE0`/`FFE1`, write without response | confirmed | HCI capture |
| Power on / off | confirmed | capture + observed on strip |
| Static RGB color | confirmed | capture + red/green/blue/white observed |
| Brightness 0–100 | confirmed | capture + max/mid/min observed |
| Native effects (`ID` = app number, `FF` = AUTO) | captured | capture; visual not yet confirmed per ID |
| Effect speed 1–100 | captured | capture |
| Chip config (order, pixel count) | captured, partially decoded | capture |
| Pairing / bonding | not used by vendor app | capture shows plain GATT |
| State read-back | not observed | no notifications in session 1 |
| Per-pixel control | unknown | hardware addressable; no frame captured |
| Multiple phones at once | not supported (manual: one-to-one) | vendor manual |

## Session handoff (2026-11-22 23:59 America/Costa_Rica)

- Research task file: `odd/tasks/device-research.md` (specs, tasks, log L1-L10).
- Design: `design/deleluz-mobile/` v2 (5 phone directions). User: option 1 is the best but feels too generic ("muy IA"). Waiting for other AIs' designs in `.ld9/design-refs/<ai-name>/`, then compare and ask 2-3 style questions before one polish pass. `design/deleluz-app/` is an older desktop draft.
- Stitch MCP: `.pi/mcp.json` reads `${STITCH_API_KEY}`; key verified (connected, 18 tools) when injected. Pi must be launched from a terminal started after `setx` (close Ghostty fully).
- Windows BLE test: blocked until the USB Bluetooth adapter is plugged in; then `tools/leddmx.py scan`, `probe --device LEDDMX-03-03C1`, `send ... off/on`.
- Phone: USB stay-awake left on by user request; vendor app force-stopped. HCI snoop still enabled.
- Nothing committed yet.

## Next

1. Windows BLE probe (`tools/scan_ble.py`, `probe_gatt.py`, `send_hex.py --dry-run`) against `FFE1`.
2. Capture remaining vendor features (music, timer, any DIY/segment screen) and decode the `2A … AF` handshake.
3. Frame builder + tests from confirmed frames only.
