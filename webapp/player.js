// Plays a page-sequenced mode: the controller cannot store sequences, so the page sends
// one color frame per step and loops until stopped. Only one mode plays at a time.
export const MIN_INTERVAL = 50;

export function createPlayer({
  send,
  now = () => performance.now(),
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
}) {
  let run = 0;
  let active = false;

  return {
    get playing() { return active; },
    stop() { run++; active = false; },
    async play(steps, interval) {
      if (!Number.isInteger(interval) || interval < MIN_INTERVAL) {
        throw new RangeError(`Step interval must be at least ${MIN_INTERVAL} ms`);
      }
      if (!steps.length) throw new RangeError('A mode needs at least one step');
      const mine = ++run;
      active = true;
      let start;
      try {
        for (let i = 0; mine === run; i++) {
          // The clock starts when the first frame actually goes out, so a frame still queued
          // ahead of it (power, brightness) does not shorten the following steps.
          if (i > 0) {
            const due = start + i * interval;
            const wait = due - now();
            if (wait > 0) await sleep(wait);
            if (mine !== run) break;
            const woke = now();
            const missed = Math.floor((woke - due) / interval);
            if (missed > 0) {
              // Jump to the current frame, then give it a full interval instead of catching up.
              i += missed;
              start = woke - i * interval;
            }
          }
          await send(steps[i % steps.length]);
          if (i === 0) start = now();
        }
      } finally {
        if (mine === run) active = false;
      }
    },
  };
}
