import test from 'node:test';
import assert from 'node:assert/strict';
import * as colors from './colors.js';
const { removePaletteColor, movePaletteColor } = colors;

const key = 'deleluz.webapp.palette';
const legacy = 'deleluz.webapp.customColors';
const defaults = ['#00ff00', '#ffc800', '#ff0000'];
const extra = Array.from({ length: 13 }, (_, i) => `#0${(i + 1).toString(16)}0${(i + 1).toString(16)}0${(i + 1).toString(16)}`);
const storage = (entries = {}, invalid) => ({ getItem: name => entries[name] ?? null, invalid });

test('palette defaults have the specified order and color names', () => {
  assert.equal(colors.PALETTE_LIMIT, 15);
  assert.deepEqual(colors.DEFAULT_PALETTE, defaults);
  assert.deepEqual(defaults.map(colors.colorName), ['green', 'yellow', 'red']);
  assert.equal(colors.colorName('#FFC880'), 'warmWhite');
  assert.equal(colors.colorName('#123456'), 'solid');
});

test('a missing palette migrates legacy colors after defaults, deduping and capping at 15', () => {
  assert.deepEqual(colors.loadPalette(storage()), defaults);
  assert.deepEqual(colors.loadPalette(storage({ [legacy]: JSON.stringify(['#FF0000', '#010101', ...extra]) })), [...defaults, ...extra.slice(0, 12)]);
});

test('stored replacements win over legacy colors; corrupt or denied storage falls back', () => {
  const saved = ['#ABCDEF', ...defaults.slice(1)];
  assert.deepEqual(colors.loadPalette(storage({ [key]: JSON.stringify(saved), [legacy]: '["#010101"]' })), ['#abcdef', ...defaults.slice(1)]);
  for (const raw of ['{', 'null', '{}', '["bad"]']) {
    let invalid = false;
    assert.deepEqual(colors.loadPalette(storage({ [key]: raw, [legacy]: '["#010101"]' }, () => { invalid = true; })), defaults);
    assert.equal(invalid, true);
  }
  assert.deepEqual(colors.loadPalette({ getItem() { throw new Error('denied'); } }), defaults);
  assert.deepEqual(colors.loadPalette(storage({ [legacy]: '{' })), defaults);
});

test('adds normalize colors and never overwrite, even when full', () => {
  const full = extra.reduce(colors.addPaletteColor, defaults);
  assert.deepEqual(full, [...defaults, ...extra.slice(0, 12)]);
  assert.strictEqual(colors.addPaletteColor(full, '#aabbcc'), full);
  assert.strictEqual(colors.addPaletteColor(defaults, '#FF0000'), defaults);
  assert.strictEqual(colors.addPaletteColor(defaults, 'red'), defaults);
  assert.deepEqual(colors.addPaletteColor(defaults, '#AABBCC'), [...defaults, '#aabbcc']);
});

test('replaces any slot without mutating the source or accepting duplicates and invalid indexes', () => {
  assert.deepEqual(colors.replacePaletteColor(defaults, 0, '#AABBCC'), ['#aabbcc', ...defaults.slice(1)]);
  assert.equal(defaults[0], '#00ff00');
  for (const index of [-1, defaults.length, 1.5, '0', NaN]) assert.strictEqual(colors.replacePaletteColor(defaults, index, '#aabbcc'), defaults);
  assert.strictEqual(colors.replacePaletteColor(defaults, 0, '#FF0000'), defaults);
  assert.strictEqual(colors.replacePaletteColor(defaults, 0, 'red'), defaults);
});

test('removing palette colors can empty the palette', () => {
  const list = ['#ff0000', '#00ff00', '#0000ff'];
  assert.deepEqual(removePaletteColor(list, 1), ['#ff0000', '#0000ff']);
  assert.deepEqual(removePaletteColor(['#ff0000'], 0), []);
  assert.deepEqual(removePaletteColor(list, 5), list);
});

test('moving a palette color reorders without losing any', () => {
  const list = ['#a00000', '#00a000', '#0000a0', '#a0a000'];
  assert.deepEqual(movePaletteColor(list, 0, 2), ['#00a000', '#0000a0', '#a00000', '#a0a000']);
  assert.deepEqual(movePaletteColor(list, 3, 0), ['#a0a000', '#a00000', '#00a000', '#0000a0']);
  assert.equal(movePaletteColor(list, 1, 1), list);
  assert.equal(movePaletteColor(list, 0, 9), list);
});
