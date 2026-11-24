import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stripPixels } from './strip-settings.js';

test('strip settings round the product and reject invalid inputs and totals', () => {
  for (const [density, length, total] of [[30, 5, 150], [30, 2.5, 75], [3, 2.5, 8], [1, 1, 1], [512, 2, 1024]]) {
    assert.equal(stripPixels(density, length), total);
  }
  for (const [density, length] of [[0, 5], [30, 0], [NaN, 5], [30, NaN], [-30, -5], [1, 0.4], [1025, 1], [30, Infinity]]) {
    assert.equal(stripPixels(density, length), null);
  }
});

test('a typed LED total must be a whole number from 1 to 1024', async () => {
  const { validPixels } = await import('./strip-settings.js');
  for (const total of [1, 100, 150, 1024]) assert.equal(validPixels(total), total);
  for (const total of [0, -1, 1025, 150.5, NaN, Infinity]) assert.equal(validPixels(total), null);
});
