import { MIN_INTERVAL } from './player.js';

const FADES = new Set(['christmas-moving', 'christmas-glow', 'siren', 'rasta']);

export function smoothSteps(preset, steps) {
  if (!FADES.has(preset)) return steps;
  return steps.flatMap(({ bytes, interval }, index) => {
    const count = Math.max(1, Math.floor(interval / MIN_INTERVAL)); // floor: each sub-step stays >= the floor
    const gap = Math.max(MIN_INTERVAL, Math.round(interval / count));
    const next = steps[(index + 1) % steps.length].bytes;
    return Array.from({ length: count }, (_, step) => {
      const frame = bytes.slice();
      for (let channel = 3; channel <= 5; channel++) {
        frame[channel] = Math.round(bytes[channel] + (next[channel] - bytes[channel]) * step / count);
      }
      return { bytes: frame, interval: gap };
    });
  });
}
