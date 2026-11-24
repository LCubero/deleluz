import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadState, persistState } from './state.js';

test('invalid saved state cannot overwrite defaults or introduce unexpected fields', () => {
  const defaults = { rgb: [255, 200, 128], on: false, bri: 80, label: ['warmWhite'], scene: 'warm' };
  let invalid = 0;
  const read = value => loadState('state', defaults, [], () => ({ getItem: () => value, invalid: () => invalid++ }));
  assert.deepEqual(read(null), defaults);
  assert.equal(invalid, 0);
  assert.deepEqual(read('{'), defaults);
  assert.deepEqual(read('{"on":true,"rgb":null,"bri":200,"label":{},"scene":42,"mode":{"colors":[]},"unexpected":true}'), { ...defaults, on: true });
  assert.equal(invalid, 2);
  assert.deepEqual(read('{"rgb":[1,2,3],"scene":"sequence:gone","label":"Gone","mode":{"colors":[[1,2,3]],"interval":150}}'), { ...defaults, rgb: [1, 2, 3], scene: null, label: ['colorHex', { hex: '#010203' }], mode: null });
});

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
