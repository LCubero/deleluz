// Throttled BLE write queue. The controller drops frames sent too fast (lab: 150 ms floor),
// so writes are spaced by `interval`. A frame with a key replaces any unsent frame with the
// same key (latest wins), so dragging a slider never builds a backlog.
export function createSender({
  write,
  interval = 150,
  now = () => performance.now(),
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
}) {
  let pending = [];
  let running = false;
  let nextAt = -Infinity;

  async function drain() {
    running = true;
    try {
      while (pending.length) {
        const wait = nextAt - now();
        if (wait > 0) await sleep(wait);
        const item = pending.shift();
        if (!item) continue;
        nextAt = now() + interval;
        try {
          await write(item.bytes);
          item.resolve('sent');
        } catch (error) {
          item.reject(error);
        }
      }
    } finally {
      running = false;
    }
  }

  return {
    send(bytes, key) {
      return new Promise((resolve, reject) => {
        if (key !== undefined) {
          const index = pending.findIndex(item => item.key === key);
          if (index >= 0) {
            pending[index].resolve('replaced');
            pending[index] = { bytes, key, resolve, reject };
            return;
          }
        }
        pending.push({ bytes, key, resolve, reject });
        if (!running) drain();
      });
    },
    cancel() {
      const dropped = pending;
      pending = [];
      for (const item of dropped) item.resolve('canceled');
    },
    get size() { return pending.length; },
  };
}
