import test from 'node:test';
import assert from 'node:assert/strict';
import { createSender } from './sender.js';

function fakeClock() {
  let t = 0;
  return { now: () => t, sleep: async ms => { t += ms; } };
}

function recorder(clock, fail = () => false) {
  const writes = [];
  return {
    writes,
    write: async bytes => {
      if (fail(bytes)) throw new Error(`write failed ${bytes[0]}`);
      writes.push({ at: clock.now(), byte: bytes[0] });
    },
  };
}

test('writes are spaced at least the interval apart', async () => {
  const clock = fakeClock();
  const rec = recorder(clock);
  const sender = createSender({ write: rec.write, interval: 150, ...clock });
  const results = await Promise.all([1, 2, 3].map(n => sender.send(Uint8Array.of(n), `k${n}`)));
  assert.deepEqual(results, ['sent', 'sent', 'sent']);
  assert.deepEqual(rec.writes.map(w => w.byte), [1, 2, 3]);
  assert.deepEqual(rec.writes.map(w => w.at), [0, 150, 300]);
});

test('a newer frame replaces a pending frame with the same key', async () => {
  const clock = fakeClock();
  const rec = recorder(clock);
  const sender = createSender({ write: rec.write, interval: 150, ...clock });
  const first = sender.send(Uint8Array.of(1), 'power');
  const a = sender.send(Uint8Array.of(10), 'brightness');
  const b = sender.send(Uint8Array.of(20), 'brightness');
  const c = sender.send(Uint8Array.of(30), 'brightness');
  assert.deepEqual(await Promise.all([first, a, b, c]), ['sent', 'replaced', 'replaced', 'sent']);
  assert.deepEqual(rec.writes.map(w => w.byte), [1, 30]);
});

test('frames without a key are never replaced', async () => {
  const clock = fakeClock();
  const rec = recorder(clock);
  const sender = createSender({ write: rec.write, interval: 150, ...clock });
  await Promise.all([sender.send(Uint8Array.of(1)), sender.send(Uint8Array.of(2))]);
  assert.deepEqual(rec.writes.map(w => w.byte), [1, 2]);
});

test('a failed write rejects that send and the queue continues', async () => {
  const clock = fakeClock();
  const rec = recorder(clock, bytes => bytes[0] === 2);
  const sender = createSender({ write: rec.write, interval: 150, ...clock });
  const results = await Promise.allSettled([1, 2, 3].map(n => sender.send(Uint8Array.of(n), `k${n}`)));
  assert.equal(results[0].value, 'sent');
  assert.equal(results[1].status, 'rejected');
  assert.match(results[1].reason.message, /write failed 2/);
  assert.equal(results[2].value, 'sent');
  assert.deepEqual(rec.writes.map(w => w.byte), [1, 3]);
});

test('cancel drops unsent frames and resolves them as canceled', async () => {
  const clock = fakeClock();
  const rec = recorder(clock);
  const sender = createSender({ write: rec.write, interval: 150, ...clock });
  const sends = [1, 2, 3].map(n => sender.send(Uint8Array.of(n), `k${n}`));
  sender.cancel();
  const results = await Promise.all(sends);
  assert.equal(results.filter(r => r === 'canceled').length >= 2, true);
  assert.equal(rec.writes.length <= 1, true);
  assert.equal(await sender.send(Uint8Array.of(9), 'after'), 'sent');
});
