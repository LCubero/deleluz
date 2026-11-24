import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EFFECT_NAMES, effectName } from './effects.js';

test('lists one name per controller effect ID 1-210', () => {
  assert.equal(EFFECT_NAMES.length, 210);
  assert.ok(EFFECT_NAMES.every(name => typeof name === 'string' && name.trim() === name && name.length > 0));
});

test('maps IDs to the vendor names', () => {
  assert.equal(effectName(1), 'Forward Dreaming');
  assert.equal(effectName(3), 'Forward 7 Colors');
  assert.equal(effectName(80), 'Strobe White');
  assert.equal(effectName(95), 'Forward Run 7 Colors');
  assert.equal(effectName(210), 'Close Curtain Swab CN/VT');
});

test('returns null outside 1-210', () => {
  for (const id of [0, 211, 255, 1.5, '1', null, undefined]) assert.equal(effectName(id), null);
});
