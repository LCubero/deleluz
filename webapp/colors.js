import { readStoredJson } from './state.js';

export const CUSTOM_COLORS_KEY = 'deleluz.webapp.customColors';
export const CUSTOM_LIMIT = 7;
const LIMIT = CUSTOM_LIMIT;
const normalize = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;

export function addCustomColor(colors, value) {
  const hex = normalize(value);
  if (!hex || colors.includes(hex) || colors.length >= LIMIT) return colors;
  return [...colors, hex];
}

// Replace one saved color in place (the slot the user tapped); duplicates are ignored.
export function replaceCustomColor(colors, index, value) {
  const hex = normalize(value);
  if (!hex || index < 0 || index >= colors.length || colors.includes(hex)) return colors;
  return colors.map((old, i) => (i === index ? hex : old));
}

export function loadCustomColors(storage) {
  const values = readStoredJson(storage, CUSTOM_COLORS_KEY);
  if (values === undefined) return [];
  if (!Array.isArray(values)) { storage.invalid?.(); return []; }
  const colors = [...new Set(values.map(normalize).filter(Boolean))].slice(0, LIMIT);
  if (colors.length !== values.length) storage.invalid?.();
  return colors;
}
