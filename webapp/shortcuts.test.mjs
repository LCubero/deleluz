import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SHORTCUTS_KEY, MAX_SHORTCUTS, DEFAULT_SHORTCUTS, loadShortcuts, saveShortcuts,
  addShortcut, replaceShortcut, removeShortcut, moveShortcut, gridColumns, filterShortcuts,
} from './shortcuts.js';

const presets = ['police', 'rasta'];
const store = value => {
  const data = new Map(value === undefined ? [] : [[SHORTCUTS_KEY, value]]);
  return { getItem: key => data.get(key) ?? null, setItem: (key, v) => data.set(key, v), data };
};
const red = { kind: 'color', rgb: [255, 0, 0] };
const police = { kind: 'scene', preset: 'police' };

test('defaults are warm white, cool white, blue, green, yellow and red', () => {
  assert.deepEqual(DEFAULT_SHORTCUTS.map(s => s.name), ['warmWhite', 'coolWhite']);
  assert.equal(MAX_SHORTCUTS, 6);
  assert.deepEqual(loadShortcuts(store(), presets), DEFAULT_SHORTCUTS);
});

test('corrupt or unreadable storage falls back to the defaults', () => {
  assert.deepEqual(loadShortcuts(store('{oops'), presets), DEFAULT_SHORTCUTS);
  assert.deepEqual(loadShortcuts(store('{"a":1}'), presets), DEFAULT_SHORTCUTS);
  assert.deepEqual(loadShortcuts({ getItem() { throw new Error('denied'); } }, presets), DEFAULT_SHORTCUTS);
});

test('loading keeps valid items, drops invalid ones, caps at six and keeps an empty list', () => {
  const list = [red, police, { kind: 'scene', preset: 'unknown' }, { kind: 'color', rgb: [256, 0, 0] }, { kind: 'effect', id: 3 }];
  assert.deepEqual(loadShortcuts(store(JSON.stringify(list)), presets), [red, police]);
  assert.equal(loadShortcuts(store(JSON.stringify(Array(9).fill(red))), presets).length, 6);
  assert.deepEqual(loadShortcuts(store('[]'), presets), []);
});

test('sequence shortcuts round-trip only while their saved scene exists', () => {
  const sequence = { kind: 'sequence', id: '1' };
  const stale = { kind: 'sequence', id: '2' };
  const s = store();
  assert.equal(saveShortcuts(s, [stale, police, sequence, { ...sequence, id: 1 }]), true);
  assert.deepEqual(loadShortcuts(s, presets, ['1']), [police, sequence]);
  assert.deepEqual(loadShortcuts(s, presets), [police]);
  assert.deepEqual(filterShortcuts([police, sequence], presets, []), [police]);
});

test('saving round-trips and reports a storage failure without throwing', () => {
  const s = store();
  assert.equal(saveShortcuts(s, [police, red]), true);
  assert.deepEqual(loadShortcuts(s, presets), [police, red]);
  assert.equal(saveShortcuts({ setItem() { throw new Error('quota'); } }, [red]), false);
});

test('list operations add up to six, replace, remove and move', () => {
  const six = Array(6).fill(red);
  assert.equal(addShortcut(six, police).length, 6);
  assert.deepEqual(addShortcut([red], police), [red, police]);
  assert.deepEqual(replaceShortcut([red, red], 1, police), [red, police]);
  assert.deepEqual(removeShortcut([red, police], 0), [police]);
  assert.deepEqual(moveShortcut(['a', 'b', 'c', 'd'], 0, 2), ['b', 'c', 'a', 'd']);
  assert.deepEqual(moveShortcut(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
  assert.deepEqual(moveShortcut(['a', 'b'], 0, 5), ['a', 'b']);
});

test('grid columns follow the number of cells', () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6].map(gridColumns), [1, 2, 3, 2, 3, 3]);
});
