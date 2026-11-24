const integer = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;
const isRgb = value => Array.isArray(value) && value.length === 3 && value.every(v => integer(v, 0, 255));

export function solidSelection(rgb) {
  const hex = `#${rgb.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
  return { scene: null, mode: null, label: ['colorHex', { hex }] };
}

export function readStoredJson(storage, key) {
  let raw;
  try { raw = storage.getItem(key); } catch { return undefined; }
  if (raw == null) return undefined;
  try { return JSON.parse(raw); }
  catch { storage.invalid?.(); return undefined; }
}

export function loadState(key, defaults, sequenceKeys, getStorage = () => localStorage, presetIds = []) {
  let storage;
  try { storage = getStorage(); } catch { return { ...defaults }; }
  const saved = readStoredJson(storage, key);
  if (saved === undefined) return { ...defaults };
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) {
    storage.invalid?.();
    return { ...defaults };
  }
  const accepted = {};
  if (typeof saved.on === 'boolean') accepted.on = saved.on;
  if (integer(saved.bri, 0, 100)) accepted.bri = saved.bri;
  if (integer(saved.speed, 0, 100)) accepted.speed = saved.speed;
  if (saved.fx === 'AUTO' || integer(saved.fx, 1, 210)) accepted.fx = saved.fx;
  if (isRgb(saved.rgb)) accepted.rgb = saved.rgb;
  const label = saved.label;
  if (typeof label === 'string' || (Array.isArray(label) && typeof label[0] === 'string' && label.length <= 2 &&
      (label.length === 1 || (label[1] && typeof label[1] === 'object' && !Array.isArray(label[1]) &&
        Object.values(label[1]).every(value => ['string', 'number'].includes(typeof value)))))) accepted.label = label;
  if (saved.scene === null || typeof saved.scene === 'string') accepted.scene = saved.scene;
  const mode = saved.mode;
  if (accepted.scene?.startsWith('sequence:')) {
    if (sequenceKeys.includes(accepted.scene) && Array.isArray(mode?.colors) && integer(mode.colors.length, 1, 8) &&
        mode.colors.every(isRgb) && integer(mode.interval, 150, 2000)) accepted.mode = { colors: mode.colors, interval: mode.interval };
    else {
      storage.invalid?.();
      Object.assign(accepted, solidSelection(accepted.rgb ?? defaults.rgb));
    }
  } else if (presetIds.includes(mode?.preset) && integer(mode.interval, 50, 2000)) accepted.mode = { preset: mode.preset, interval: mode.interval };
  else if (mode?.effect === 'AUTO' || integer(mode?.effect, 1, 210)) accepted.mode = { effect: mode.effect };
  else if (integer(mode?.voice, 1, 4)) accepted.mode = { voice: mode.voice };
  else if (mode === null) accepted.mode = null;
  if (Object.keys(saved).some(field => !Object.hasOwn(accepted, field))) storage.invalid?.();
  return { ...defaults, ...accepted };
}

export function persistState(key, snapshot, getStorage = () => localStorage) {
  try {
    getStorage().setItem(key, JSON.stringify(snapshot));
    return true;
  } catch {
    // Storage is optional; keep the in-memory state and let strip commands proceed.
    return false;
  }
}
