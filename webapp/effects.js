// Built-in effect names, in controller ID order (1-210).
// Source: the vendor app's `dmx03_model` resource (LED LAMP 4.3.7), which shows these
// English names in every locale except Chinese. ID 255 is AUTO (auto cycle).
import { effect } from '../lab/web/protocol.js';
import { readStoredJson, persistState } from './state.js';

export const EFFECT_NAMES = Object.freeze([
  "Forward Dreaming",
  "Backward Dreaming",
  "Forward 7 Colors",
  "Backward 7 Colors",
  "Forward RD/GN/BU",
  "Backward RD/GN/BU",
  "Forward YE/CN/VT",
  "Backward YE/CN/VT",
  "Forward 6 Colors RD",
  "Backward 6 Colors RD",
  "Forward 6 Colors GN",
  "Backward 6 Colors GN",
  "Forward 6 Colors BU",
  "Backward 6 Colors BU",
  "Forward 6 Colors CN",
  "Backward 6 Colors CN",
  "Forward 6 Colors YE",
  "Backward 6 Colors YE",
  "Forward 6 Colors VT",
  "Backward 6 Colors VT",
  "Forward 6 Colors WH",
  "Backward 6 Colors WH",
  "Forward Trailing 7 Colors",
  "Backward Trailing 7 Colors",
  "Forward Trailing RD",
  "Backward Trailing RD",
  "Forward Trailing GN",
  "Backward Trailing GN",
  "Forward Trailing BU",
  "Backward Trailing BU",
  "Forward Trailing YE",
  "Backward Trailing YE",
  "Forward Trailing CN",
  "Backward Trailing CN",
  "Forward Trailing VT",
  "Backward Trailing VT",
  "Forward Trailing WH",
  "Backward Trailing WH",
  "Forward Streaming 7 Colors",
  "Backward Streaming 7 Colors",
  "Forward Streaming RD/GN/BU",
  "Backward Streaming RD/GN/BU",
  "Forward Streaming YE/CN/VT",
  "Backward Streaming YE/CN/VT",
  "Forward Streaming RD/GN",
  "Backward Streaming RD/GN",
  "Forward Streaming GN/BU",
  "Backward Streaming GN/BU",
  "Forward Streaming YE/BU",
  "Backward Streaming YE/BU",
  "Forward Streaming YE/CN",
  "Backward Streaming YE/CN",
  "Forward Streaming CN/VT",
  "Backward Streaming CN/VT",
  "Forward Streaming BK/WH",
  "Backward Streaming BK/WH",
  "Open Curtain 7 Colors",
  "Close Curtain 7 Colors",
  "Open Curtain RD/GN/BU",
  "Close Curtain RD/GN/BU",
  "Open Curtain YE/CN/VT",
  "Close Curtain YE/CN/VT",
  "Forward Follow Spot 7 Colors",
  "Backward Follow Spot 7 Colors",
  "Forward Follow Spot RD/GN/BU",
  "Backward Follow Spot RD/GN/BU",
  "Forward Follow Spot YE/CN/VT",
  "Backward Follow Spot YE/CN/VT",
  "Forward Flutter 7 Colors",
  "Backward Flutter 7 Colors",
  "Forward Flutter RD/GN/BU",
  "Backward Flutter RD/GN/BU",
  "Forward Flutter BU/YE/CN",
  "Backward Flutter BU/YE/CN",
  "Forward Flutter CN/VT/WH",
  "Backward Flutter CN/VT/WH",
  "Hop 7 Colors",
  "Hop RD/GN/BU",
  "Hop YE/CN/VT",
  "Strobe White",
  "Forward Horse Race 7 Colors",
  "Backward Horse Race 7 Colors",
  "Forward Horse Race RD/GN/BU",
  "Backward Horse Race RD/GN/BU",
  "Forward Horse Race YE/CN/VT",
  "Backward Horse Race YE/CN/VT",
  "Forward Horse Race YE",
  "Backward Horse Race YE",
  "Forward Horse Race CN",
  "Backward Horse Race CN",
  "Forward Horse Race VT",
  "Backward Horse Race VT",
  "Forward Horse Race WH",
  "Backward Horse Race WH",
  "Forward Run 7 Colors",
  "Backward Run 7 Colors",
  "Forward Run RD",
  "Backward Run RD",
  "Forward Run GN",
  "Backward Run GN",
  "Forward Run BU",
  "Backward Run BU",
  "Forward Run YE",
  "Backward Run YE",
  "Forward Run CN",
  "Backward Run CN",
  "Forward Run VT",
  "Backward Run VT",
  "Forward Run WH",
  "Backward Run WH",
  "Forward Run RD/GN",
  "Backward Run RD/GN",
  "Forward Run GN/BU",
  "Backward Run GN/BU",
  "Forward Run BU/YE",
  "Backward Run BU/YE",
  "Forward Run YE/CN",
  "Backward Run YE/CN",
  "Forward Run CN/VT",
  "Backward Run CN/VT",
  "Forward Run VT/WH",
  "Backward Run VT/WH",
  "Forward Flow 7 Colors",
  "Backward Flow 7 Colors",
  "Forward Flow RD/GN/RD",
  "Backward Flow RD/GN/RD",
  "Forward Flow BU/GN/BU",
  "Backward Flow BU/GN/BU",
  "Forward Flow YE/GN/YE",
  "Backward Flow YE/GN/YE",
  "Forward Flow YE/CN/YE",
  "Backward Flow YE/CN/YE",
  "Forward Flow VT/CN/VT",
  "Backward Flow VT/CN/VT",
  "Forward Flow WH/VT/WH",
  "Backward Flow WH/VT/WH",
  "Forward Run 7 Colors ON WH",
  "Backward Run 7 Colors ON WH",
  "Forward Run RD ON WH",
  "Backward Run RD ON WH",
  "Forward Run GN ON WH",
  "Backward Run GN ON WH",
  "Forward Run BU ON WH",
  "Backward Run BU ON WH",
  "Forward Run YE ON GN",
  "Backward Run YE ON GN",
  "Forward Run CN ON RD",
  "Backward Run CN ON RD",
  "Forward Run VT ON BU",
  "Backward Run VT ON BU",
  "Forward Run YE ON WH",
  "Backward Run YE ON WH",
  "Close Curtain 7 COLOR",
  "Open Curtain 7 COLOR",
  "Close Curtain RD",
  "Open Curtain RD",
  "Close Curtain GN",
  "Open Curtain GN",
  "Close Curtain BU",
  "Open Curtain BU",
  "Close Curtain YE",
  "Open Curtain YE",
  "Close Curtain CN",
  "Open Curtain CN",
  "Close Curtain VT",
  "Open Curtain VT",
  "Close Curtain WH",
  "Open Curtain WH",
  "Close Curtain 7 Colors ON YE",
  "Open Curtain 7 Colors ON YE",
  "Close Curtain RD/GN/BU ON CN",
  "Open Curtain RD/GN/BU ON CN",
  "Close Curtain YE/CN/VT ON VT",
  "Open Curtain YE/CN/VT ON VT",
  "Forward Flow RD/GN/BU/YE",
  "Backward Flow RD/GN/BU/YE",
  "Forward Flow GN/BU/YE/CN",
  "Backward Flow GN/BU/YE/CN",
  "Forward Flow BU/YE/CN/VT",
  "Backward Flow BU/YE/CN/VT",
  "Forward Flow YE/CN/VT/WH",
  "Backward Flow YE/CN/VT/WH",
  "Forward Swab 7 COLORS",
  "Backward Swab 7 COLORS",
  "Forward Swab RD/GN/BU",
  "Backward Swab RD/GN/BU",
  "Forward Swab YE/CN/VT",
  "Backward Swab YE/CN/VT",
  "Forward Swab RD",
  "Backward Swab RD",
  "Forward Swab GN",
  "Backward Swab GN",
  "Forward Swab BU",
  "Backward Swab BU",
  "Forward Swab YE",
  "Backward Swab YE",
  "Forward Swab CN",
  "Forward Swab CN",
  "Forward Swab VT",
  "Forward Swab VT",
  "Forward Swab WH",
  "Forward Swab WH",
  "Open Curtain Swab 7 COLORS",
  "Close Curtain Swab 7 COLORS",
  "Open Curtain Swab RD/GN/BU",
  "Close Curtain Swab RD/GN/BU",
  "Open Curtain Swab BU/YE",
  "Close Curtain Swab BU/YE",
  "Open Curtain Swab CN/VT",
  "Close Curtain Swab CN/VT",
]);

export function effectName(id) {
  return Number.isInteger(id) && id >= 1 && id <= EFFECT_NAMES.length ? EFFECT_NAMES[id - 1] : null;
}

export const EFFECT_FAVORITES_KEY = 'deleluz.webapp.effectFavorites';
export const AUTO_KEY = 'deleluz.webapp.auto';
export const AUTO_DURATIONS = Object.freeze([10, 30, 60, 300]);
const ids = EFFECT_NAMES.map((_, index) => index + 1);
const fold = text => text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
const names = EFFECT_NAMES.map(fold);
export const formatEffect = id => `${String(id).padStart(2, '0')} · ${effectName(id)}`;

export function effectGroups(query, favorites) {
  const term = fold(query.trim());
  const groups = [[], []];
  for (const id of ids) {
    if (names[id - 1].includes(term) || String(id).padStart(2, '0').includes(term)) groups[favorites.has(id) ? 0 : 1].push(id);
  }
  return groups;
}

export function autoFrames(favoritesOnly, favorites = new Set()) {
  return (favoritesOnly ? ids.filter(id => favorites.has(id)) : ids).map(id => effect(id));
}

export function loadEffectFavorites(storage) {
  const saved = readStoredJson(storage, EFFECT_FAVORITES_KEY);
  if (saved === undefined) return new Set();
  const valid = Array.isArray(saved) ? saved.filter(id => effectName(id) !== null) : [];
  if (!Array.isArray(saved) || valid.length !== saved.length) storage.invalid?.();
  return new Set(valid);
}

export function saveEffectFavorites(storage, favorites) {
  const sorted = [...favorites].sort((a, b) => a - b);
  return sorted.every(id => effectName(id) !== null) && persistState(EFFECT_FAVORITES_KEY, sorted, () => storage);
}

const validAuto = options => AUTO_DURATIONS.includes(options?.seconds) && typeof options?.favorites === 'boolean';
export function loadAutoOptions(storage) {
  const saved = readStoredJson(storage, AUTO_KEY);
  if (validAuto(saved)) return { seconds: saved.seconds, favorites: saved.favorites };
  if (saved !== undefined) storage.invalid?.();
  return { seconds: 30, favorites: false };
}

export function saveAutoOptions(storage, options) {
  return validAuto(options) && persistState(AUTO_KEY, { seconds: options.seconds, favorites: options.favorites }, () => storage);
}
