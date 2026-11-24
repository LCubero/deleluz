import { test } from 'node:test';
import assert from 'node:assert/strict';
import { power, color, brightness, effect, speed, voiceMode, CHIP_ORDERS, chipConfig, hex, parseRaw, experimentalFrame } from './protocol.js';

test('chip configuration uses vendor order codes and big-endian pixel counts', () => {
  assert.deepEqual(CHIP_ORDERS, ['RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR', 'RGBW', 'RBGW', 'GRBW', 'GBRW', 'BRGW', 'BGRW']);
  CHIP_ORDERS.forEach((order, index) => assert.equal(chipConfig(order, 150)[6], index + 1));
  for (const [order, pixels, bytes] of [
    ['GRB', 150, '00 96 03'], ['RGB', 150, '00 96 01'], ['BGR', 150, '00 96 06'],
    ['GRB', 1024, '04 00 03'], ['GRB', 1, '00 01 03'],
  ]) frame(chipConfig(order, pixels), `05 04 ${bytes}`);
  for (const count of [0, 1025, 150.5]) assert.throws(() => chipConfig('GRB', count), RangeError);
  assert.throws(() => chipConfig('XYZ', 150), RangeError);
});

function frame(actual, expected) {
  assert.ok(actual instanceof Uint8Array);
  assert.equal(hex(actual), `7B FF ${expected} FF BF`);
}

test('power and logical RGB match the capture', () => {
  frame(power(true), '04 01 FF FF FF');
  frame(power(false), '04 00 FF FF FF');
  frame(color(255, 0, 0), '07 FF 00 00 00');
  frame(color(0, 128, 255), '07 00 80 FF 00');
  assert.throws(() => power(1));
  for (const invalid of [-1, 256, 1.5, '0', NaN]) {
    assert.throws(() => color(invalid, 0, 0));
    assert.throws(() => color(0, invalid, 0));
    assert.throws(() => color(0, 0, invalid));
  }
});

test('brightness uses floor and preserves the original percent', () => {
  for (const [pct, bytes] of [[0, '00 00'], [2, '00 02'], [50, '10 32'], [99, '1F 63'], [100, '20 64']]) {
    frame(brightness(pct), `01 ${bytes} 00 FF`);
  }
  for (const invalid of [-1, 101, 1.5, '50', Infinity]) assert.throws(() => brightness(invalid));
});

test('effect and speed include boundaries and AUTO', () => {
  for (const [id, byte] of [[1, '01'], [95, '5F'], [210, 'D2'], ['AUTO', 'FF'], [255, 'FF']]) {
    frame(effect(id), `03 ${byte} FF FF FF`);
  }
  frame(speed(1), '02 01 FF 00 FF');
  frame(speed(100), '02 64 FF 00 FF');
  for (const invalid of [0, 211, 254, '95', 1.5]) assert.throws(() => effect(invalid));
  for (const invalid of [0, 101, '50', 1.5]) assert.throws(() => speed(invalid));
});

test('voice mode matches the captured frame and rejects invalid modes', () => {
  frame(voiceMode(1), '0B 01 00 FF FF');
  frame(voiceMode(4), '0B 04 00 FF FF');
  for (const invalid of [0, 5, 1.5, '1', NaN]) assert.throws(() => voiceMode(invalid), RangeError);
});

test('raw parser checks framing and length', () => {
  assert.deepEqual(parseRaw('7b ff 04 01 ff ff ff ff bf'), power(true));
  assert.deepEqual(parseRaw('7bff0401ffffffffbf'), power(true));
  for (const invalid of ['7B FF 04 01 FF FF FF FF', '2A 02 A1 23 45 67 F6 39 AF', 'zz', '7BFF0401FFFFFFFFBF00', '7 B FF 04 01 FF FF FF FF BF']) {
    assert.throws(() => parseRaw(invalid));
  }
});

test('experimental writes require canonical frames and exact captures for the dedicated gate', () => {
  const chip = '7B FF 05 04 00 96 03 FF BF';
  const handshake = '2A 02 A1 23 45 67 F6 39 AF';
  for (const captured of [chip, handshake]) {
    assert.throws(() => experimentalFrame(captured));
    assert.equal(hex(experimentalFrame(captured, true)), captured);
  }
  for (const risky of ['7B FF 05 04 00 97 03 FF BF', '2A 02 A1 23 45 67 F6 38 AF', '7B FF 06 01 FF FF FF FF BF', '7B FF 01 20 00 00 FF FF BF']) {
    assert.throws(() => experimentalFrame(risky, true));
  }
  for (const safe of [power(false), color(1, 2, 3), brightness(50), effect(210), effect('AUTO'), speed(100)]) {
    assert.deepEqual(experimentalFrame(hex(safe)), safe);
  }
});
