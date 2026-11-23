import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PRESETS, SEND_INTERVAL, presetFrames } from './presets.js';
import { hex } from './protocol.js';

const colors = plan => plan.steps.filter(({ bytes }) => bytes[2] === 7).map(({ bytes }) => hex(bytes.slice(3, 6)));

test('each preset uses whole-strip writes with no sub-throttle delays', () => {
  assert.deepEqual(PRESETS.map(({ id }) => id), ['christmas-moving', 'christmas-glow', 'police', 'siren', 'rasta', 'flashing']);
  for (const { id, interval } of PRESETS) {
    const plan = presetFrames(id, interval);
    assert.equal(hex(plan.setup[0]), '7B FF 04 01 FF FF FF FF BF');
    for (const bytes of [...plan.setup, ...plan.steps.map(step => step.bytes)]) {
      assert.ok([1, 4, 7].includes(bytes[2]));
    }
    assert.ok(plan.steps.every(step => step.interval >= SEND_INTERVAL));
    assert.throws(() => presetFrames(id, SEND_INTERVAL - 1), RangeError);
  }
});

test('Police double flashes and Flashing alternates white with black at the chosen interval', () => {
  assert.deepEqual(colors(presetFrames('police', 150)), ['FF 00 00', '00 00 00', 'FF 00 00', '00 00 FF', '00 00 00', '00 00 FF', '00 00 00']);
  const flashing = presetFrames('flashing', 425);
  assert.deepEqual(colors(flashing), ['FF FF FF', '00 00 00']);
  assert.deepEqual(flashing.steps.map(step => step.interval), [425, 425]);
});

test('holiday and siren ramps include intermediate shades; Rasta changes the whole strip', () => {
  const christmas = colors(presetFrames('christmas-moving', 150));
  assert.ok(['FF 00 00', '00 FF 00', 'FF C8 80', '80 80 00'].every(value => christmas.includes(value)));
  const glow = colors(presetFrames('christmas-glow', 150));
  assert.ok(['FF 00 00', '00 FF 00', '40 00 00', '00 40 00'].every(value => glow.includes(value)));
  const siren = colors(presetFrames('siren', 150));
  assert.ok(['FF 00 00', '00 00 FF', '80 00 80'].every(value => siren.includes(value)));
  assert.deepEqual(colors(presetFrames('rasta', 150)), ['00 FF 00', 'FF FF 00', 'FF 00 00']);
});
