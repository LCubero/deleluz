import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SEQUENCES_KEY, loadSequences, saveSequences, createSequence, updateSequence, renameSequence,
  removeSequence, setColor, addColor, removeColor, moveColor, speedPercent, intervalFromSpeed,
} from './sequences.js';

const defaults = [[0, 255, 0], [255, 200, 0], [255, 0, 0]];
const storage = value => ({ getItem: key => key === SEQUENCES_KEY ? value : null });

test('speed is linear from 0% slowest to 100% fastest', () => {
  for (const [percent, interval] of [[0, 2000], [50, 1075], [100, 150]]) {
    assert.equal(intervalFromSpeed(percent), interval);
    assert.equal(speedPercent(interval), percent);
  }
  for (let percent = 0; percent <= 100; percent++) {
    assert.ok(Math.abs(speedPercent(intervalFromSpeed(percent)) - percent) <= 1);
  }
  assert.equal(intervalFromSpeed(-1), 2000);
  assert.equal(speedPercent(149), 100);
});

test('creates independent defaults, with first free name and at most 12 sequences', () => {
  assert.equal(SEQUENCES_KEY, 'deleluz.webapp.sequences');
  const first = createSequence([]);
  assert.deepEqual(first[0], { id: first[0].id, name: 'Secuencia 1', colors: defaults, interval: 500, bri: 80 });
  const second = createSequence(first);
  assert.notEqual(second[0].id, second[1].id);
  assert.notEqual(second[0].colors[0], second[1].colors[0]);
  assert.equal(createSequence(removeSequence(second, first[0].id)).at(-1).name, 'Secuencia 1');
  assert.equal(createSequence([], n => `Sequence ${n}`)[0].name, 'Sequence 1');
  let items = [];
  for (let i = 0; i < 13; i++) items = createSequence(items);
  assert.equal(items.length, 12);
});

test('rename trims the name and accepts exactly 24 characters', () => {
  const items = createSequence(createSequence([]));
  const name = 'x'.repeat(24);
  const next = renameSequence(items, items[0].id, ` ${name} `);
  assert.equal(next[0].name, name);
  assert.equal(next[1], items[1]);
  assert.equal(items[0].name, 'Secuencia 1');
  assert.equal(renameSequence(items, items[0].id, ' SECUENCIA 1 ')[0].name, 'SECUENCIA 1');
  assert.equal(renameSequence(items, 'missing', name), items);
});

for (const [label, name] of [['an empty', '  '], ['an oversized', 'x'.repeat(25)], ['a duplicate', ' sECUENCIA 2 ']]) {
  test(`rename rejects ${label} name`, () => {
    const items = createSequence(createSequence([]));
    assert.equal(renameSequence(items, items[0].id, name), items);
  });
}

test('create rejects oversized and blank names and skips case-insensitive matches', () => {
  const items = createSequence([]);
  assert.equal(createSequence(items, () => 'x'.repeat(25)), items);
  assert.equal(createSequence(items, () => '  '), items);
  assert.equal(createSequence(items, n => ` secuencia ${n} `).at(-1).name, 'secuencia 2');
});

test('load rejects corrupt and invalid entries and caps the validated list', () => {
  const [valid] = createSequence([]);
  const invalid = [null, { ...valid, id: '' }, { ...valid, name: ' ' }, { ...valid, colors: [] },
    { ...valid, colors: [[0, 0, 256]] }, { ...valid, colors: Array(9).fill([0, 0, 0]) },
    { ...valid, interval: 149 }, { ...valid, interval: 2001 }, { ...valid, bri: 0 }, { ...valid, bri: 101 }];
  assert.deepEqual(loadSequences(storage(JSON.stringify([...invalid, valid, valid]))), [valid]);
  assert.deepEqual(loadSequences(storage('{')), []);
  assert.deepEqual(loadSequences(storage('{}')), []);
  assert.deepEqual(loadSequences({ getItem() { throw new Error(); } }), []);
  const many = Array.from({ length: 13 }, (_, i) => ({ ...valid, id: `${i}` }));
  assert.equal(loadSequences(storage(JSON.stringify(many))).length, 12);
});

test('save round trips and reports storage errors without throwing', () => {
  const items = createSequence([]);
  let raw;
  assert.equal(saveSequences({ setItem(key, value) { assert.equal(key, SEQUENCES_KEY); raw = value; } }, items), true);
  assert.deepEqual(loadSequences(storage(raw)), items);
  assert.equal(saveSequences({ setItem() { throw new Error(); } }, items), false);
});

test('updates only the matching sequence and rejects invalid settings', () => {
  const items = createSequence(createSequence([]));
  const [{ id }] = items;
  const next = updateSequence(items, id, { interval: 150, bri: 100 });
  assert.equal(next[0].interval, 150);
  assert.equal(next[0].bri, 100);
  assert.equal(next[1], items[1]);
  assert.equal(items[0].interval, 500);
  assert.deepEqual(updateSequence(next, id, { bri: 1.5 }), next);
  assert.equal(updateSequence(next, id, { name: ' SECUENCIA 2 ' })[0], next[0]);
  assert.deepEqual(updateSequence(next, 'missing', { interval: 2000 }), next);
  assert.deepEqual(removeSequence(next, id), [items[1]]);
});

test('color edits are immutable and enforce valid indices and 1–8 colors', () => {
  const [item] = createSequence([]);
  const rgb = [0, 42, 255];
  const changed = setColor(item, 1, rgb);
  assert.deepEqual(changed.colors, [defaults[0], rgb, defaults[2]]);
  assert.notEqual(changed.colors[1], rgb);
  assert.deepEqual(item.colors, defaults);
  assert.equal(setColor(item, -1, rgb), item);
  assert.equal(setColor(item, 0, [0, 0, -1]), item);
  let next = changed;
  for (let i = 0; i < 8; i++) next = addColor(next);
  assert.equal(next.colors.length, 8);
  assert.deepEqual(removeColor(changed, 1).colors, [defaults[0], defaults[2]]);
  for (let i = 0; i < 8; i++) next = removeColor(next, 0);
  assert.equal(next.colors.length, 1);
  assert.equal(removeColor(next, 0), next);
});

test('moves a color to its final index in either direction without changing the original', () => {
  const [item] = createSequence([]);
  const moved = moveColor(item, 0, 2);
  assert.deepEqual(moved, { ...item, colors: [defaults[1], defaults[2], defaults[0]] });
  assert.deepEqual(moveColor(moved, 2, 0), item);
  assert.deepEqual(item.colors, defaults);
});

test('moving a color to the same or an invalid index is a no-op', () => {
  const [item] = createSequence([]);
  for (const [from, to] of [[1, 1], [-1, 0], [3, 0], [0, 3], [1.5, 0], [0, '1']]) {
    assert.equal(moveColor(item, from, to), item);
  }
});
