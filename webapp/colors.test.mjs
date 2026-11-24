import test from 'node:test';
import assert from 'node:assert/strict';
import { CUSTOM_LIMIT, addCustomColor, replaceCustomColor, loadCustomColors } from './colors.js';

const palette = ['#010203', '#040506', '#070809', '#0a0b0c', '#0d0e0f', '#101112', '#131415'];

test('custom colors append up to seven and never overwrite when full', () => {
  assert.equal(CUSTOM_LIMIT, 7);
  assert.deepEqual(palette.reduce(addCustomColor, []), palette);
  assert.deepEqual(addCustomColor(palette, '#AABBCC'), palette);
});

test('a chosen custom slot is replaced in place', () => {
  assert.deepEqual(replaceCustomColor(palette, 2, '#AABBCC'), [...palette.slice(0, 2), '#aabbcc', ...palette.slice(3)]);
  assert.deepEqual(replaceCustomColor(palette, 2, '#0A0B0C'), palette, 'no duplicates');
  assert.deepEqual(replaceCustomColor(palette, 9, '#aabbcc'), palette, 'index out of range');
  assert.deepEqual(replaceCustomColor(palette, 2, 'red'), palette, 'invalid color');
});

test('custom colors ignore duplicates and invalid picks', () => {
  assert.deepEqual(addCustomColor(palette.slice(0, 3), '#0A0B0C'.replace('0A0B0C', '070809')), palette.slice(0, 3));
  assert.deepEqual(addCustomColor(palette.slice(0, 3), 'red'), palette.slice(0, 3));
});

test('custom colors load sanitized, deduplicated and capped, with an empty fallback', () => {
  const storage = value => ({ getItem: () => value });
  assert.deepEqual(loadCustomColors(storage(JSON.stringify(['bad', ...palette, '#0A0B0C', '#abcdef']))), palette);
  for (const value of [null, '{', '{}']) assert.deepEqual(loadCustomColors(storage(value)), []);
  assert.deepEqual(loadCustomColors({ getItem() { throw new Error('denied'); } }), []);
});
