// Wire format: docs/PROTOCOL.md. Mirrors lab/web/protocol.js byte for byte.
import 'dart:typed_data';

int _integer(int value, int min, int max, String label) {
  if (value < min || value > max) {
    throw RangeError('$label must be an integer from $min to $max');
  }
  return value;
}

Uint8List _framed(int op, int a, int b, int c, int d) =>
    Uint8List.fromList([0x7b, 0xff, op, a, b, c, d, 0xff, 0xbf]);

Uint8List power(bool on) => _framed(4, on ? 1 : 0, 255, 255, 255);

Uint8List color(int r, int g, int b) => _framed(7, _integer(r, 0, 255, 'Red'),
    _integer(g, 0, 255, 'Green'), _integer(b, 0, 255, 'Blue'), 0);

Uint8List brightness(int pct) {
  _integer(pct, 0, 100, 'Brightness');
  return _framed(1, pct * 32 ~/ 100, pct, 0, 255);
}

/// Built-in effect 1-210, or [autoEffect] for the AUTO cycle.
const autoEffect = 255;

Uint8List effect(int id) => _framed(
    3, id == autoEffect ? 255 : _integer(id, 1, 210, 'Effect'), 255, 255, 255);

Uint8List speed(int pct) => _framed(2, _integer(pct, 1, 100, 'Speed'), 255, 0, 255);

Uint8List voiceMode(int mode) =>
    _framed(0x0b, _integer(mode, 1, 4, 'Voice mode'), 0, 255, 255);

/// Higher value = more sensitive (lab L59).
Uint8List micSensitivity(int pct) =>
    _framed(0x0c, _integer(pct, 0, 100, 'Mic sensitivity'), 0, 255, 255);

const chipOrders = [
  'RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR', //
  'RGBW', 'RBGW', 'GRBW', 'GBRW', 'BRGW', 'BGRW',
];

Uint8List chipConfig(String order, int pixels) {
  final code = chipOrders.indexOf(order) + 1;
  if (code == 0) throw RangeError('Unknown chip color order');
  _integer(pixels, 1, 1024, 'Pixel count');
  return _framed(5, 4, pixels >> 8, pixels & 0xff, code);
}

String hex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');
