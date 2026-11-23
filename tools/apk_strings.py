"""Print matching DEX string-table entries from an APK (stdlib only)."""

import argparse
import re
import sys
from struct import unpack_from
from zipfile import ZipFile


def dex_strings(data):
    if not data.startswith(b"dex\n"):
        raise ValueError("Not a standard DEX file")
    count, table = unpack_from("<II", data, 0x38)
    for index in range(count):
        (offset,) = unpack_from("<I", data, table + 4 * index)
        while data[offset] & 0x80:  # Skip the ULEB128 UTF-16 length.
            offset += 1
        offset += 1
        end = data.index(0, offset)
        # DEX uses modified UTF-8; preserve encoded UTF-16 surrogate pairs.
        text = data[offset:end].replace(b"\xc0\x80", b"\x00")
        yield text.decode("utf-8", "surrogatepass").encode(
            "utf-16le", "surrogatepass"
        ).decode("utf-16le", "replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("regex")
    args = parser.parse_args()
    pattern = re.compile(args.regex)
    sys.stdout.reconfigure(encoding="utf-8")
    with ZipFile(args.apk) as apk:
        for name in apk.namelist():
            if re.fullmatch(r"classes\d*\.dex", name):
                for text in dex_strings(apk.read(name)):
                    if pattern.search(text):
                        print(f"{name}\t{text}")


if __name__ == "__main__":
    main()
