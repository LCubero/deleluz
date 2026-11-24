export const SEQUENCES_KEY = 'deleluz.webapp.sequences';
export const MAX_SEQUENCES = 12;
export const MAX_COLORS = 8;
const DEFAULT_COLORS = [[255, 0, 0], [0, 255, 0], [0, 0, 255]];
const inRange = (n, min, max) => Number.isInteger(n) && n >= min && n <= max;
const validRgb = rgb => Array.isArray(rgb) && rgb.length === 3 && [...rgb].every(n => inRange(n, 0, 255));
const validText = value => typeof value === 'string' && !!value.trim();
const valid = item => item && validText(item.id) && validText(item.name)
  && Array.isArray(item.colors) && inRange(item.colors.length, 1, MAX_COLORS) && [...item.colors].every(validRgb)
  && inRange(item.interval, 150, 2000) && inRange(item.bri, 1, 100);

export const speedPercent = interval => Math.round(Math.min(100, Math.max(0, (2000 - interval) * 100 / 1850)));
export const intervalFromSpeed = percent => Math.round(2000 - Math.min(100, Math.max(0, percent)) * 1850 / 100);

export function loadSequences(storage) {
  try {
    const items = JSON.parse(storage.getItem(SEQUENCES_KEY));
    if (!Array.isArray(items)) return [];
    const unique = new Map();
    for (const item of items) {
      if (!valid(item) || unique.has(item.id)) continue;
      const { id, name, colors, interval, bri } = item;
      unique.set(id, { id, name, colors, interval, bri });
      if (unique.size === MAX_SEQUENCES) break;
    }
    return [...unique.values()];
  } catch { return []; }
}

export function saveSequences(storage, items) {
  try {
    storage.setItem(SEQUENCES_KEY, JSON.stringify(items));
    return true;
  } catch { return false; }
}

export function createSequence(items, nameFor = n => `Secuencia ${n}`) {
  if (items.length >= MAX_SEQUENCES) return items;
  let n = 1;
  while (items.some(item => item.name === nameFor(n))) n++;
  let id = 1;
  while (items.some(item => item.id === String(id))) id++;
  return [...items, { id: String(id), name: nameFor(n), colors: DEFAULT_COLORS.map(rgb => [...rgb]), interval: 500, bri: 80 }];
}

export function updateSequence(items, id, changes) {
  return items.map(item => {
    if (item.id !== id) return item;
    const { name, colors, interval, bri } = { ...item, ...changes };
    const next = { id, name, colors, interval, bri };
    return valid(next) ? next : item;
  });
}

export const removeSequence = (items, id) => items.filter(item => item.id !== id);

export function setColor(item, index, rgb) {
  if (!inRange(index, 0, item.colors.length - 1) || !validRgb(rgb)) return item;
  return { ...item, colors: item.colors.map((color, i) => i === index ? [...rgb] : color) };
}

export function addColor(item) {
  if (item.colors.length >= MAX_COLORS) return item;
  return { ...item, colors: [...item.colors, [...item.colors.at(-1)]] };
}

export function removeColor(item, index) {
  if (item.colors.length === 1 || !inRange(index, 0, item.colors.length - 1)) return item;
  return { ...item, colors: item.colors.filter((_, i) => i !== index) };
}
