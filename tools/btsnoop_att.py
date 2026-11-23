"""Extract BLE ATT traffic from an Android btsnoop_hci.log (stdlib only).

Usage:
    python tools/btsnoop_att.py <btsnoop_hci.log | bugreport.zip> [--all]

Prints one line per ATT write/notification (or every ATT PDU with --all):
    <local time> <dir> <opcode> handle=0xNNNN <hex payload>
plus a GATT handle -> UUID map recovered from discovery responses.
Device addresses are never printed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import io
import struct
import sys
import zipfile

BTSNOOP_MAGIC = b"btsnoop\x00"
EPOCH_DELTA_US = 0x00DCDDB30F2F8000  # microseconds from year 0 to 1970-01-01
H4_ACL = 0x02
ATT_CID = 0x0004

ATT_NAMES = {
    0x01: "ERROR", 0x02: "MTU_REQ", 0x03: "MTU_RSP", 0x04: "FIND_INFO_REQ", 0x05: "FIND_INFO_RSP",
    0x08: "READ_BY_TYPE_REQ", 0x09: "READ_BY_TYPE_RSP", 0x0A: "READ_REQ", 0x0B: "READ_RSP",
    0x10: "READ_BY_GROUP_REQ", 0x11: "READ_BY_GROUP_RSP", 0x12: "WRITE_REQ", 0x13: "WRITE_RSP",
    0x1B: "NOTIFY", 0x1D: "INDICATE", 0x52: "WRITE_CMD",
}
DEFAULT_OPS = {0x12, 0x52, 0x1B, 0x1D, 0x0B, 0x01}


def uuid_str(raw: bytes) -> str:
    if len(raw) == 2:
        return f"0x{struct.unpack('<H', raw)[0]:04X}"
    return raw[::-1].hex()


def read_log(path: str) -> bytes:
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as zf:
            name = next(n for n in zf.namelist() if n.endswith("btsnoop_hci.log"))
            return zf.read(name)
    with open(path, "rb") as fh:
        return fh.read()


def iter_records(data: bytes):
    if data[:8] != BTSNOOP_MAGIC:
        raise ValueError("not a btsnoop file")
    buf = io.BytesIO(data[16:])
    while True:
        head = buf.read(24)
        if len(head) < 24:
            return
        _orig, incl, flags, _drops, ts = struct.unpack(">IIIIq", head)
        yield ts, flags, buf.read(incl)


def iter_att(data: bytes):
    """Yield (timestamp, received, conn, opcode, pdu) for single-fragment ATT PDUs."""
    for ts, flags, pkt in iter_records(data):
        if len(pkt) < 9 or pkt[0] != H4_ACL:
            continue
        hdl_flags, _acl_len, l2_len, cid = struct.unpack("<HHHH", pkt[1:9])
        if (hdl_flags >> 12) & 0x3 == 0x1 or cid != ATT_CID:
            continue  # continuation fragment or non-ATT channel
        pdu = pkt[9:9 + l2_len]
        if pdu:
            yield ts, bool(flags & 1), hdl_flags & 0x0FFF, pdu[0], pdu


def to_local(ts_us: int) -> str:
    when = dt.datetime(1970, 1, 1) + dt.timedelta(microseconds=ts_us - EPOCH_DELTA_US)
    return when.strftime("%H:%M:%S.%f")[:-3]


def gatt_map(pdus) -> dict[tuple[int, int], str]:
    """Map (connection, handle) to a service/characteristic description."""
    names: dict[tuple[int, int], str] = {}
    for _ts, _rx, conn, op, pdu in pdus:
        if op == 0x11 and len(pdu) > 2:  # services: start, end, uuid
            size = pdu[1]
            for i in range(2, len(pdu) - size + 1, size):
                start = struct.unpack("<H", pdu[i:i + 2])[0]
                names.setdefault((conn, start), "service " + uuid_str(pdu[i + 4:i + size]))
        elif op == 0x09 and len(pdu) > 2:  # characteristic declarations
            size = pdu[1]
            for i in range(2, len(pdu) - size + 1, size):
                props, value_handle = pdu[i + 2], struct.unpack("<H", pdu[i + 3:i + 5])[0]
                if size in (7, 21):
                    names[(conn, value_handle)] = f"char {uuid_str(pdu[i + 5:i + size])} props=0x{props:02X}"
    return names


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log")
    parser.add_argument("--all", action="store_true", help="print every ATT PDU")
    args = parser.parse_args(argv)

    pdus = list(iter_att(read_log(args.log)))
    handles = gatt_map(pdus)
    print("# GATT handles (conn, handle)")
    for conn, handle in sorted(handles):
        print(f"conn=0x{conn:03X} 0x{handle:04X} {handles[(conn, handle)]}")
    print("# ATT traffic")
    for ts, rx, conn, op, pdu in pdus:
        if not args.all and op not in DEFAULT_OPS:
            continue
        direction = "<-" if rx else "->"
        name = ATT_NAMES.get(op, f"0x{op:02X}")
        if op in (0x12, 0x52, 0x1B, 0x1D) and len(pdu) >= 3:
            handle = struct.unpack("<H", pdu[1:3])[0]
            print(f"{to_local(ts)} conn=0x{conn:03X} {direction} {name} handle=0x{handle:04X} {pdu[3:].hex(' ').upper()}")
        else:
            print(f"{to_local(ts)} conn=0x{conn:03X} {direction} {name} {pdu[1:].hex(' ').upper()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
