// Home quick scenes chosen by the user: colors, included page scenes or saved sequences, at most six.
// Stored in this browser only; storage failures fall back to the defaults or memory.
import { readStoredJson } from './state.js';

export const SHORTCUTS_KEY = 'deleluz.webapp.shortcuts';
export const MAX_SHORTCUTS = 6;
export const DEFAULT_SHORTCUTS = Object.freeze([
  { kind: 'color', name: 'warmWhite', rgb: [255, 200, 128] },
  { kind: 'color', name: 'coolWhite', rgb: [255, 255, 255] },
  { kind: 'color', name: 'blue', rgb: [0, 0, 255] },
  { kind: 'color', name: 'green', rgb: [0, 255, 0] },
  { kind: 'color', name: 'yellow', rgb: [255, 200, 0] },
  { kind: 'color', name: 'red', rgb: [255, 0, 0] },
]);

const isByte = value => Number.isInteger(value) && value >= 0 && value <= 255;

function valid(item, presetIds, sequenceIds) {
  if (item?.kind === 'color') return Array.isArray(item.rgb) && item.rgb.length === 3 && item.rgb.every(isByte)
    && (item.name === undefined || typeof item.name === 'string');
  if (item?.kind === 'sequence') return typeof item.id === 'string' && sequenceIds.includes(item.id);
  return item?.kind === 'scene' && presetIds.includes(item.preset);
}

const copy = item => item.kind === 'color'
  ? { kind: 'color', ...(item.name ? { name: item.name } : {}), rgb: [...item.rgb] }
  : item.kind === 'sequence' ? { kind: 'sequence', id: item.id } : { kind: 'scene', preset: item.preset };

const defaults = () => DEFAULT_SHORTCUTS.map(copy);

export const filterShortcuts = (list, presetIds, sequenceIds) =>
  list.filter(item => valid(item, presetIds, sequenceIds)).slice(0, MAX_SHORTCUTS);

export function loadShortcuts(storage, presetIds, sequenceIds = []) {
  const list = readStoredJson(storage, SHORTCUTS_KEY);
  if (list === undefined) return defaults();
  if (!Array.isArray(list)) { storage.invalid?.(); return defaults(); }
  const filtered = filterShortcuts(list, presetIds, sequenceIds);
  if (filtered.length !== list.length) storage.invalid?.();
  return filtered.map(copy);
}

export function saveShortcuts(storage, list) {
  try {
    storage.setItem(SHORTCUTS_KEY, JSON.stringify(list));
    return true;
  } catch {
    return false;
  }
}

export const addShortcut = (list, item) => (list.length >= MAX_SHORTCUTS ? list.slice() : [...list, item]);
export const replaceShortcut = (list, index, item) => list.map((old, i) => (i === index ? item : old));
export const removeShortcut = (list, index) => list.filter((_, i) => i !== index);

export function moveShortcut(list, from, to) {
  const next = list.slice();
  if (from < 0 || from >= list.length || to < 0 || to >= list.length) return next;
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
}

// 1-3 cells in one row, 4 as a 2x2 block, 5-6 in rows of three.
export const gridColumns = cells => (cells <= 3 ? Math.max(cells, 1) : cells === 4 ? 2 : 3);
