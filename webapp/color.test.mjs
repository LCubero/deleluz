import test from 'node:test';
import assert from 'node:assert/strict';
import { hueToRgb, hueFromPoint, rgbCss } from './color.js';

test('hue maps to full-saturation RGB at the wheel anchors', () => {
  assert.deepEqual(hueToRgb(0), [255, 0, 0]);
  assert.deepEqual(hueToRgb(60), [255, 255, 0]);
  assert.deepEqual(hueToRgb(120), [0, 255, 0]);
  assert.deepEqual(hueToRgb(180), [0, 255, 255]);
  assert.deepEqual(hueToRgb(240), [0, 0, 255]);
  assert.deepEqual(hueToRgb(300), [255, 0, 255]);
  assert.deepEqual(hueToRgb(360), [255, 0, 0]);
});

test('hue is measured clockwise from the top, like the CSS conic gradient', () => {
  assert.equal(hueFromPoint(0, -10), 0);
  assert.equal(hueFromPoint(10, 0), 90);
  assert.equal(hueFromPoint(0, 10), 180);
  assert.equal(hueFromPoint(-10, 0), 270);
});

test('rgbCss formats a CSS color', () => {
  assert.equal(rgbCss([255, 200, 128]), 'rgb(255 200 128)');
});
