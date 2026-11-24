import test from 'node:test';
import assert from 'node:assert/strict';
import { addCustomColor, loadCustomColors } from './colors.js';

const palette = ['#010203', '#040506', '#070809', '#0a0b0c'];

test('custom colors append through four, then replace only the last slot', () => {
  assert.deepEqual(palette.reduce(addCustomColor, []), palette);
  assert.deepEqual(addCustomColor(palette, '#AABBCC'), [...palette.slice(0, 3), '#aabbcc']);
  assert.equal(palette[3], '#0a0b0c');
});

test('custom colors ignore duplicates and invalid picks', () => {
  assert.deepEqual(addCustomColor(palette, '#0A0B0C'), palette);
  assert.deepEqual(addCustomColor(palette, 'red'), palette);
});

test('custom colors load sanitized, deduplicated and capped, with an empty fallback', () => {
  const storage = value => ({ getItem: () => value });
  assert.deepEqual(loadCustomColors(storage(JSON.stringify(['bad', ...palette, '#0A0B0C', '#abcdef']))), palette);
  for (const value of [null, '{', '{}']) assert.deepEqual(loadCustomColors(storage(value)), []);
  assert.deepEqual(loadCustomColors({ getItem() { throw new Error('denied'); } }), []);
});
