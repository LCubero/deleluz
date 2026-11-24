import test from 'node:test';
import assert from 'node:assert/strict';
import { loadScenes, saveScene, deleteScene, SCENES_KEY } from './scenes.js';

const storage = () => new MapStorage();
class MapStorage extends Map {
  getItem(key) { return this.get(key) ?? null; }
  setItem(key, value) { this.set(key, value); }
}
const solid = { rgb: [255, 0, 120] };
const page = { preset: 'police', interval: 200 };

test('scenes round-trip solid and page modes with trimmed names', () => {
  const store = storage();
  saveScene(store, ' Pink ', solid);
  saveScene(store, 'Police', page);
  assert.deepEqual(loadScenes(store), [{ name: 'Pink', ...solid }, { name: 'Police', ...page }]);
});

test('invalid names leave stored scenes unchanged', () => {
  const store = storage();
  saveScene(store, 'Pink', solid);
  const original = store.getItem(SCENES_KEY);
  for (const name of ['', '   ', 'x'.repeat(31)]) {
    assert.throws(() => saveScene(store, name, page), /1–30/);
    assert.equal(store.getItem(SCENES_KEY), original);
  }
});

test('case-insensitive duplicates leave stored scenes unchanged', () => {
  const store = storage();
  saveScene(store, 'Pink', solid);
  const original = store.getItem(SCENES_KEY);
  assert.throws(() => saveScene(store, ' pink ', page), /already exists/);
  assert.equal(store.getItem(SCENES_KEY), original);
});

test('corrupt JSON or a non-array yields an empty list', () => {
  const store = storage();
  for (const value of ['{broken', '{}']) {
    store.setItem(SCENES_KEY, value);
    assert.deepEqual(loadScenes(store), []);
  }
});

test('delete removes only the named scene', () => {
  const store = storage();
  saveScene(store, 'Pink', solid);
  saveScene(store, 'Police', page);
  deleteScene(store, 'Pink');
  assert.deepEqual(loadScenes(store), [{ name: 'Police', ...page }]);
});
