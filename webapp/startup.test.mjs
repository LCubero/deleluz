import test from 'node:test';
import assert from 'node:assert/strict';
import { createSender } from './sender.js';
import { runStartup } from './startup.js';

test('a slider replacing the queued startup brightness does not abort the scene', async () => {
  let t = 0;
  let release = null;
  let held = true;
  const writes = [];
  const sender = createSender({
    write: async bytes => { writes.push(bytes[0]); },
    interval: 150,
    now: () => t,
    // The throttle wait only ends when the test releases it.
    sleep: ms => (held
      ? new Promise(resolve => { release = () => { held = false; t += ms; resolve(); }; })
      : Promise.resolve().then(() => { t += ms; })),
  });
  const send = (bytes, key) => sender.send(bytes, key);
  const started = runStartup(send, [
    { bytes: Uint8Array.of(1), key: 'power' },
    { bytes: Uint8Array.of(50), key: 'brightness' },
  ], () => true);
  for (let i = 0; i < 50 && !release; i++) await Promise.resolve();
  assert.equal(sender.size, 1, 'startup brightness is queued behind the throttle');
  // The user drags brightness while the startup brightness frame is still queued.
  const slider = send(Uint8Array.of(90), 'brightness');
  release();
  assert.equal(await slider, 'sent');
  assert.equal(await started, true);
  await send(Uint8Array.of(7), 'color'); // first scene frame
  assert.deepEqual(writes, [1, 90, 7]);
});

test('startup stops when its frames are canceled or the run is stale', async () => {
  assert.equal(await runStartup(async () => 'canceled', [{ bytes: Uint8Array.of(1) }], () => true), false);
  assert.equal(await runStartup(async () => 'sent', [{ bytes: Uint8Array.of(1) }], () => false), false);
});
