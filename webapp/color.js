// Hue wheel helpers. The wheel is a CSS conic gradient starting at the top (red) and running clockwise.
export function hueToRgb(hue, saturation = 1) {
  const h = ((hue % 360) + 360) % 360 / 60;
  const x = 255 * (1 - Math.abs((h % 2) - 1));
  const table = [[255, x, 0], [x, 255, 0], [0, 255, x], [0, x, 255], [x, 0, 255], [255, 0, x]];
  return table[Math.floor(h) % 6].map(channel => Math.round(255 - (255 - channel) * saturation));
}

export function hueFromPoint(dx, dy) {
  const degrees = Math.atan2(dx, -dy) * 180 / Math.PI;
  return Math.round((degrees + 360) % 360);
}

export const WHITE_PRESETS = [
  ['whiteWarm', [255, 200, 128]], ['whiteNeutral', [255, 228, 196]], ['whiteCool', [255, 255, 255]],
];

export function discRgb(x, y) {
  return hueToRgb(Math.atan2(x, -y) * 180 / Math.PI, Math.min(1, Math.hypot(x, y)));
}

export function rgbDiscPoint([r, g, b]) {
  // This disc fixes value to 100%; project darker colors onto the same hue/saturation.
  const max = Math.max(r, g, b);
  const delta = max - Math.min(r, g, b);
  if (!delta) return [0, 0];
  const sector = max === r ? (g - b) / delta : max === g ? 2 + (b - r) / delta : 4 + (r - g) / delta;
  const angle = sector * Math.PI / 3;
  const radius = delta / max;
  return [radius * Math.sin(angle), -radius * Math.cos(angle)];
}

export const rgbCss = ([r, g, b]) => `rgb(${r} ${g} ${b})`;

export function rgbFromHex(value) {
  if (typeof value !== 'string' || !/^#[0-9a-f]{6}$/i.test(value)) return null;
  return [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
}
