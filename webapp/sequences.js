import { readStoredJson } from './state.js';

export const SEQUENCES_KEY = 'deleluz.webapp.sequences';
export const MAX_SEQUENCES = 12;
export const MAX_COLORS = 8;
export const MAX_SEQUENCE_NAME = 24;
const DEFAULT_COLORS = [[0, 255, 0], [255, 200, 0], [255, 0, 0]];
const inRange = (n, min, max) => Number.isInteger(n) && n >= min && n <= max;
const validRgb = rgb => Array.isArray(rgb) && rgb.length === 3 && [...rgb].every(n => inRange(n, 0, 255));
const validText = value => typeof value === 'string' && !!value.trim();
const valid = item => item && validText(item.id) && validText(item.name)
  && Array.isArray(item.colors) && inRange(item.colors.length, 1, MAX_COLORS) && [...item.colors].every(validRgb)
  && inRange(item.interval, 150, 2000) && inRange(item.bri, 1, 100);

export const speedPercent = interval => Math.round(Math.min(100, Math.max(0, (2000 - interval) * 100 / 1850)));
export const intervalFromSpeed = percent => Math.round(2000 - Math.min(100, Math.max(0, percent)) * 1850 / 100);

export function loadSequences(storage) {
  const items = readStoredJson(storage, SEQUENCES_KEY);
  if (items === undefined) return [];
  if (!Array.isArray(items)) { storage.invalid?.(); return []; }
  const unique = new Map();
  for (const item of items) {
    if (!valid(item) || unique.has(item.id)) continue;
    const { id, name, colors, interval, bri } = item;
    unique.set(id, { id, name, colors, interval, bri });
    if (unique.size === MAX_SEQUENCES) break;
  }
  if (unique.size !== items.length) storage.invalid?.();
  return [...unique.values()];
}

export function saveSequences(storage, items) {
  try {
    storage.setItem(SEQUENCES_KEY, JSON.stringify(items));
    return true;
  } catch { return false; }
}

export function createSequence(items, nameFor = n => `Secuencia ${n}`) {
  if (items.length >= MAX_SEQUENCES) return items;
  let id = 1;
  while (items.some(item => item.id === String(id))) id++;
  for (let n = 1; n <= MAX_SEQUENCES; n++) {
    const name = nameFor(n);
    const error = sequenceNameError(items, null, name);
    if (error === 'sequenceNameDuplicate') continue;
    if (error) return items;
    return [...items, { id: String(id), name: name.trim(), colors: DEFAULT_COLORS.map(rgb => [...rgb]), interval: 500, bri: 80 }];
  }
  return items;
}

export function sequenceNameError(items, id, name) {
  if (!validText(name)) return 'sequenceNameEmpty';
  const trimmed = name.trim();
  if (trimmed.length > MAX_SEQUENCE_NAME) return 'sequenceNameTooLong';
  if (items.some(item => item.id !== id && item.name.trim().toLowerCase() === trimmed.toLowerCase())) {
    return 'sequenceNameDuplicate';
  }
  return null;
}

export function renameSequence(items, id, name) {
  if (!items.some(item => item.id === id) || sequenceNameError(items, id, name)) return items;
  return updateSequence(items, id, { name });
}

export function updateSequence(items, id, changes) {
  return items.map(item => {
    if (item.id !== id) return item;
    const { name, colors, interval, bri } = { ...item, ...changes };
    if (name !== item.name && sequenceNameError(items, id, name)) return item;
    const next = { id, name: name === item.name ? name : name.trim(), colors, interval, bri };
    return valid(next) ? next : item;
  });
}

export const removeSequence = (items, id) => items.filter(item => item.id !== id);

export function setColor(item, index, rgb) {
  if (!inRange(index, 0, item.colors.length - 1) || !validRgb(rgb)) return item;
  return { ...item, colors: item.colors.map((color, i) => i === index ? [...rgb] : color) };
}

export function moveColor(item, from, to) {
  const last = item.colors.length - 1;
  if (from === to || !inRange(from, 0, last) || !inRange(to, 0, last)) return item;
  const colors = [...item.colors];
  const [color] = colors.splice(from, 1);
  colors.splice(to, 0, color);
  return { ...item, colors };
}

export function addColor(item) {
  if (item.colors.length >= MAX_COLORS) return item;
  return { ...item, colors: [...item.colors, [...item.colors.at(-1)]] };
}

export function removeColor(item, index) {
  if (item.colors.length === 1 || !inRange(index, 0, item.colors.length - 1)) return item;
  return { ...item, colors: item.colors.filter((_, i) => i !== index) };
}
