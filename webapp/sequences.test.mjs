import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SEQUENCES_KEY, loadSequences, saveSequences, createSequence, updateSequence,
  removeSequence, setColor, addColor, removeColor,
} from './sequences.js';

const defaults = [[255, 0, 0], [0, 255, 0], [0, 0, 255]];
const storage = value => ({ getItem: key => key === SEQUENCES_KEY ? value : null });

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
