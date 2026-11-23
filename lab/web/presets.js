import { brightness, color, power } from './protocol.js';

export const SEND_INTERVAL = 150;
const red = [255, 0, 0], green = [0, 255, 0], blue = [0, 0, 255];
const black = [0, 0, 0], white = [255, 255, 255], warm = [255, 200, 128];

// Include each anchor once, with a smooth transition back to the first anchor.
function cycle(anchors, subdivisions) {
  return anchors.flatMap((from, index) => {
    const to = anchors[(index + 1) % anchors.length];
    return Array.from({ length: subdivisions }, (_, step) =>
      from.map((value, channel) => Math.round(value + (to[channel] - value) * step / subdivisions)));
  });
}

const definitions = [
  ['christmas-moving', 'Christmas moving', 200, cycle([red, green, warm], 8)],
  ['christmas-glow', 'Christmas glow', 300, cycle([[64, 0, 0], red, [64, 0, 0], [0, 64, 0], green, [0, 64, 0]], 6)],
  ['police', 'Police', 180, [red, black, red, blue, black, blue, black]],
  ['siren', 'Siren', 150, cycle([red, blue], 12)],
  ['rasta', 'Rasta', 650, [green, [255, 255, 0], red]],
  ['flashing', 'Flashing', 500, [white, black]],
];

export const PRESETS = definitions.map(([id, name, interval]) => ({ id, name, interval }));

export function presetFrames(id, interval) {
  const definition = definitions.find(([key]) => id === key);
  if (!definition) throw new RangeError('Unknown preset');
  if (!Number.isInteger(interval) || interval < SEND_INTERVAL || interval > 600000) {
    throw new RangeError(`Step interval must be ${SEND_INTERVAL}–600000 ms`);
  }
  return {
    setup: [power(true), brightness(50)],
    steps: definition[3].map(shade => ({ bytes: color(...shade), interval })),
  };
}
