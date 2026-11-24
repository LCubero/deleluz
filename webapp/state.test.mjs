import { test } from 'node:test';
import assert from 'node:assert/strict';
import { persistState } from './state.js';

test('state persistence does not interrupt a command when storage fails', () => {
  const state = { on: false };
  for (const getStorage of [
    () => { throw new Error('Storage access denied'); },
    () => ({ setItem() { throw new Error('Quota exceeded'); } }),
  ]) {
    assert.doesNotThrow(() => persistState('state', state, getStorage));
    assert.deepEqual(state, { on: false });
  }
});

test('state persistence writes the snapshot when storage is available', () => {
  const writes = [];
  persistState('state', { on: true }, () => ({ setItem: (...args) => writes.push(args) }));
  assert.deepEqual(writes, [['state', '{"on":true}']]);
});
