// Hue wheel helpers. The wheel is a CSS conic gradient starting at the top (red) and running clockwise.
export function hueToRgb(hue) {
  const h = ((hue % 360) + 360) % 360 / 60;
  const x = Math.round(255 * (1 - Math.abs((h % 2) - 1)));
  const table = [[255, x, 0], [x, 255, 0], [0, 255, x], [0, x, 255], [x, 0, 255], [255, 0, x]];
  return table[Math.floor(h) % 6];
}

export function hueFromPoint(dx, dy) {
  const degrees = Math.atan2(dx, -dy) * 180 / Math.PI;
  return Math.round((degrees + 360) % 360);
}

export const rgbCss = ([r, g, b]) => `rgb(${r} ${g} ${b})`;
