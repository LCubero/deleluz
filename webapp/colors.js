import { readStoredJson } from './state.js';

export const CUSTOM_COLORS_KEY = 'deleluz.webapp.customColors';
const LIMIT = 4;
const normalize = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;

export function addCustomColor(colors, value) {
  const hex = normalize(value);
  if (!hex || colors.includes(hex)) return colors;
  return [...colors.slice(0, LIMIT - 1), hex];
}

export function loadCustomColors(storage) {
  const values = readStoredJson(storage, CUSTOM_COLORS_KEY);
  if (values === undefined) return [];
  if (!Array.isArray(values)) { storage.invalid?.(); return []; }
  const colors = [...new Set(values.map(normalize).filter(Boolean))].slice(0, LIMIT);
  if (colors.length !== values.length) storage.invalid?.();
  return colors;
}
