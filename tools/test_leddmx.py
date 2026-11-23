"""Frame tests for tools/leddmx.py. Run: python -B -m unittest discover -s tools"""

import unittest

import leddmx


class FrameTests(unittest.TestCase):
    def test_confirmed_frames_match_capture(self):
        self.assertEqual(leddmx.frame("on").hex(" ").upper(), "7B FF 04 01 FF FF FF FF BF")
        self.assertEqual(leddmx.frame("off").hex(" ").upper(), "7B FF 04 00 FF FF FF FF BF")
        self.assertEqual(leddmx.frame("color", "#FF0000").hex(" ").upper(), "7B FF 07 FF 00 00 00 FF BF")
        self.assertEqual(leddmx.frame("brightness", "99").hex(" ").upper(), "7B FF 01 1F 63 00 FF FF BF")
        self.assertEqual(leddmx.frame("brightness", "50").hex(" ").upper(), "7B FF 01 10 32 00 FF FF BF")
        self.assertEqual(leddmx.frame("brightness", "2").hex(" ").upper(), "7B FF 01 00 02 00 FF FF BF")

    def test_every_frame_is_nine_bytes_with_markers(self):
        for args in (("on",), ("off",), ("color", "00ff00"), ("brightness", "100")):
            data = leddmx.frame(*args)
            self.assertEqual((len(data), data[0], data[-1]), (9, 0x7B, 0xBF))

    def test_parse_hex_accepts_only_nine_framed_bytes(self):
        self.assertEqual(leddmx.parse_hex("7b ff 04 01 ff ff ff ff bf"), leddmx.frame("on"))
        for bad in ("7B FF 04 01 FF FF FF FF", "2A 02 A1 23 45 67 F6 39 AF", "zz", "7BFF0401FFFFFFFFBF00"):
            with self.assertRaises(ValueError):
                leddmx.parse_hex(bad)

    def test_rejects_out_of_range_values(self):
        for args in (("brightness", "101"), ("brightness", "-1"), ("color", "#12345"), ("color", "GG0000"), ("blink",)):
            with self.assertRaises(ValueError):
                leddmx.frame(*args)


if __name__ == "__main__":
    unittest.main()
