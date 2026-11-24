import { readStoredJson } from './state.js';

export const PALETTE_KEY = 'deleluz.webapp.palette';
export const PALETTE_LIMIT = 15;
const LEGACY_KEY = 'deleluz.webapp.customColors';
const names = new Map([
  ['#ffc880', 'warmWhite'], ['#ffffff', 'coolWhite'], ['#ff0000', 'red'],
  ['#ff6e00', 'orange'], ['#ffc800', 'yellow'], ['#00ff00', 'green'],
  ['#00ffff', 'cyan'], ['#0000ff', 'blue'], ['#ff0078', 'pink'],
]);
export const DEFAULT_PALETTE = Object.freeze([...names.keys()]);
const normalize = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;

export const colorName = value => names.get(normalize(value)) ?? 'solid';

export function addPaletteColor(colors, value) {
  const hex = normalize(value);
  if (!hex || colors.includes(hex) || colors.length >= PALETTE_LIMIT) return colors;
  return [...colors, hex];
}

export function replacePaletteColor(colors, index, value) {
  const hex = normalize(value);
  if (!hex || !Number.isInteger(index) || index < 0 || index >= colors.length || colors.includes(hex)) return colors;
  return colors.map((old, i) => (i === index ? hex : old));
}

// Remove one color; the palette may end up empty (the "+" still adds colors).
export function removePaletteColor(colors, index) {
  if (index < 0 || index >= colors.length) return colors;
  return colors.filter((_, i) => i !== index);
}

export function movePaletteColor(colors, from, to) {
  if (from === to || from < 0 || to < 0 || from >= colors.length || to >= colors.length) return colors;
  const next = colors.slice();
  next.splice(to, 0, next.splice(from, 1)[0]);
  return next;
}

export function loadPalette(storage) {
  // Only a missing key triggers migration, not malformed JSON or a denied read.
  let missing = false;
  const saved = readStoredJson({
    getItem(key) {
      const raw = storage.getItem(key);
      missing = raw == null;
      return raw;
    },
    invalid: () => storage.invalid?.(),
  }, PALETTE_KEY);
  if (missing) {
    const legacy = readStoredJson(storage, LEGACY_KEY);
    if (legacy === undefined) return [...DEFAULT_PALETTE];
    if (!Array.isArray(legacy) || legacy.some(value => !normalize(value))) {
      storage.invalid?.();
      return [...DEFAULT_PALETTE];
    }
    return legacy.reduce(addPaletteColor, [...DEFAULT_PALETTE]);
  }
  if (Array.isArray(saved) && saved.length > 0 && saved.length <= PALETTE_LIMIT) {
    const colors = saved.map(normalize);
    if (colors.every(Boolean) && new Set(colors).size === colors.length) return colors;
  }
  if (saved !== undefined) storage.invalid?.();
  return [...DEFAULT_PALETTE];
}
