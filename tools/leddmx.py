"""Minimal LEDDMX-03 BLE CLI: scan, probe GATT, send confirmed frames.

Usage (from the repository root, with the venv that has `bleak`):
    python tools/leddmx.py scan
    python tools/leddmx.py probe  --device LEDDMX-03-03C1
    python tools/leddmx.py send   --device LEDDMX-03-03C1 on|off
    python tools/leddmx.py send   --device LEDDMX-03-03C1 color FF0000
    python tools/leddmx.py send   --device LEDDMX-03-03C1 brightness 50
    python tools/leddmx.py send   --device LEDDMX-03-03C1 hex "7B FF 04 01 FF FF FF FF BF"
Add --dry-run to print the frame without connecting.

Only frames confirmed in docs/PROTOCOL.md are built here. `hex` accepts any
9-byte 7B..BF frame; use it only for documented, reversible tests.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
NAME_PREFIX = "LEDDMX"


def _framed(op: int, a: int, b: int, c: int, d: int) -> bytes:
    return bytes([0x7B, 0xFF, op, a, b, c, d, 0xFF, 0xBF])


def frame(command: str, value: str | None = None) -> bytes:
    """Build a confirmed control frame. Raises ValueError on bad input."""
    if command == "on":
        return _framed(0x04, 0x01, 0xFF, 0xFF, 0xFF)
    if command == "off":
        return _framed(0x04, 0x00, 0xFF, 0xFF, 0xFF)
    if command == "color":
        text = (value or "").removeprefix("#")
        if len(text) != 6:
            raise ValueError("color must be RRGGBB")
        r, g, b = bytes.fromhex(text)  # ValueError on non-hex
        return bytes([0x7B, 0xFF, 0x07, r, g, b, 0x00, 0xFF, 0xBF])
    if command == "brightness":
        pct = int(value or "")
        if not 0 <= pct <= 100:
            raise ValueError("brightness must be 0..100")
        return bytes([0x7B, 0xFF, 0x01, pct * 32 // 100, pct, 0x00, 0xFF, 0xFF, 0xBF])
    raise ValueError(f"unknown command: {command}")


def parse_hex(text: str) -> bytes:
    data = bytes.fromhex(text)
    if len(data) != 9 or data[0] != 0x7B or data[-1] != 0xBF:
        raise ValueError("frame must be exactly 9 bytes: 7B .. BF")
    return data


async def _find(name: str, timeout: float):
    from bleak import BleakScanner

    device = await BleakScanner.find_device_by_name(name, timeout=timeout)
    if device is None:
        raise SystemExit(f"error: '{name}' not found (powered? another app connected?)")
    return device


async def scan(timeout: float) -> None:
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    rows = [(adv.rssi, d.name or adv.local_name) for d, adv in found.values()]
    rows = [r for r in rows if r[1] and r[1].upper().startswith(NAME_PREFIX)]
    for rssi, name in sorted(rows, reverse=True):
        print(f"{name}  rssi={rssi}")
    if not rows:
        print(f"no {NAME_PREFIX}* devices found")


async def probe(name: str, timeout: float) -> None:
    from bleak import BleakClient

    async with BleakClient(await _find(name, timeout)) as client:
        for service in client.services:
            print(f"service {service.uuid}")
            for char in service.characteristics:
                print(f"  char {char.uuid} [{', '.join(char.properties)}]")
        print("write characteristic present:", client.services.get_characteristic(WRITE_UUID) is not None)


async def send(name: str, data: bytes, timeout: float) -> None:
    from bleak import BleakClient

    async with BleakClient(await _find(name, timeout)) as client:
        await client.write_gatt_char(WRITE_UUID, data, response=False)
        await asyncio.sleep(0.3)  # let a write-without-response leave before disconnecting
    print("sent (check the strip; a sent frame is not proof of effect)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--timeout", type=float, default=8.0)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    p = sub.add_parser("probe")
    p.add_argument("--device", required=True)
    s = sub.add_parser("send")
    s.add_argument("--device", required=True)
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("command", choices=["on", "off", "color", "brightness", "hex"])
    s.add_argument("value", nargs="?")
    args = parser.parse_args(argv)

    if args.cmd == "scan":
        asyncio.run(scan(args.timeout))
    elif args.cmd == "probe":
        asyncio.run(probe(args.device, args.timeout))
    else:
        try:
            data = parse_hex(args.value or "") if args.command == "hex" else frame(args.command, args.value)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        print("frame:", data.hex(" ").upper())
        if not args.dry_run:
            asyncio.run(send(args.device, data, args.timeout))
    return 0


if __name__ == "__main__":
    sys.exit(main())
