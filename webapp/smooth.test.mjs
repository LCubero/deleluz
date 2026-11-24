import assert from 'node:assert/strict';
import { test } from 'node:test';
import { presetFrames } from '../lab/web/presets.js';
import { smoothSteps } from './smooth.js';

for (const [id, interval] of [['christmas-moving', 200], ['christmas-glow', 300], ['siren', 150], ['rasta', 650], ['rasta', 260], ['rasta', 180]]) {
  test(`${id} at ${interval} ms preserves anchors and adds evenly spaced frames`, () => {
    const { steps } = presetFrames(id, interval);
    const result = smoothSteps(id, steps);
    const k = Math.max(1, Math.floor(interval / 50));
    assert.equal(result.length, steps.length * k);
    assert.deepEqual(result.filter((_, i) => i % k === 0).map(s => s.bytes), steps.map(s => s.bytes));
    assert.ok(result.every(s => Number.isInteger(s.interval) && s.interval >= 50 && s.interval === result[0].interval));
    assert.ok(Math.abs(k * result[0].interval - interval) <= 25);
  });
}

test('interpolates Rasta across both a forward step and the wrap', () => {
  const { steps } = presetFrames('rasta', 200);
  const result = smoothSteps('rasta', steps);
  assert.deepEqual([...result[2].bytes], [0x7b, 0xff, 0x07, 128, 255, 0, 0, 0xff, 0xbf]);
  assert.deepEqual([...result.at(-1).bytes.slice(3, 6)], [64, 191, 0]);
});

for (const id of ['police', 'flashing']) {
  test(`${id} keeps its hard cuts`, () => {
    const { steps } = presetFrames(id, 180);
    assert.equal(smoothSteps(id, steps), steps);
  });
}

test('sub-steps never stretch the chosen step interval', async () => {
  const { smoothSteps } = await import('./smooth.js');
  const { color } = await import('../lab/web/protocol.js');
  for (const interval of [150, 180, 230, 650, 2000]) {
    const steps = [{ bytes: color(255, 0, 0), interval }, { bytes: color(0, 255, 0), interval }];
    const out = smoothSteps('rasta', steps);
    const perStep = out.length / steps.length;
    assert.ok(out[0].interval >= 50, `gap ${out[0].interval} >= 50 for ${interval}`);
    assert.ok(Math.abs(perStep * out[0].interval - interval) <= perStep, `${perStep} x ${out[0].interval} ≈ ${interval}`);
  }
});
