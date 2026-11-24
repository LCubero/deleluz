import test from 'node:test';
import assert from 'node:assert/strict';
import { createPlayer } from './player.js';

function harness(maxSends) {
  let t = 0;
  const sent = [];
  const player = createPlayer({
    now: () => t,
    sleep: async ms => { t += ms; },
    send: async bytes => {
      sent.push({ at: t, byte: bytes[0] });
      if (sent.length >= maxSends) player.stop();
      return 'sent';
    },
  });
  return { player, sent };
}

test('loops the steps at the requested interval until stopped', async () => {
  const { player, sent } = harness(5);
  await player.play([Uint8Array.of(1), Uint8Array.of(2)], 50);
  assert.deepEqual(sent.map(s => s.byte), [1, 2, 1, 2, 1]);
  assert.deepEqual(sent.map(s => s.at), [0, 50, 100, 150, 200]);
  assert.equal(player.playing, false);
});

test('a slow first send does not shorten the following steps', async () => {
  let t = 0;
  const sent = [];
  const player = createPlayer({
    now: () => t,
    sleep: async ms => { t += ms; },
    send: async bytes => {
      if (!sent.length) t += 150; // first frame waits behind a queued power/brightness frame
      sent.push(t);
      if (sent.length >= 4) player.stop();
      return 'sent';
    },
  });
  await player.play([Uint8Array.of(1), Uint8Array.of(2)], 200);
  assert.deepEqual(sent.slice(1).map((at, i) => at - sent[i]), [200, 200, 200]);
});

test('rejects an interval below the 50 ms floor and sends nothing', async () => {
  const { player, sent } = harness(1);
  await assert.rejects(player.play([Uint8Array.of(1)], 49), /50/);
  assert.equal(sent.length, 0);
});

test('starting a new mode stops the previous one', async () => {
  let t = 0;
  const sent = [];
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const player = createPlayer({
    now: () => t,
    sleep: async ms => { t += ms; await gate; },
    send: async bytes => { sent.push(bytes[0]); return 'sent'; },
  });
  const first = player.play([Uint8Array.of(1)], 200);
  const second = player.play([Uint8Array.of(2)], 200);
  player.stop();
  release();
  await Promise.all([first, second]);
  assert.equal(sent.includes(1) && sent.lastIndexOf(1) > sent.indexOf(2), false);
});
