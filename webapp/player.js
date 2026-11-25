// Plays a page-sequenced mode: the controller cannot store sequences, so the page sends
// one color frame per step and loops until stopped. Only one mode plays at a time.
export const MIN_INTERVAL = 50;

function wait(ms, signal) {
  return new Promise(resolve => {
    const done = () => { clearTimeout(timer); signal?.removeEventListener('abort', done); resolve(); };
    const timer = setTimeout(done, ms);
    signal?.addEventListener('abort', done, { once: true });
  });
}

export function createPlayer({
  send,
  now = () => performance.now(),
  sleep = wait,
}) {
  let run = 0;
  let active = false;
  let dwellWait;

  function stop() {
    run++;
    active = false;
    dwellWait?.abort();
    dwellWait = undefined;
  }

  return {
    get playing() { return active; },
    stop,
    async play(steps, interval, { dwell = false, canPlay = () => true, write = send, onFrame } = {}) {
      if (!Number.isInteger(interval) || interval < MIN_INTERVAL) {
        throw new RangeError(`Step interval must be at least ${MIN_INTERVAL} ms`);
      }
      if (!steps.length) throw new RangeError('A mode needs at least one step');
      stop();
      const mine = run;
      const current = () => mine === run && canPlay();
      const pause = dwell ? new AbortController() : null;
      dwellWait = pause;
      active = true;
      let start;
      try {
        // Effects dwell for a full interval from each successful write, even after queue delays.
        if (dwell) {
          for (let i = 0; current(); i = (i + 1) % steps.length) {
            const bytes = steps[i];
            await write(bytes);
            if (!current()) break;
            onFrame?.(bytes);
            if (current()) await sleep(interval, pause.signal);
          }
          return;
        }
        for (let i = 0; current(); i++) {
          // The clock starts when the first frame actually goes out, so a frame still queued
          // ahead of it (power, brightness) does not shorten the following steps.
          if (i > 0) {
            const due = start + i * interval;
            const wait = due - now();
            if (wait > 0) await sleep(wait);
            if (!current()) break;
            const woke = now();
            const missed = Math.floor((woke - due) / interval);
            if (missed > 0) {
              // Jump to the current frame, then give it a full interval instead of catching up.
              i += missed;
              start = woke - i * interval;
            }
          }
          await write(steps[i % steps.length]);
          if (i === 0) start = now();
        }
      } finally {
        if (mine === run) stop();
      }
    },
  };
}
