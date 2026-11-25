import test from 'node:test';
import assert from 'node:assert/strict';
import * as color from './color.js';
import * as fx from './effects.js';
import { createPlayer } from './player.js';

test('disc maps center, radius and clockwise hue to RGB and back', () => {
  assert.deepEqual(color.discRgb(0, 0), [255, 255, 255]);
  assert.deepEqual(color.discRgb(0, -0.5), [255, 128, 128]);
  assert.deepEqual(color.discRgb(0.5, 0), [191, 255, 128]);
  assert.deepEqual(color.discRgb(0, -2), [255, 0, 0]);
  for (const rgb of color.WHITE_PRESETS.map(([, rgb]) => rgb)) {
    assert.deepEqual(color.discRgb(...color.rgbDiscPoint(rgb)), rgb);
  }
  assert.deepEqual(color.WHITE_PRESETS.map(([, rgb]) => rgb), [[255, 200, 128], [255, 228, 196], [255, 255, 255]]);
});

test('effect search folds accents and case, matches padded IDs and groups favorites first', () => {
  assert.deepEqual(fx.effectGroups(' FÓRWARD DREAMING ', new Set([1])), [[1], []]);
  assert.deepEqual(fx.effectGroups('210', new Set()), [[], [210]]);
  assert.deepEqual(fx.effectGroups('01', new Set([101])), [[101], [1, 201]]);
  assert.deepEqual(fx.effectGroups('---', new Set([1])), [[], []]);
});

test('new keys validate and persist favorites and AUTO preferences independently', () => {
  const data = new Map([[fx.EFFECT_FAVORITES_KEY, '[2,2,0,211,"4",null,1.5]'], [fx.AUTO_KEY, '{"seconds":15,"favorites":true}']]);
  const storage = { getItem: key => data.get(key), setItem: (key, value) => data.set(key, value) };
  assert.deepEqual([...fx.loadEffectFavorites(storage)], [2]);
  assert.deepEqual(fx.loadAutoOptions(storage), { seconds: 30, favorites: false });
  assert.equal(fx.saveEffectFavorites(storage, new Set([210, 1])), true);
  assert.deepEqual([...fx.loadEffectFavorites(storage)], [1, 210]);
  assert.equal(fx.saveAutoOptions(storage, { seconds: 300, favorites: true }), true);
  assert.deepEqual(fx.loadAutoOptions(storage), { seconds: 300, favorites: true });
  assert.equal(fx.saveAutoOptions(storage, { seconds: 10, favorites: 1 }), false);
  assert.deepEqual([...data.keys()], [fx.EFFECT_FAVORITES_KEY, fx.AUTO_KEY]);
});

function clock() {
  let time = 0;
  const pending = [];
  return {
    now: () => time,
    sleep: ms => new Promise(resolve => pending.push([time + ms, resolve])),
    async advance(ms) {
      time += ms;
      for (let i = pending.length - 1; i >= 0; i--) {
        if (pending[i][0] <= time) pending.splice(i, 1)[0][1]();
      }
      await Promise.resolve();
    },
  };
}

for (const seconds of [10, 30, 60, 300]) {
  test(`AUTO sends sorted favorite frames every ${seconds}s and wraps`, async () => {
    const time = clock();
    const writes = [];
    const player = createPlayer({ ...time, send: bytes => writes.push([...bytes]) });
    const run = player.play(fx.autoFrames(true, new Set([210, 2])), seconds * 1000, { dwell: true });
    const frame = id => [0x7b, 0xff, 3, id, 255, 255, 255, 255, 0xbf];
    await time.advance(0);
    assert.deepEqual(writes, [frame(2)]);
    await time.advance(seconds * 1000 - 1);
    assert.deepEqual(writes, [frame(2)]);
    await time.advance(1);
    assert.deepEqual(writes, [frame(2), frame(210)]);
    await time.advance(seconds * 1000);
    assert.deepEqual(writes, [frame(2), frame(210), frame(2)]);
    player.stop();
    await time.advance(seconds * 1000);
    await run;
  });
}

for (const change of ['hidden', 'disconnect']) {
  test(`AUTO sends no subsequent frames on ${change}`, async () => {
    const time = clock();
    const writes = [];
    let hidden = false, connected = true;
    const player = createPlayer({ ...time, send: bytes => writes.push(bytes[3]) });
    const run = player.play(fx.autoFrames(false), 30000, { dwell: true, canPlay: () => !hidden && connected });
    await time.advance(0);
    if (change === 'hidden') hidden = true;
    else connected = false;
    await time.advance(30000);
    await run;
    assert.equal(player.playing, false);
    hidden = false;
    connected = true;
    await time.advance(30000);
    assert.deepEqual(writes, [1]);
  });
}

test('AUTO builds the complete catalog in order and no frames for empty favorites', () => {
  assert.deepEqual(fx.autoFrames(false).map(bytes => bytes[3]), Array.from({ length: 210 }, (_, index) => index + 1));
  assert.deepEqual(fx.autoFrames(true), []);
});

test('AUTO begins dwell after a delayed write and does not publish an interrupted frame', async () => {
  const time = clock();
  const writes = [], displayed = [];
  let finishWrite;
  const player = createPlayer({ ...time, send: bytes => {
    writes.push(bytes[3]);
    return new Promise(resolve => { finishWrite = resolve; });
  } });
  const run = player.play(fx.autoFrames(false), 10000, { dwell: true, onFrame: bytes => displayed.push(bytes[3]) });
  await time.advance(500);
  assert.deepEqual(displayed, []);
  finishWrite();
  await time.advance(0);
  await time.advance(9999);
  assert.deepEqual(writes, [1]);
  assert.deepEqual(displayed, [1]);
  await time.advance(1);
  assert.deepEqual(writes, [1, 2]);
  player.stop();
  finishWrite();
  await run;
  assert.deepEqual(displayed, [1]);
});

test('scene and AUTO replace one another in the shared player', async () => {
  const time = clock();
  const writes = [];
  const player = createPlayer({ ...time, send: bytes => writes.push(bytes[3]) });
  const scene = [[0, 0, 0, 90], [0, 0, 0, 91]];
  const first = player.play(scene, 500);
  await time.advance(0);
  const auto = player.play(fx.autoFrames(false), 30000, { dwell: true });
  await time.advance(500);
  assert.deepEqual(writes, [90, 1]);
  const last = player.play(scene, 500);
  await time.advance(0);
  player.stop();
  await time.advance(30000);
  await Promise.all([first, auto, last]);
  assert.deepEqual(writes, [90, 1, 90]);
});
