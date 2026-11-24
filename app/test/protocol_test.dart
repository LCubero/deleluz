// Same vectors as lab/web/protocol.test.mjs.
import 'package:deleluz/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void frame(List<int> actual, String expected) =>
    expect(hex(actual), '7B FF $expected FF BF');

void main() {
  test('chip configuration uses vendor order codes and big-endian pixel counts', () {
    expect(chipOrders, ['RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR', 'RGBW', 'RBGW', 'GRBW', 'GBRW', 'BRGW', 'BGRW']);
    for (var i = 0; i < chipOrders.length; i++) {
      expect(chipConfig(chipOrders[i], 150)[6], i + 1);
    }
    for (final (order, pixels, bytes) in [
      ('GRB', 150, '00 96 03'), ('RGB', 150, '00 96 01'), ('BGR', 150, '00 96 06'),
      ('GRB', 1024, '04 00 03'), ('GRB', 1, '00 01 03'),
    ]) {
      frame(chipConfig(order, pixels), '05 04 $bytes');
    }
    for (final count in [0, 1025]) {
      expect(() => chipConfig('GRB', count), throwsRangeError);
    }
    expect(() => chipConfig('XYZ', 150), throwsRangeError);
  });

  test('power and logical RGB match the capture', () {
    frame(power(true), '04 01 FF FF FF');
    frame(power(false), '04 00 FF FF FF');
    frame(color(255, 0, 0), '07 FF 00 00 00');
    frame(color(0, 128, 255), '07 00 80 FF 00');
    for (final invalid in [-1, 256]) {
      expect(() => color(invalid, 0, 0), throwsRangeError);
      expect(() => color(0, invalid, 0), throwsRangeError);
      expect(() => color(0, 0, invalid), throwsRangeError);
    }
  });

  test('brightness uses floor and preserves the original percent', () {
    for (final (pct, bytes) in [(0, '00 00'), (2, '00 02'), (50, '10 32'), (99, '1F 63'), (100, '20 64')]) {
      frame(brightness(pct), '01 $bytes 00 FF');
    }
    for (final invalid in [-1, 101]) {
      expect(() => brightness(invalid), throwsRangeError);
    }
  });

  test('effect and speed include boundaries and AUTO', () {
    for (final (id, byte) in [(1, '01'), (95, '5F'), (210, 'D2'), (autoEffect, 'FF')]) {
      frame(effect(id), '03 $byte FF FF FF');
    }
    frame(speed(1), '02 01 FF 00 FF');
    frame(speed(100), '02 64 FF 00 FF');
    for (final invalid in [0, 211, 254]) {
      expect(() => effect(invalid), throwsRangeError);
    }
    for (final invalid in [0, 101]) {
      expect(() => speed(invalid), throwsRangeError);
    }
  });

  test('voice mode matches the captured frame and rejects invalid modes', () {
    frame(voiceMode(1), '0B 01 00 FF FF');
    frame(voiceMode(4), '0B 04 00 FF FF');
    for (final invalid in [0, 5]) {
      expect(() => voiceMode(invalid), throwsRangeError);
    }
  });

  test('mic sensitivity matches the verified frame and rejects invalid values', () {
    frame(micSensitivity(0), '0C 00 00 FF FF');
    frame(micSensitivity(5), '0C 05 00 FF FF');
    frame(micSensitivity(95), '0C 5F 00 FF FF');
    frame(micSensitivity(100), '0C 64 00 FF FF');
    for (final invalid in [-1, 101]) {
      expect(() => micSensitivity(invalid), throwsRangeError);
    }
  });
}
