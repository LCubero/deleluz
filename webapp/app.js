import { power, color, brightness, effect, speed, voiceMode, micSensitivity, CHIP_ORDERS, chipConfig } from '../lab/web/protocol.js';
import { stripPixels, validPixels } from './strip-settings.js';
import { effectName, formatEffect, effectGroups, autoFrames, AUTO_DURATIONS,
  loadEffectFavorites, saveEffectFavorites, loadAutoOptions, saveAutoOptions } from './effects.js';
import { PRESETS, presetFrames } from '../lab/web/presets.js';
import { createSender } from './sender.js';
import { runStartup } from './startup.js';
import { createPlayer } from './player.js';
import { smoothSteps } from './smooth.js';
import { loadState, persistState, solidSelection } from './state.js';
import { MAX_SHORTCUTS, loadShortcuts, saveShortcuts, addShortcut, replaceShortcut,
  removeShortcut, moveShortcut, gridColumns, filterShortcuts } from './shortcuts.js';
import { MAX_SEQUENCES, MAX_COLORS, MAX_SEQUENCE_NAME, loadSequences, saveSequences, createSequence, updateSequence,
  renameSequence, sequenceNameError,
  removeSequence, setColor as setFrameColor, addColor, removeColor, moveColor, speedPercent, intervalFromSpeed } from './sequences.js';
import { formatRemaining, fadeBrightness, parseTimerDuration } from './timer.js';
import { createLink } from './ble.js';
import { hueToRgb, hueFromPoint, discRgb, rgbDiscPoint, WHITE_PRESETS, rgbCss, rgbFromHex } from './color.js';
import { DEFAULT_PALETTE, PALETTE_KEY, PALETTE_LIMIT, loadPalette, addPaletteColor, replacePaletteColor, removePaletteColor, movePaletteColor, colorName } from './colors.js';

import { LANGUAGE_KEY, loadLanguage, translate } from './i18n.js';

let storageReadFailed = false;
let storageInvalid = false;
const localStore = {
  getItem(key) {
    try { return localStorage.getItem(key); }
    catch (error) { storageReadFailed = true; throw error; }
  },
  setItem: (key, value) => localStorage.setItem(key, value),
  invalid: () => { storageInvalid = true; },
};
let language = loadLanguage(localStore);
const t = (key, vars) => translate(language, key, vars);

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const bind = name => $$(`[data-bind="${name}"]`);
const text = (name, value) => bind(name).forEach(el => { el.textContent = value; });

// ---- state (what the page last sent; the controller cannot report its real state) ----
const STORE = 'deleluz.webapp.state';
const WARM = [255, 200, 128];
const presetIds = PRESETS.map(p => p.id);
let sequences = loadSequences(localStore);
const sequenceKey = id => `sequence:${id}`;
const state = loadState(STORE, { on: false, bri: 80, rgb: WARM, label: ['warmWhite'], scene: 'warm', fx: 1, speed: 50, micSens: 50, lastSentAt: null },
  sequences.map(item => sequenceKey(item.id)), () => localStore, presetIds);
let lastPlayedRgb;
const persist = () => {
  const { on, bri, rgb, label, scene, mode, fx, speed: sp, micSens } = state;
  if (!persistState(STORE, { on, bri, rgb, label, scene, mode, fx, speed: sp, micSens })) toast('storageFailed', true);
};

// ---- link, sender, player ----
const simulate = new URLSearchParams(location.search).has('sim');
const link = createLink({ simulate, onChange: renderLink });
// Lab runs 2-4 (docs/CAPABILITIES.md, Send rate): the strip follows every change down to ~35 ms;
// 50 ms keeps a margin. Page-mode steps keep their own interval (player MIN_INTERVAL).
const SEND_GAP_MS = 50;
const sender = createSender({ write: bytes => link.write(bytes), interval: SEND_GAP_MS });
const player = createPlayer({ send: async bytes => {
  if (document.hidden) return;
  const run = playback;
  if (await send(bytes, 'color') === 'sent' && run === playback) {
    lastPlayedRgb = Array.from(bytes.subarray(3, 6));
    if (activeSequence && activeSequence !== draftPlayback) {
      state.rgb = lastPlayedRgb;
      renderStrip();
    }
  }
} });
let playback = 0;
let activeSequence = null;
const draftPlayback = Symbol('draft playback');
function stopPlayback() {
  playback++;
  player.stop();
  sender.cancel();
  activeSequence = null;
  clearAppAuto();
  renderSequencePlayback();
}

async function startMode(mode, { sequence = state.scene, bri = state.bri } = {}) {
  stopPlayback();
  lastPlayedRgb = null;
  const run = playback;
  if (mode.colors) {
    activeSequence = sequence;
    renderSequencePlayback();
  }
  try {
    const ready = await runStartup(send, [
      { bytes: power(true), key: 'power' },
      { bytes: brightness(targetBrightness(bri)), key: 'brightness' },
    ], () => run === playback);
    if (!ready) return;
    if (mode.preset) {
      const { steps } = presetFrames(mode.preset, mode.interval);
      const frames = smoothSteps(mode.preset, steps);
      await player.play(frames.map(frame => frame.bytes), frames[0].interval);
    } else if (mode.colors) await player.play(mode.colors.map(c => color(...c)), mode.interval);
    else if (mode.rgb) await send(color(...mode.rgb), 'color');
    else if (mode.voice) {
      await send(voiceMode(mode.voice), 'effect');
      await send(micSensitivity(state.micSens), 'micSens');
    }
    else await send(effect(mode.effect), 'effect');
  } catch (error) {
    if (run === playback && !(error instanceof SendFailure)) toast('sceneFailed', true);
  } finally {
    if (run === playback && mode.colors) {
      activeSequence = null;
      renderSequencePlayback();
    }
  }
}

let toastKey;
function toast(key, error = false) {
  const el = bind('toast')[0];
  if (dialog.open && el.parentElement !== dialog) dialog.append(el);
  if (toastKey === key) return;
  toastKey = key;
  el.textContent = t(key);
  el.classList.toggle('error', error);
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { toastKey = null; el.textContent = ''; }, error ? 6000 : 2500);
}

// User actions that change the strip do nothing until a strip is connected (or simulated),
// so the page never shows On / a color that was not sent.
function needsLink() {
  if (link.ready) return false;
  toast(link.state.status === 'lost' ? 'reconnectFirst' : 'connectFirst', true);
  return true;
}

class SendFailure extends Error {}

async function send(bytes, key) {
  if (!link.ready) {
    needsLink();
    throw new SendFailure();
  }
  try {
    const result = await sender.send(bytes, key);
    if (result === 'sent') { state.lastSentAt = Date.now(); renderLastSent(); }
    return result;
  } catch {
    if (link.state.status !== 'lost') toast('commandFailed', true);
    throw new SendFailure();
  }
}
const fire = (bytes, key) => send(bytes, key).catch(() => {});

// ---- quick scenes (Home) ----
const effectLabel = id => id === 'AUTO' ? ['autoCycle'] : ['effectNumber', { id }];
const effectTitle = id => id === 'AUTO' ? t('autoCycle') : t('effectNamed', { id, name: effectName(id) });
// Preset preview colors, unchanged from the previous quick scenes and scene list.
const PRESET_SW = {
  'christmas-moving': 'linear-gradient(90deg,#ef4444,#22c55e,#fff7e6)',
  police: 'linear-gradient(90deg,#ef4444,#3b82f6)',
  rasta: 'linear-gradient(90deg,#22c55e,#facc15,#ef4444)',
  flashing: '#fff',
};
const presetSwatch = id => PRESET_SW[id] ?? 'linear-gradient(90deg,#ef4444,#4f46e5)';

function setColor(rgb, label, scene = null) {
  if (needsLink()) return;
  stopPlayback();
  const wasOn = state.on;
  Object.assign(state, { rgb, label, scene, mode: null, on: true });
  persist();
  render();
  if (!wasOn) {
    fire(power(true), 'power');
    fire(brightness(targetBrightness()), 'brightness');
  }
  fire(color(...rgb), 'color');
}

function playPreset(id, interval = PRESETS.find(p => p.id === id).interval, label = [id], scene = id) {
  if (needsLink()) return;
  const mode = { preset: id, interval };
  Object.assign(state, { label, scene, mode, on: true });
  persist();
  render();
  return startMode(mode);
}

// ---- quick scenes (user shortcuts) ----
let shortcuts = loadShortcuts(localStore, presetIds, sequences.map(item => item.id));
const hex = rgb => `#${rgb.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
function shortcutName(item) {
  if (item.kind === 'sequence') return sequences.find(scene => scene.id === item.id).name;
  if (item.kind === 'scene') return t(item.preset);
  return t(item.name ?? colorName(hex(item.rgb)));
}
const shortcutId = item => item.kind === 'sequence' ? sequenceKey(item.id) :
  item.kind === 'scene' ? item.preset : `color:${item.rgb.join(',')}`;

function storeShortcuts(next) {
  shortcuts = next;
  if (!saveShortcuts(localStore, shortcuts)) toast('storageFailed', true);
  renderQuick();
  render();
}

function applyShortcut(item) {
  if (item.kind === 'sequence') {
    const scene = sequences.find(scene => scene.id === item.id);
    if (scene) playSequence(scene);
  } else if (item.kind === 'scene') playPreset(item.preset);
  else setColor(item.rgb, [item.name ?? colorName(hex(item.rgb))], shortcutId(item));
}

const HOLD_MS = 450;
const SLOP = 8;
// A tap activates; a hold can open options, lift an item for reordering, or both.
function attachPress(button, { tap, hold, drop, trash, onLift, onEnd }) {
  let timer;
  let start = null;
  let lifted = false;
  let moved = false;
  let suppress = false;
  const reset = () => {
    clearTimeout(timer);
    if (lifted) onEnd?.();
    button.classList.remove('lifted');
    button.style.translate = '';
    button.style.pointerEvents = '';
    start = null;
    lifted = false;
  };
  button.addEventListener('pointerdown', event => {
    if (event.button !== 0 || !event.isPrimary) return;
    suppress = false;
    start = { x: event.clientX, y: event.clientY, id: event.pointerId };
    moved = false;
    timer = setTimeout(() => {
      lifted = true;
      button.classList.add('lifted');
      onLift?.();
      try { button.setPointerCapture(start.id); } catch { /* the pointer may already be gone */ }
      navigator.vibrate?.(15);
    }, HOLD_MS);
  });
  button.addEventListener('pointermove', event => {
    if (!start || event.pointerId !== start.id) return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    if (!lifted) {
      if (Math.hypot(dx, dy) > SLOP) { suppress = true; reset(); }
      return;
    }
    if (Math.hypot(dx, dy) > SLOP) moved = true;
    if (moved && drop) {
      button.style.pointerEvents = 'none';
      button.style.translate = `${dx}px ${dy}px`;
    }
  });
  button.addEventListener('touchmove', event => { if (lifted) event.preventDefault(); }, { passive: false });
  button.addEventListener('pointerup', event => {
    if (!start || event.pointerId !== start.id) return;
    if (!lifted) { reset(); return; }
    suppress = true;
    const wasMoved = moved;
    const under = wasMoved && drop ? document.elementFromPoint(event.clientX, event.clientY) : null;
    const target = under?.closest('[data-index]');
    const bin = trash && under?.closest('[data-trash]');
    reset();
    if (wasMoved) {
      if (bin && bin.parentElement === button.parentElement) trash();
      else if (target && target.parentElement === button.parentElement) drop(Number(target.dataset.index));
    } else hold?.();
  });
  const cancel = event => { if (event.pointerId === start?.id) reset(); };
  button.addEventListener('pointercancel', cancel);
  button.addEventListener('lostpointercapture', cancel);
  button.addEventListener('pointerleave', () => { if (!lifted) reset(); });
  button.addEventListener('click', event => {
    if (suppress && event.detail > 0) { suppress = false; event.preventDefault(); return; }
    tap();
  });
  button.addEventListener('contextmenu', event => {
    event.preventDefault();
    if (start || lifted) return; // a touch long-press is handled by the hold timer
    hold?.();
  });
}

function shortcutTile(item) {
  const button = document.createElement('button');
  button.className = 'tile';
  const sw = document.createElement('span');
  sw.className = 'sw';
  if (item.kind === 'sequence') {
    const { colors } = sequences.find(scene => scene.id === item.id);
    sw.style.background = colors.length === 1 ? rgbCss(colors[0]) : `linear-gradient(90deg,${colors.map((rgb, i) =>
      `${rgbCss(rgb)} ${100 * i / colors.length}% ${100 * (i + 1) / colors.length}%`).join(',')})`;
  } else sw.style.background = item.kind === 'scene' ? presetSwatch(item.preset) : rgbCss(item.rgb);
  const name = document.createElement('span');
  name.className = 'tile-name';
  name.textContent = shortcutName(item);
  button.append(sw, name);
  return button;
}

function renderQuick() {
  const grid = bind('quick')[0];
  const validShortcuts = filterShortcuts(shortcuts, presetIds, sequences.map(item => item.id));
  if (validShortcuts.length !== shortcuts.length) {
    shortcuts = validShortcuts;
    if (!saveShortcuts(localStore, shortcuts)) toast('storageFailed', true);
  }
  const tiles = shortcuts.map((item, index) => {
    const button = shortcutTile(item);
    button.dataset.index = String(index);
    button.dataset.scene = shortcutId(item);
    attachPress(button, {
      tap: () => applyShortcut(item),
      hold: () => openShortcutMenu(index, button),
      drop: to => { if (to !== index) storeShortcuts(moveShortcut(shortcuts, index, to)); },
    });
    return button;
  });
  if (shortcuts.length < MAX_SHORTCUTS) {
    const add = document.createElement('button');
    add.className = 'tile add-tile';
    add.setAttribute('aria-label', t('addShortcut'));
    add.textContent = '+';
    add.addEventListener('click', () => openShortcutChooser(null, add));
    tiles.push(add);
  }
  grid.style.setProperty('--cols', String(gridColumns(tiles.length)));
  grid.replaceChildren(...tiles);
}

let shortcutIndex = null;
function openShortcutMenu(index, trigger) {
  shortcutIndex = index;
  $('[data-action="shortcut-left"]').disabled = index === 0;
  $('[data-action="shortcut-right"]').disabled = index === shortcuts.length - 1;
  openSheet('shortcut', shortcutName(shortcuts[index]), trigger);
}

function choice(item) {
  const button = shortcutTile(item);
  button.addEventListener('click', () => chooseShortcut(item));
  return button;
}

// Quick scenes offer only the named default colors (plus "Otro color" with the wheel),
// not the colors saved in the palette.
const NAMED_SHORTCUT_COLORS = [
  { kind: 'color', name: 'warmWhite', rgb: [255, 200, 128] },
  { kind: 'color', name: 'coolWhite', rgb: [255, 255, 255] },
  { kind: 'color', name: 'night', rgb: [255, 48, 0] },
];
function renderShortcutColors() {
  bind('shortcut-colors')[0].replaceChildren(...NAMED_SHORTCUT_COLORS.map(choice));
  shortcutPalette.render();
}

function openShortcutChooser(index, trigger) {
  shortcutIndex = index;
  renderShortcutColors();
  bind('shortcut-scenes')[0].replaceChildren(...PRESETS.map(({ id }) => choice({ kind: 'scene', preset: id })));
  const savedChoices = bind('shortcut-sequences')[0];
  savedChoices.replaceChildren(...sequences.map(({ id }) => choice({ kind: 'sequence', id })));
  savedChoices.hidden = bind('shortcut-divider')[0].hidden = sequences.length === 0;
  bind('shortcut-scene-section')[0].open = false;
  bind('shortcut-color-section')[0].open = false;
  openSheet('shortcut-pick', t(index === null ? 'addShortcut' : 'changeShortcut'), trigger);
}

function chooseShortcut(item) {
  storeShortcuts(shortcutIndex === null ? addShortcut(shortcuts, item) : replaceShortcut(shortcuts, shortcutIndex, item));
  closeSheet();
}

// ---- collapsible quick scenes (open/closed remembered in this browser) ----
const QUICK_OPEN_KEY = 'deleluz.webapp.quickOpen';
const quickToggle = $('[data-action="toggle-quick"]');
function setQuickOpen(open, save = true) {
  quickToggle.setAttribute('aria-expanded', String(open));
  bind('quick')[0].hidden = !open;
  bind('home-speed')[0].hidden = open;
  if (!save) return;
  try { localStorage.setItem(QUICK_OPEN_KEY, open ? '1' : '0'); } catch { toast('storageFailed', true); }
}
quickToggle.addEventListener('click', () => setQuickOpen(quickToggle.getAttribute('aria-expanded') !== 'true'));
setQuickOpen((() => {
  try {
    const value = localStore.getItem(QUICK_OPEN_KEY);
    if (value !== null && value !== '0' && value !== '1') localStore.invalid();
    return value === '1';
  } catch { return false; }
})(), false);

// ---- power and brightness ----
$('[data-action="power"]').addEventListener('click', () => {
  if (needsLink()) return;
  state.on = !state.on;
  if (!state.on) stopPlayback();
  persist();
  render();
  if (state.on) startMode(currentMode());
  else fire(power(false), 'power');
});
bind('bri').forEach(input => input.addEventListener('input', () => {
  state.bri = Number(input.value);
  persist();
  renderBrightness();
  fire(brightness(targetBrightness()), 'brightness');
}));

// ---- color wheel and swatches ----
let colorPalette;
function renderSwatches() {
  colorPalette ??= createPalette({
    place: 'color',
    container: bind('swatches')[0],
    mark: rgb => ({ rgb: rgb.join(',') }),
    current: () => state.rgb,
    apply: (rgb, label) => chooseColor(rgb, label),
  });
  colorPalette.render();
}

function currentLabel() {
  if (state.mode?.colors && typeof state.label === 'string') return state.label;
  if (state.scene?.startsWith('mine:')) return state.scene.slice(5);
  if (Array.isArray(state.label)) return t(...state.label);
  // Older versions persisted English labels instead of translation keys.
  if (state.mode?.preset) return t(state.mode.preset);
  if (state.mode?.effect) return t(...effectLabel(state.mode.effect));
  const degrees = /^Hue (\d+)°$/.exec(state.label)?.[1];
  if (degrees !== undefined) return t('hueValue', { degrees });
  const key = ['warmWhite', 'movie', ...SWATCHES.map(([name]) => name)]
    .find(name => translate('en', name) === state.label);
  return t(key ?? 'solid');
}

function createHueWheel(wheel, onPick) {
  const handle = wheel.querySelector('.handle');
  let hue = 0;
  const pick = degrees => {
    const next = (degrees + 360) % 360;
    onPick(hueToRgb(next), next);
  };
  function point(event) {
    const r = wheel.getBoundingClientRect();
    pick(hueFromPoint(event.clientX - r.left - r.width / 2, event.clientY - r.top - r.height / 2));
  }
  wheel.addEventListener('pointerdown', event => { wheel.setPointerCapture(event.pointerId); point(event); });
  wheel.addEventListener('pointermove', event => { if (wheel.hasPointerCapture(event.pointerId)) point(event); });
  wheel.addEventListener('keydown', event => {
    const step = { ArrowRight: 5, ArrowUp: 5, ArrowLeft: -5, ArrowDown: -5 }[event.key];
    if (step) { event.preventDefault(); pick(hue + step); }
  });
  return rgb => {
    const [r, g, b] = rgb;
    const max = Math.max(...rgb);
    const delta = max - Math.min(...rgb);
    const sector = !delta ? 0 : max === r ? (g - b) / delta : max === g ? 2 + (b - r) / delta : 4 + (r - g) / delta;
    hue = (Math.round(sector * 60) + 360) % 360;
    const angle = hue * Math.PI / 180;
    wheel.style.setProperty('--c', rgbCss(rgb));
    handle.style.left = `${50 + 38 * Math.sin(angle)}%`;
    handle.style.top = `${50 - 38 * Math.cos(angle)}%`;
    wheel.setAttribute('aria-valuenow', String(hue));
  };
}
// Without a strip, the wheel and circles still choose a color so favorites can be added or changed;
// nothing is sent until a strip is connected.
function chooseColor(rgb, label) {
  if (link.ready) { setColor(rgb, label); return; }
  Object.assign(state, { rgb, label });
  persist();
  render();
}
const disc = bind('disc')[0];
const discHandle = disc.querySelector('.handle');
let discHue = 0;
let discSaturation = 0;
const pickDisc = rgb => chooseColor(rgb, solidSelection(rgb).label);
function discPoint(event) {
  const r = disc.getBoundingClientRect();
  return [(event.clientX - r.left) * 2 / r.width - 1, (event.clientY - r.top) * 2 / r.height - 1];
}
disc.addEventListener('pointerdown', event => {
  if (event.button !== 0 || !event.isPrimary) return;
  const point = discPoint(event);
  if (Math.hypot(...point) > 1) return;
  disc.setPointerCapture(event.pointerId);
  pickDisc(discRgb(...point));
});
disc.addEventListener('pointermove', event => {
  if (disc.hasPointerCapture(event.pointerId)) pickDisc(discRgb(...discPoint(event)));
});
disc.addEventListener('keydown', event => {
  if (event.key === 'ArrowLeft') discHue = (discHue + 355) % 360;
  else if (event.key === 'ArrowRight') discHue = (discHue + 5) % 360;
  else if (event.key === 'ArrowUp') discSaturation = Math.min(1, discSaturation + 0.05);
  else if (event.key === 'ArrowDown') discSaturation = Math.max(0, discSaturation - 0.05);
  else if (event.key === 'Home') discSaturation = 0;
  else if (event.key === 'End') discSaturation = 1;
  else return;
  event.preventDefault();
  pickDisc(hueToRgb(discHue, discSaturation));
});
const whites = WHITE_PRESETS.map(([key, rgb]) => {
  const button = document.createElement('button');
  button.className = 'btn ghost white-preset';
  button.style.setProperty('--sw', rgbCss(rgb));
  const label = document.createElement('span');
  label.dataset.i18n = key;
  button.append(label);
  button.addEventListener('click', () => chooseColor([...rgb], [key]));
  bind('whites')[0].append(button);
  return [button, rgb];
});
function renderColorDisc(rgb) {
  const [x, y] = rgbDiscPoint(rgb);
  discSaturation = Math.hypot(x, y);
  if (discSaturation) discHue = hueFromPoint(x, y) % 360;
  disc.style.setProperty('--c', rgbCss(rgb));
  discHandle.style.left = `${50 + x * 50}%`;
  discHandle.style.top = `${50 + y * 50}%`;
  disc.setAttribute('aria-valuenow', String(discHue));
  disc.setAttribute('aria-valuetext', t('discValue', { degrees: discHue, saturation: Math.round(discSaturation * 100), hex: hex(rgb) }));
  for (const [button, white] of whites) button.setAttribute('aria-pressed', String(rgb.join() === white.join()));
}

// ---- built-in effects ----
$$('[data-mode]').forEach(button => button.addEventListener('click', () => {
  $$('[data-mode]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  $$('[data-panel]').forEach(p => { p.hidden = p.dataset.panel !== button.dataset.mode; });
  bind('effect-speed')[0].hidden = button.dataset.mode !== 'effects';
}));
function selectEffect(id) {
  if (id !== 'AUTO') state.fx = id;
  const mode = { effect: id };
  Object.assign(state, { label: effectLabel(id), scene: `effect:${id}`, mode, on: true });
  return mode;
}
function playEffect(id) {
  if (needsLink()) return;
  const mode = selectEffect(id);
  persist();
  render();
  startMode(mode);
}
const fxAuto = $('[data-action="fx-auto"]');
fxAuto.addEventListener('click', () => playEffect('AUTO'));
const effectFavorites = loadEffectFavorites(localStore);
const fxSearch = $('#fx-search');
const fxResults = bind('effect-results')[0];
const effectRows = new Map();
let selectedEffect;

function renderEffectCatalog() {
  const [favorites, others] = effectGroups(fxSearch.value, effectFavorites);
  effectRows.clear();
  selectedEffect = undefined;
  const groups = [[favorites, 'favorites'], [others, 'effectCatalogAll']].filter(([ids]) => ids.length);
  bind('effect-empty')[0].hidden = groups.length > 0;
  fxResults.hidden = !groups.length;
  fxResults.replaceChildren(...groups.flatMap(([ids, label]) => {
    const heading = document.createElement('h3');
    heading.textContent = t(label);
    const list = document.createElement('ul');
    for (const id of ids) {
      const row = document.createElement('li');
      const play = document.createElement('button');
      play.textContent = formatEffect(id);
      play.setAttribute('aria-pressed', 'false');
      play.addEventListener('click', () => playEffect(id));
      effectRows.set(id, play);
      const star = document.createElement('button');
      star.className = 'effect-star';
      star.dataset.effectStar = id;
      star.textContent = effectFavorites.has(id) ? '★' : '☆';
      star.setAttribute('aria-label', t('effectFavorite', { effect: formatEffect(id) }));
      star.setAttribute('aria-pressed', String(effectFavorites.has(id)));
      star.addEventListener('click', () => toggleEffectFavorite(id));
      row.append(play, star);
      list.append(row);
    }
    return [heading, list];
  }));
  renderEffect();
}
function toggleEffectFavorite(id) {
  if (!effectFavorites.delete(id)) effectFavorites.add(id);
  if (!saveEffectFavorites(localStore, effectFavorites)) toast('storageFailed', true);
  if (autoRunning && autoOptions.favorites && !effectFavorites.size) stopPlayback();
  renderEffectCatalog();
  const replacement = fxResults.querySelector(`[data-effect-star="${id}"]`);
  replacement?.focus({ preventScroll: true });
  const listRect = fxResults.getBoundingClientRect();
  const starRect = replacement?.getBoundingClientRect();
  if (starRect && starRect.top < listRect.top) fxResults.scrollTop -= listRect.top - starRect.top;
  if (starRect && starRect.bottom > listRect.bottom) fxResults.scrollTop += starRect.bottom - listRect.bottom;
}
fxSearch.addEventListener('input', () => {
  renderEffectCatalog();
  fxResults.scrollTop = 0;
});
function renderEffect() {
  const current = state.on && !autoRunning ? state.mode?.effect : undefined;
  fxAuto.setAttribute('aria-pressed', String(current === 'AUTO'));
  bind('strip-cycle-current')[0].hidden = current !== 'AUTO';
  if (current !== selectedEffect) {
    effectRows.get(selectedEffect)?.setAttribute('aria-pressed', 'false');
    effectRows.get(current)?.setAttribute('aria-pressed', 'true');
    selectedEffect = current;
  }
  renderAppAuto();
}

let autoOptions = loadAutoOptions(localStore);
let autoRunning = false;
let autoCurrent;
let autoStartedAt;
let autoProgressTimer;
const autoButton = $('[data-action="app-auto"]');
const autoDuration = $('#auto-duration');
const autoList = $('#auto-list');
const autoProgress = bind('auto-progress')[0];
const canRunAuto = () => !document.hidden && link.ready;
function updateAutoProgress() {
  autoProgress.value = Math.min(1, (performance.now() - autoStartedAt) / (autoOptions.seconds * 1000));
}
function renderAppAuto() {
  autoDuration.value = String(autoOptions.seconds);
  autoDuration.disabled = autoList.disabled = autoRunning;
  autoList.value = autoOptions.favorites ? 'favorites' : 'all';
  autoList.options[1].disabled = !effectFavorites.size;
  bind('auto-favorites-hint')[0].hidden = effectFavorites.size > 0;
  autoButton.disabled = !autoRunning && (!canRunAuto() || (autoOptions.favorites && !effectFavorites.size));
  const action = autoRunning ? 'appAutoStop' : 'appAutoStart';
  autoButton.dataset.i18n = action;
  autoButton.textContent = t(action);
  const label = autoCurrent ? t('appAutoCurrent', { effect: formatEffect(autoCurrent) }) : '';
  const current = bind('auto-current')[0];
  if (current.textContent !== label) current.textContent = label;
  autoProgress.hidden = !autoCurrent;
}
function clearAppAuto() {
  if (!autoRunning) return;
  autoRunning = false;
  autoCurrent = undefined;
  clearInterval(autoProgressTimer);
  autoProgressTimer = undefined;
  renderEffect();
}
function changeAutoOptions() {
  if (autoRunning) return;
  autoOptions = { seconds: Number(autoDuration.value), favorites: autoList.value === 'favorites' };
  if (!saveAutoOptions(localStore, autoOptions)) toast('storageFailed', true);
  renderAppAuto();
}
autoDuration.addEventListener('change', changeAutoOptions);
autoList.addEventListener('change', changeAutoOptions);
autoButton.addEventListener('click', async () => {
  if (autoRunning) { stopPlayback(); return; }
  const frames = autoFrames(autoOptions.favorites, effectFavorites);
  if (!canRunAuto() || !frames.length) return;
  stopPlayback();
  const run = playback;
  const canPlay = () => run === playback && canRunAuto();
  autoRunning = true;
  renderEffect();
  try {
    const ready = await runStartup(send, [
      { bytes: power(true), key: 'power' },
      { bytes: brightness(targetBrightness()), key: 'brightness' },
    ], canPlay);
    if (!ready) return;
    await player.play(frames, autoOptions.seconds * 1000, {
      dwell: true,
      canPlay,
      write: bytes => send(bytes, 'effect'),
      onFrame(bytes) {
        autoCurrent = bytes[3];
        selectEffect(autoCurrent);
        persist();
        autoStartedAt = performance.now();
        updateAutoProgress();
        autoProgressTimer ??= setInterval(updateAutoProgress, 200);
        render();
      },
    });
  } catch (error) {
    if (canPlay() && !(error instanceof SendFailure)) toast('sceneFailed', true);
  } finally {
    if (run === playback) clearAppAuto();
  }
});
const voiceButtons = $$('[data-voice]');
voiceButtons.forEach(button => button.addEventListener('click', () => {
  if (needsLink()) return;
  const id = Number(button.dataset.voice);
  const mode = { voice: id };
  Object.assign(state, { label: ['musicMode', { id }], scene: `voice:${id}`, mode, on: true });
  persist();
  render();
  startMode(mode);
}));

// Every slider paints its filled part from its own min/max while it is dragged.
document.addEventListener('input', event => {
  const input = event.target;
  if (!input.classList?.contains('range')) return;
  const min = Number(input.min) || 0;
  const max = Number(input.max) || 100;
  input.style.setProperty('--p', `${100 * (Number(input.value) - min) / (max - min)}%`);
});

function renderSpeed() {
  bind('speed').forEach(input => {
    input.value = state.speed;
    input.style.setProperty('--p', `${100 * (state.speed - input.min) / (input.max - input.min)}%`);
  });
  text('speed-out', t('percent', { value: state.speed }));
}
bind('speed').forEach(input => input.addEventListener('input', () => {
  state.speed = Number(input.value);
  persist();
  renderSpeed();
  fire(speed(state.speed), 'speed');
}));

function renderMicSens() {
  const input = bind('mic-sens')[0];
  input.value = state.micSens;
  input.style.setProperty('--p', `${state.micSens}%`);
  text('mic-sens-out', t('percent', { value: state.micSens }));
}
bind('mic-sens')[0].addEventListener('input', event => {
  state.micSens = Number(event.target.value);
  persist();
  renderMicSens();
  // Sensitivity only applies while a voice mode runs; the next voice mode sends the saved value.
  if (state.on && state.mode?.voice) fire(micSensitivity(state.micSens), 'micSens');
});

// ---- connection ----
function connectStrip({ reconnect = false } = {}) {
  const action = reconnect ? link.reconnect() : link.connect();
  action.catch(error => toast(error.code === 'controllerUnsupported' ? error.code : 'connectFailed', true));
}

$('[data-action="connect"]').addEventListener('click', () => connectStrip({ reconnect: link.state.status === 'lost' }));

$$('.acc > button').forEach(button => button.addEventListener('click', () => {
  const open = button.getAttribute('aria-expanded') === 'true';
  const panel = document.getElementById(button.getAttribute('aria-controls'));
  button.setAttribute('aria-expanded', String(!open));
  panel.hidden = open;
  if (open && panel.id === 'strip-settings') showStripConfirmation(false);
}));

function renderLinkText(s = link.state) {
  document.body.dataset.status = s.status;
  $('[data-action="power"]').setAttribute('aria-disabled', String(!link.ready));
  text('chip-text', t(s.status));
  text('name', s.status === 'simulated' ? t('simulatedStrip') : s.name ?? 'LEDDMX');
  text('device-sub', t(s.status === 'simulated'
    ? (s.supported ? 'simulatedFrames' : 'noWebBluetooth')
    : s.status === 'lost' ? 'keepsColor' : 'controller'));
  const connect = $('[data-action="connect"]');
  connect.hidden = !['idle', 'lost', 'connecting'].includes(s.status);
  connect.disabled = s.status === 'connecting';
  connect.querySelector('span').textContent = t(s.status === 'lost' ? 'reconnect' : s.status === 'connecting' ? 'connecting' : 'connect');
  $('[data-action="disconnect"]').hidden = s.status !== 'connected';
}

function renderLink(s) {
  const wasConnected = document.body.dataset.status === 'connected';
  renderLinkText(s);
  render();
  if (s.status === 'lost' && wasConnected) {
    trying = false;
    stopPlayback();
    toast('reconnectPrompt', true);
  }
}

function disconnectStrip() {
  stopPlayback();
  try { link.disconnect(); } catch { toast('disconnectFailed', true); }
}
$('[data-action="disconnect"]').addEventListener('click', disconnectStrip);

// ---- render ----
function renderBrightness() {
  bind('bri').forEach(input => { input.value = state.bri; input.style.setProperty('--p', `${state.bri}%`); });
  text('bri-out', t('percent', { value: state.bri }));
}
function renderLastSent() {
  if (!state.lastSentAt) { text('last-sent', t('noCommand')); return; }
  const s = Math.round((Date.now() - state.lastSentAt) / 1000);
  text('last-sent', t('lastCommand', { time: s < 60 ? `${s} s` : `${Math.round(s / 60)} min` }));
}
// The Home preview and power show "on" only while a strip is connected (or simulated):
// without a link the page cannot know or control what the strip shows.
const shownOn = () => state.on && link.ready;
function renderStrip() {
  const strip = bind('strip')[0];
  const on = shownOn();
  strip.style.setProperty('--strip', on ? (state.mode?.preset ? presetSwatch(state.mode.preset) : rgbCss(state.rgb)) : '#2a2540');
  strip.style.setProperty('--glow', on ? rgbCss(state.rgb).replace(')', ' / .55)') : 'transparent');
  strip.setAttribute('aria-label', t('previewLabel', { label: on ? currentLabel() : t('off') }));
}
function render() {
  const pw = $('[data-action="power"]');
  pw.setAttribute('aria-pressed', String(shownOn()));
  pw.setAttribute('aria-label', t(shownOn() ? 'powerOn' : 'powerOff'));
  text('power-label', shownOn() ? t('onLabel', { label: currentLabel() }) : t('off'));
  const quickId = state.mode?.preset ?? state.scene;
  renderStrip();
  $$('.tile[data-scene]').forEach(t => t.setAttribute('aria-pressed', String(state.on && t.dataset.scene === quickId)));
  $$('.swatch[data-rgb]').forEach(s => s.setAttribute('aria-pressed', String(s.dataset.rgb === state.rgb.join(','))));
  renderColorDisc(state.rgb);
  voiceButtons.forEach(button => button.setAttribute('aria-pressed', String(state.on && state.mode?.voice === Number(button.dataset.voice))));
  renderEffect();
  renderSpeed();
  renderMicSens();
  renderBrightness();
  renderLastSent();
  renderSceneSelection();
}

// ---- bottom sheets ----
const dialog = $('#sheet');
let opener;
let selected;
let trying = false;
let previewClock;

function openSheet(panel, title, trigger, focus = $('#sheet-title')) {
  opener = trigger;
  text('preview-error', '');
  $('#sheet-title').textContent = title;
  sequenceNameInput.hidden = true;
  $('#sheet-title').classList.remove('editing-name');
  sequenceRename.hidden = panel !== 'sequence';
  setSequenceNameError(null);
  sequenceDelete.hidden = panel !== 'sequence' || isNewSequence;
  showSequenceConfirmation(false);
  $$('[data-sheet]').forEach(section => { section.hidden = section.dataset.sheet !== panel; });
  dialog.showModal();
  focus.focus();
}

function stopTry(restore) {
  if (!trying) return;
  trying = false;
  stopPlayback();
  if (restore && link.ready) {
    if (state.on) startMode(currentMode());
    else fire(power(false), 'power');
  }
}

function closeSheet({ restoreTry = true } = {}) {
  stopTry(restoreTry);
  clearInterval(previewClock);
  selected = null;
  editingSequence = null;
  dialog.close();
  const notice = bind('toast')[0];
  if (notice.parentElement === dialog) document.body.append(notice);
  if (opener?.isConnected && !opener.closest('[hidden]')) opener.focus();
}

$('[data-action="close-sheet"]').addEventListener('click', () => closeSheet());
dialog.addEventListener('cancel', event => { event.preventDefault(); closeSheet(); });
let scrimDown = false;
const outsideSheet = ({ clientX, clientY, target }) => {
  const { left, right, top, bottom } = dialog.getBoundingClientRect();
  return target === dialog && (clientX < left || clientX > right || clientY < top || clientY > bottom);
};
dialog.addEventListener('pointerdown', event => { scrimDown = outsideSheet(event); });
dialog.addEventListener('click', event => { if (scrimDown && outsideSheet(event)) closeSheet(); });

// ---- scene gallery ----
const gallery = [
  ...PRESETS.map(({ id, interval }) => ({ id, interval, preset: id })),
  ...['AUTO', 1, 2].map(id => ({ id: `effect:${id}`, effect: id })),
];
const sceneName = scene => scene.preset ? t(scene.preset) : effectTitle(scene.effect);
const intervalInput = $('#step-interval');
const uiMinInterval = Number(intervalInput.min);
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

function currentMode() {
  const legacy = PRESETS.find(p => p.id === state.scene);
  return state.mode ?? (legacy ? { preset: legacy.id, interval: legacy.interval } : { rgb: state.rgb });
}

function sceneSwatch(scene) {
  if (scene.rgb) return rgbCss(scene.rgb);
  if (scene.preset) return presetSwatch(scene.preset);
  return 'linear-gradient(90deg,#ec4899,#a855f7,#22d3ee)';
}

function renderSceneSelection() {
  $$('.scene').forEach(button => button.setAttribute('aria-current', String(state.on && button.dataset.id === state.scene)));
}

function renderScenes() {
  bind('scene-list')[0].replaceChildren(...gallery.map(scene => {
    const button = document.createElement('button');
    button.className = 'scene sequence-card';
    button.dataset.id = scene.id;
    const name = document.createElement('b');
    name.className = 'meta';
    name.textContent = sceneName(scene);
    const strip = document.createElement('span');
    strip.className = 'strip';
    strip.style.setProperty('--strip', sceneSwatch(scene));
    button.append(name, strip);
    attachPress(button, {
      tap: () => (scene.preset ? playPreset(scene.preset, scene.interval) : playEffect(scene.effect)),
      hold: () => openPreview(scene, button),
    });
    return button;
  }));
  renderSceneSelection();
}

function updatePreview() {
  clearInterval(previewClock);
  if (!selected) return;
  const strip = bind('preview-strip')[0];
  const interval = Number(intervalInput.value);
  text('interval-out', `${interval} ms`);
  intervalInput.style.setProperty('--p', `${100 * (interval - uiMinInterval) / (Number(intervalInput.max) - uiMinInterval)}%`);
  strip.style.setProperty('--strip', sceneSwatch(selected));
  // Presets are color frames; bytes 3–5 are logical RGB. Built-in previews are illustrative.
  const colors = selected.preset ? presetFrames(selected.preset, interval).steps.map(({ bytes }) => bytes.slice(3, 6))
    : selected.rgb ? [] : [[236, 72, 153], [168, 85, 247], [34, 211, 238]];
  if (colors.length && !reducedMotion.matches) {
    let step = 0;
    const draw = () => { if (!document.hidden) strip.style.setProperty('--strip', rgbCss(colors[step++ % colors.length])); };
    draw();
    // Keep the on-screen preview slower than the strip for high-contrast modes.
    previewClock = setInterval(draw, selected.preset ? Math.max(350, interval) : 650);
  }
}

function openPreview(scene, trigger) {
  selected = scene;
  bind('page-controls')[0].hidden = !scene.preset;
  intervalInput.value = scene.interval ?? uiMinInterval;
  openSheet('preview', sceneName(scene), trigger);
  updatePreview();
}

intervalInput.addEventListener('input', updatePreview);
reducedMotion.addEventListener('change', updatePreview);

function useScene(apply) {
  // Same warning as every other strip action: close the sheet so the top toast is visible.
  if (!link.ready) { closeSheet(); needsLink(); return; }
  const { id, preset, effect: fx } = selected;
  const mode = preset ? { preset, interval: Number(intervalInput.value) } : { effect: fx };
  if (apply) {
    closeSheet({ restoreTry: false });
    if (preset) playPreset(preset, mode.interval, [preset], id);
    else playEffect(fx);
  } else {
    text('preview-error', '');
    trying = true;
    startMode(mode);
  }
}
$('[data-action="try-scene"]').addEventListener('click', () => useScene(false));
$('[data-action="apply-scene"]').addEventListener('click', () => useScene(true));
$('[data-action="shortcut-change"]').addEventListener('click', () => {
  const index = shortcutIndex;
  const trigger = opener;
  closeSheet();
  openShortcutChooser(index, trigger);
});
$('[data-action="shortcut-left"]').addEventListener('click', () => { storeShortcuts(moveShortcut(shortcuts, shortcutIndex, shortcutIndex - 1)); closeSheet(); });
$('[data-action="shortcut-right"]').addEventListener('click', () => { storeShortcuts(moveShortcut(shortcuts, shortcutIndex, shortcutIndex + 1)); closeSheet(); });
$('[data-action="shortcut-remove"]').addEventListener('click', () => {
  const item = shortcuts[shortcutIndex];
  if (item && shortcutId(item) === (state.mode?.preset ?? state.scene)) clearSceneMode();
  storeShortcuts(removeShortcut(shortcuts, shortcutIndex));
  closeSheet();
});
// "Otro color" uses the same hue wheel as the Color tab; the button adds the picked color.
let shortcutWheelRgb = [255, 0, 0];
const renderShortcutWheel = createHueWheel(bind('shortcut-wheel')[0], rgb => { shortcutWheelRgb = rgb; renderShortcutWheel(rgb); });
renderShortcutWheel(shortcutWheelRgb);
$('[data-action="shortcut-add-wheel"]').addEventListener('click', () => chooseShortcut({ kind: 'color', rgb: [...shortcutWheelRgb] }));
let shortcutPalette;
queueMicrotask(() => {
  shortcutPalette = createPalette({
    place: 'quick',
    container: bind('shortcut-palette')[0],
    mark: rgb => ({ color: hex(rgb).toLowerCase() }),
    current: () => shortcutWheelRgb,
    apply: rgb => { shortcutWheelRgb = [...rgb]; renderShortcutWheel(shortcutWheelRgb); },
  });
});

// Shared palette: tap any circle to apply it and select its replacement slot.
let paletteColors = loadPalette(localStore);
const palettes = [];
function paletteColorLabel(value) {
  const name = colorName(value);
  return name === 'solid' ? t('paletteColorHex', { hex: value.toUpperCase() }) : t(name);
}
function storePalette(next) {
  if (next === paletteColors) return;
  paletteColors = next;
  try { localStore.setItem(PALETTE_KEY, JSON.stringify(paletteColors)); } catch { toast('storageFailed', true); }
  palettes.forEach(palette => palette.render());
}
// Each Favoritos section opens and closes on its own (closed by default, remembered per place).
const favoritesKey = place => `deleluz.webapp.favoritesOpen.${place}`;
function createPalette({ place, container, mark, current, apply }) {
  let slot = null;
  let open = (() => { try { return localStorage.getItem(favoritesKey(place)) === '1'; } catch { return false; } })();
  const grid = container.closest('.swatches') ?? container;
  const toggle = document.createElement('button');
  toggle.className = 'section-toggle favorites-toggle';
  toggle.setAttribute('aria-expanded', 'true');
  toggle.innerHTML = '<span data-i18n="favorites"></span><svg class="chev" width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  toggle.querySelector('span').textContent = t('favorites');
  toggle.addEventListener('click', () => {
    open = !open;
    try { localStorage.setItem(favoritesKey(place), open ? '1' : '0'); } catch { /* keep it for this session */ }
    showOpen();
  });
  grid.before(toggle);
  const plus = document.createElement('button');
  plus.className = 'swatch palette-plus';
  plus.textContent = '+';
  plus.dataset.trash = '';
  const hint = document.createElement('p');
  hint.className = 'small muted palette-hint';
  hint.dataset.i18n = 'paletteHint';
  hint.textContent = t('paletteHint');
  grid.after(hint);
  const showOpen = () => {
    toggle.setAttribute('aria-expanded', String(open));
    grid.hidden = hint.hidden = !open;
  };
  showOpen();
  // While a saved color is lifted, the "+" turns into a trash can: drop it there to delete it.
  const showTrash = on => {
    plus.classList.toggle('trash', on);
    if (on) plus.innerHTML = '<svg width="22" height="22" aria-hidden="true"><use href="#i-trash"/></svg>';
    else plus.textContent = '+';
    plus.setAttribute('aria-label', t(on ? 'dropToDelete' : slot === null ? 'saveSelectedColor' : 'replaceSavedColor'));
  };
  plus.addEventListener('click', () => {
    const value = hex(current());
    if (slot !== null) storePalette(replacePaletteColor(paletteColors, slot, value));
    else if (paletteColors.length >= PALETTE_LIMIT) { toast('paletteFull', true); return; }
    else storePalette(addPaletteColor(paletteColors, value));
    slot = null;
    render();
  });
  function render() {
    plus.setAttribute('aria-label', t(slot === null ? 'saveSelectedColor' : 'replaceSavedColor'));
    const selectedRgb = current();
    const currentHex = selectedRgb && hex(selectedRgb).toLowerCase();
    container.replaceChildren(
      ...paletteColors.map((value, i) => {
        const rgb = rgbFromHex(value);
        const button = document.createElement('button');
        button.className = 'swatch';
        button.style.background = rgbCss(rgb);
        button.setAttribute('aria-label', paletteColorLabel(value));
        button.setAttribute('aria-pressed', String(value === currentHex));
        Object.assign(button.dataset, mark(rgb));
        button.classList.toggle('slot', i === slot);
        button.dataset.index = String(i);
        attachPress(button, {
          tap: () => {
            container.querySelector('.slot')?.classList.remove('slot');
            slot = i;
            button.classList.add('slot');
            plus.setAttribute('aria-label', t('replaceSavedColor'));
            apply(rgb, [colorName(value)]);
          },
          drop: to => { slot = null; storePalette(movePaletteColor(paletteColors, i, to)); },
          trash: () => {
            slot = null;
            storePalette(removePaletteColor(paletteColors, i));
          },
          onLift: () => showTrash(true),
          onEnd: () => showTrash(false),
        });
        return button;
      }),
      plus,
    );
  }
  const palette = { render, showOpen, clearSlot() { slot = null; render(); } };
  palettes.push(palette);
  return palette;
}

// ---- saved color sequences ----
let editingSequence = null;
let isNewSequence = false;
let selectedFrame = 0;
const sequenceList = bind('sequence-list')[0];
const frameList = bind('sequence-frames')[0];
const frameHint = document.createElement('p');
frameHint.className = 'sequence-reorder-hint';
frameHint.dataset.i18n = 'sequenceReorderHint';
frameList.after(frameHint);
const sequenceSwatches = bind('sequence-swatches')[0];
const sequenceAdd = $('[data-action="sequence-add-color"]');
const pickSequenceColor = rgb => editSequence(setFrameColor(editingSequence, selectedFrame, rgb), 'colors');
const renderSequenceWheel = createHueWheel(bind('sequence-wheel')[0], pickSequenceColor);
const sequenceSpeed = $('#sequence-speed');
const sequenceBri = $('#sequence-bri');
const sequenceStop = $('[data-action="sequence-stop"]');
const sequenceNew = $('[data-action="sequence-new"]');
const sequenceDelete = $('[data-action="sequence-delete"]');
const sequenceRename = $('[data-action="sequence-rename"]');
const sequenceNameInput = $('#sequence-name');
sequenceNameInput.maxLength = MAX_SEQUENCE_NAME;

function setSequenceNameError(error) {
  sequenceNameInput.setAttribute('aria-invalid', String(Boolean(error)));
  text('sequence-name-error', error ? t(error, { max: MAX_SEQUENCE_NAME }) : '');
}

sequenceRename.addEventListener('click', () => {
  if (sequenceNameInput.hidden) {
    sequenceNameInput.value = editingSequence.name;
    sequenceNameInput.hidden = false;
    $('#sheet-title').classList.add('editing-name');
    sequenceRename.hidden = true;
  }
  sequenceNameInput.focus();
  sequenceNameInput.select();
});
sequenceNameInput.addEventListener('input', () => {
  editingSequence = { ...editingSequence, name: sequenceNameInput.value };
  setSequenceNameError(null);
});
const sequenceConfirm = $('#sequence-confirm');
const sequenceDeleteCancel = $('[data-action="sequence-delete-cancel"]');
const sequenceCard = id => [...sequenceList.children].find(button => button.dataset.id === sequenceKey(id));

$$('[data-scene-tab]').forEach(button => button.addEventListener('click', () => {
  $$('[data-scene-tab]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  $$('[data-scene-panel]').forEach(panel => { panel.hidden = panel.dataset.scenePanel !== button.dataset.sceneTab; });
  sequenceNew.hidden = button.dataset.sceneTab !== 'mine';
}));
sequenceNew.addEventListener('click', () => {
  if (sequences.length >= MAX_SEQUENCES) return;
  const next = createSequence(sequences, number => t('sequenceName', { number }));
  if (next === sequences) return;
  const draft = next.at(-1);
  // A stale shortcut must not point to a new scene after an old one is deleted.
  draft.id = crypto.getRandomValues(new Uint32Array(4)).join('-');
  openSequence(draft, sequenceNew, true);
});

function sequenceSquares(colors) {
  const row = document.createElement('span');
  row.className = 'sequence-thumb';
  row.setAttribute('aria-hidden', 'true');
  for (const rgb of colors) {
    const square = document.createElement('span');
    square.style.background = rgbCss(rgb);
    row.append(square);
  }
  return row;
}

function renderSequences() {
  bind('sequences-empty')[0].hidden = sequences.length > 0;
  const cards = sequences.map(item => {
    const button = document.createElement('button');
    button.className = 'scene sequence-card';
    button.dataset.id = sequenceKey(item.id);
    const name = document.createElement('b');
    name.className = 'meta';
    name.textContent = item.name;
    button.append(name, sequenceSquares(item.colors));
    attachPress(button, { tap: () => playSequence(item), hold: () => openSequence(item, button) });
    return button;
  });
  sequenceNew.disabled = sequences.length >= MAX_SEQUENCES;
  sequenceList.replaceChildren(...cards);
  renderSceneSelection();
}

function renderSequencePlayback() {
  sequenceStop.disabled = activeSequence !== draftPlayback;
}

function renderSequenceFrames(item, focusFrame = false) {
  const squares = item.colors.map((_, i) => {
    const button = document.createElement('button');
    button.className = 'swatch sequence-frame';
    button.dataset.index = String(i);
    attachPress(button, {
      tap: () => { selectedFrame = i; renderSequencePalette(editingSequence); },
      drop: to => {
        if (!editingSequence) return;
        const selected = editingSequence.colors[selectedFrame];
        const next = moveColor(editingSequence, i, to);
        if (next === editingSequence) return;
        selectedFrame = next.colors.indexOf(selected);
        editSequence(next, 'colors');
        frameList.children[to].focus({ preventScroll: true });
      },
    });
    return button;
  });
  frameList.replaceChildren(...squares);
  sequenceAdd.disabled = item.colors.length === MAX_COLORS;
  $('[data-action="sequence-remove-color"]').disabled = item.colors.length === 1;
  renderSequencePalette(item);
  if (focusFrame) squares[selectedFrame].focus();
}

function renderSequencePalette(item) {
  const rgb = item.colors[selectedFrame];
  [...frameList.children].forEach((button, i) => {
    const frame = item.colors[i];
    button.style.background = rgbCss(frame);
    button.setAttribute('aria-label', t('sequenceFrame', { number: i + 1, hex: hex(frame) }));
    button.setAttribute('aria-pressed', String(i === selectedFrame));
  });
  const value = hex(rgb).toLowerCase();
  [...sequenceSwatches.children].forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.color === value));
  });
  renderSequenceWheel(rgb);
}

function renderSequenceSliders(item) {
  sequenceSpeed.value = speedPercent(item.interval);
  sequenceBri.value = item.bri;
  for (const input of [sequenceSpeed, sequenceBri]) {
    input.style.setProperty('--p', `${100 * (input.value - input.min) / (input.max - input.min)}%`);
  }
  const speedLabel = t('percent', { value: sequenceSpeed.value });
  const intensityLabel = t('percent', { value: item.bri });
  text('sequence-speed-out', speedLabel);
  sequenceSpeed.setAttribute('aria-valuetext', speedLabel);
  text('sequence-bri-out', intensityLabel);
  sequenceBri.setAttribute('aria-valuetext', intensityLabel);
}

let sequencePalette;
function renderSequenceSwatches() {
  sequencePalette ??= createPalette({
    place: 'scene',
    container: sequenceSwatches,
    mark: rgb => ({ color: hex(rgb).toLowerCase() }),
    current: () => editingSequence?.colors[selectedFrame],
    apply: rgb => pickSequenceColor(rgb),
  });
  sequencePalette.clearSlot();
}

function openSequence(item, trigger, isNew = false) {
  editingSequence = { ...item, colors: item.colors.map(rgb => [...rgb]) };
  isNewSequence = isNew;
  selectedFrame = 0;
  text('sequence-error', '');
  renderSequenceSwatches();
  renderSequenceFrames(editingSequence);
  renderSequenceSliders(editingSequence);
  renderSequencePlayback();
  openSheet('sequence', item.name, trigger);
}

function editSequence(next, field, focusFrame = false) {
  editingSequence = next;
  if (field === 'colors') {
    if (frameList.children.length !== next.colors.length) renderSequenceFrames(next, focusFrame);
    else renderSequencePalette(next);
  } else renderSequenceSliders(next);
  if (activeSequence !== draftPlayback || !link.ready) return;
  if (field === 'bri') fire(brightness(targetBrightness(next.bri)), 'brightness');
  else previewSequence();
}

function previewSequence() {
  const { colors, interval, bri } = editingSequence;
  text('sequence-error', '');
  trying = true;
  startMode({ colors, interval }, { sequence: draftPlayback, bri });
}

// The dashed "+" saves the selected square's color (picked on the wheel) as a custom color.
sequenceAdd.addEventListener('click', () => {
  const next = addColor(editingSequence);
  selectedFrame = next.colors.length - 1;
  editSequence(next, 'colors', true);
});
sequenceSpeed.addEventListener('input', () => editSequence({ ...editingSequence, interval: intervalFromSpeed(sequenceSpeed.value) }, 'interval'));
sequenceBri.addEventListener('input', () => editSequence({ ...editingSequence, bri: Number(sequenceBri.value) }, 'bri'));
$('[data-action="sequence-remove-color"]').addEventListener('click', () => {
  const next = removeColor(editingSequence, selectedFrame);
  selectedFrame = Math.min(selectedFrame, next.colors.length - 1);
  editSequence(next, 'colors', true);
});
$('[data-action="sequence-play"]').addEventListener('click', () => {
  if (!link.ready) { closeSheet(); needsLink(); return; }
  previewSequence();
});
function playSequence({ id, name, colors, interval, bri }) {
  if (needsLink()) return;
  const mode = { colors, interval };
  Object.assign(state, { bri, label: name, scene: sequenceKey(id), mode, on: true });
  persist();
  render();
  startMode(mode);
}
function clearSceneMode() {
  const previewColor = activeSequence === draftPlayback && lastPlayedRgb;
  const rgb = previewColor || (state.on && (state.mode?.colors || state.mode?.preset) ? lastPlayedRgb ?? state.rgb : state.rgb);
  trying = false;
  stopPlayback();
  Object.assign(state, { rgb, on: Boolean(previewColor) || state.on }, solidSelection(rgb));
  persist();
  render();
}
sequenceStop.addEventListener('click', () => {
  if (activeSequence !== draftPlayback) return;
  stopTry(true);
  $('[data-action="sequence-play"]').focus();
});
$('[data-action="sequence-save"]').addEventListener('click', () => {
  const { id, name, colors, interval, bri } = editingSequence;
  const renaming = !sequenceNameInput.hidden;
  if (isNewSequence || renaming) {
    const error = sequenceNameError(sequences, id, name);
    setSequenceNameError(error);
    if (error) { sequenceNameInput.focus(); return; }
  }
  const next = isNewSequence ? [...sequences, { ...editingSequence, name: name.trim() }]
    : updateSequence(renaming ? renameSequence(sequences, id, name) : sequences, id, { colors, interval, bri });
  if (!saveSequences(localStore, next)) {
    toast('sequenceSaveFailed', true);
    return;
  }
  sequences = next;
  if (renaming && state.scene === sequenceKey(id)) {
    state.label = name.trim();
    persist();
  }
  renderSequences();
  renderQuick();
  render();
  opener = sequenceCard(id);
  closeSheet();
});

function showSequenceConfirmation(show) {
  sequenceConfirm.hidden = !show;
  sequenceDelete.setAttribute('aria-expanded', String(show));
}
sequenceDelete.addEventListener('click', () => {
  showSequenceConfirmation(true);
  sequenceDeleteCancel.focus();
});
sequenceDeleteCancel.addEventListener('click', () => {
  showSequenceConfirmation(false);
  sequenceDelete.focus();
});
$('[data-action="sequence-delete-confirm"]').addEventListener('click', () => {
  const { id } = editingSequence;
  const next = removeSequence(sequences, id);
  if (!saveSequences(localStore, next)) {
    toast('sequenceDeleteFailed', true);
    return;
  }
  sequences = next;
  const key = sequenceKey(id);
  if (state.scene === key || activeSequence === draftPlayback) clearSceneMode();
  else if (activeSequence === key) stopPlayback();
  renderSequences();
  renderQuick();
  render();
  opener = sequenceNew;
  closeSheet();
});

// ---- foreground off timer ----
let timer;
let wakeLock;
let wakePending = false;
let duration = '15';
const customMinutes = $('#timer-minutes');
const customSeconds = $('#timer-seconds');
const timerError = $('#timer-error');
function showTimerError(invalid) {
  timerError.textContent = invalid ? t('invalidTimer') : '';
  for (const input of [customMinutes, customSeconds]) input.setAttribute('aria-invalid', String(invalid));
}
const fadeInput = $('#timer-fade');

async function requestWakeLock() {
  if (!timer || document.hidden || !navigator.wakeLock || wakePending || (wakeLock && !wakeLock.released)) return;
  const run = timer;
  wakePending = true;
  try {
    const lock = await navigator.wakeLock.request('screen');
    if (timer === run && !document.hidden) wakeLock = lock;
    else await lock.release();
  } catch { /* Wake Lock can be denied; the foreground timer still works. */ }
  finally {
    wakePending = false;
    if (timer && timer !== run) requestWakeLock();
  }
}

function renderTimer(remaining) {
  const chip = bind('timer-chip')[0];
  chip.hidden = !timer;
  bind('timer-note')[0].hidden = !timer;
  if (timer) chip.textContent = t('offIn', { time: formatRemaining(remaining) });
  $('[data-action="cancel-timer"]').hidden = !timer;
  $('[data-action="start-timer"]').textContent = t(timer ? 'restartTimer' : 'startTimer');
}

function stopTimer() {
  const hadFade = timer?.lastLevel != null;
  timer = null;
  wakeLock?.release().catch(() => {});
  wakeLock = null;
  renderTimer(0);
  return hadFade;
}

function targetBrightness(bri = state.bri) {
  if (!timer) return bri;
  return fadeBrightness(bri, (timer.end - performance.now()) / 1000, timer.fade) ?? bri;
}

function updateTimer() {
  if (!timer || document.hidden) return;
  const remaining = (timer.end - performance.now()) / 1000;
  if (remaining <= 0) {
    stopTimer();
    trying = false;
    stopPlayback();
    state.on = false;
    persist();
    render();
    fire(power(false), 'power');
    return;
  }
  renderTimer(remaining);
  const level = fadeBrightness(state.bri, remaining, timer.fade);
  if (level !== null && level !== timer.lastLevel && link.ready) {
    timer.lastLevel = level;
    fire(brightness(level), 'brightness');
  }
}

$('[data-action="timer"]').addEventListener('click', event => openSheet('timer', t('offTimer'), event.currentTarget));
$$('[data-minutes]').forEach(button => button.addEventListener('click', () => {
  duration = button.dataset.minutes;
  $$('[data-minutes]').forEach(option => option.setAttribute('aria-pressed', String(option === button)));
  $('#timer-custom').hidden = duration !== 'custom';
  showTimerError(false);
  if (duration === 'custom') customMinutes.focus();
}));
for (const input of [customMinutes, customSeconds]) input.addEventListener('input', () => showTimerError(false));
$('[data-action="start-timer"]').addEventListener('click', () => {
  if (needsLink()) return;
  const seconds = duration === 'custom' ? parseTimerDuration(customMinutes.value, customSeconds.value) : Number(duration) * 60;
  if (seconds === null) {
    showTimerError(true);
    customMinutes.focus();
    return;
  }
  showTimerError(false);
  if (stopTimer() && link.ready) fire(brightness(state.bri), 'brightness');
  timer = { end: performance.now() + seconds * 1000, fade: fadeInput.checked, lastLevel: null };
  updateTimer();
  requestWakeLock();
  closeSheet();
});
$('[data-action="cancel-timer"]').addEventListener('click', () => {
  if (stopTimer() && link.ready) fire(brightness(state.bri), 'brightness');
  closeSheet();
});

// ---- "more below" hint for the page and the sheet ----
const chevron = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const pageMore = document.createElement('div');
pageMore.className = 'more-below';
pageMore.innerHTML = chevron;
document.body.append(pageMore);
const sheetMore = document.createElement('div');
sheetMore.className = 'sheet-more';
sheetMore.innerHTML = chevron;
dialog.append(sheetMore);
function updateMore() {
  const doc = document.documentElement;
  document.body.classList.toggle('has-more', doc.scrollHeight - innerHeight - scrollY > 24);
  dialog.classList.toggle('has-more', dialog.open && dialog.scrollHeight - dialog.clientHeight - dialog.scrollTop > 24);
}
let moreFrame = 0;
const scheduleMore = () => { cancelAnimationFrame(moreFrame); moreFrame = requestAnimationFrame(updateMore); };
addEventListener('scroll', scheduleMore, { passive: true });
addEventListener('resize', scheduleMore);
dialog.addEventListener('scroll', scheduleMore, { passive: true });
new MutationObserver(scheduleMore).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden', 'open'] });

// ---- swipe left/right between sections ----
// A clear horizontal swipe on the page (not on sliders, the color wheel, a lifted tile or an open sheet)
// moves to the next or previous tab, in the bottom-nav order.
const TAB_ORDER = ['home', 'color', 'scenes', 'settings'];
const currentTab = () => location.hash === '#help' ? 'settings' : (location.hash || '#home').slice(1);
let swipe = null;
const NO_SWIPE = 'input, select, .wheel, .lifted, [data-bind="sequence-frames"], .swatches, nav.tabs, dialog';
addEventListener('touchstart', event => {
  if (dialog.open || event.touches.length !== 1 || event.target.closest(NO_SWIPE)) { swipe = null; return; }
  const touch = event.touches[0];
  swipe = { x: touch.clientX, y: touch.clientY, at: Date.now() };
}, { passive: true });
addEventListener('touchend', event => {
  if (!swipe || dialog.open || document.querySelector('.lifted')) { swipe = null; return; }
  const touch = event.changedTouches[0];
  const dx = touch.clientX - swipe.x;
  const dy = touch.clientY - swipe.y;
  const fast = Date.now() - swipe.at < 600;
  swipe = null;
  if (!fast || Math.abs(dx) < 70 || Math.abs(dx) < Math.abs(dy) * 1.8) return;
  const current = TAB_ORDER.indexOf(currentTab());
  const next = TAB_ORDER[(Math.max(0, current) + (dx < 0 ? 1 : -1) + TAB_ORDER.length) % TAB_ORDER.length];
  location.hash = `#${next}`;
}, { passive: true });

// ---- tabs (hash routing) ----
function route() {
  if (dialog.open) closeSheet();
  showStripConfirmation(false);
  const id = currentTab();
  const target = document.getElementById(id)?.classList.contains('screen') ? id : 'home';
  if (target !== 'color') colorPalette?.clearSlot();
  $$('.screen').forEach(s => { s.hidden = s.id !== target; });
  $$('nav.tabs a').forEach(a => (a.getAttribute('href') === `#${target}` ? a.setAttribute('aria-current', 'page') : a.removeAttribute('aria-current')));
  window.scrollTo(0, 0);
}
addEventListener('hashchange', route);
document.addEventListener('visibilitychange', () => {
  if (document.hidden && (player.playing || autoRunning)) {
    stopPlayback();
    toast('backgroundPause', true);
  }
  renderAppAuto();
  if (!document.hidden) { updateTimer(); requestWakeLock(); }
});

// ---- strip settings ----
const STRIP_SETTINGS_KEY = 'deleluz.webapp.stripSettings';
const stripOrder = $('#strip-order');
const stripDensity = $('#strip-density');
const stripMeters = $('#strip-meters');
const stripTotal = $('#strip-pixels');
const stripError = $('#strip-error');
const stripSend = $('#strip-send');
const stripConfirm = $('#strip-confirm');
const stripConfirmSend = $('#strip-confirm-send');
const stripCancel = $('#strip-cancel');
const readStripPixels = () => validPixels(stripTotal.valueAsNumber);

stripOrder.replaceChildren(...CHIP_ORDERS.map(order => new Option(order, order)));
stripOrder.value = 'GRB';
let stripMode = 'total';
try {
  const saved = JSON.parse(localStore.getItem(STRIP_SETTINGS_KEY));
  const pixels = validPixels(saved?.pixels ?? stripPixels(saved?.density, saved?.meters));
  if (CHIP_ORDERS.includes(saved?.order) && pixels !== null) {
    stripOrder.value = saved.order;
    stripTotal.value = pixels;
    if (saved.mode === 'meter' && stripPixels(saved.density, saved.meters) !== null) {
      stripMode = 'meter';
      stripDensity.value = saved.density;
      stripMeters.value = saved.meters;
    }
  }
} catch { /* Keep defaults if saved strip settings are unavailable. */ }

// Per meter: the total is computed and read-only; Total: only the total is used.
function syncStripTotal() {
  if (stripMode !== 'meter') return;
  stripTotal.value = stripPixels(stripDensity.valueAsNumber, stripMeters.valueAsNumber) ?? '';
}

function renderStripSettings() {
  $('#strip-by-meter').hidden = stripMode !== 'meter';
  stripTotal.readOnly = stripMode === 'meter';
  $$('[data-strip-mode]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.stripMode === stripMode)));
  const invalid = readStripPixels() === null;
  stripError.hidden = !invalid;
  stripSend.disabled = stripConfirmSend.disabled = invalid;
}

function saveStripSettings() {
  if (readStripPixels() === null) return;
  const meter = stripMode === 'meter';
  try {
    localStore.setItem(STRIP_SETTINGS_KEY, JSON.stringify({
      order: stripOrder.value, mode: stripMode, pixels: readStripPixels(),
      ...(meter && { density: stripDensity.valueAsNumber, meters: stripMeters.valueAsNumber }),
    }));
  } catch { toast('storageFailed', true); }
}

$$('[data-strip-mode]').forEach(button => button.addEventListener('click', () => {
  stripMode = button.dataset.stripMode;
  showStripConfirmation(false);
  syncStripTotal();
  renderStripSettings();
  saveStripSettings();
}));

for (const field of [stripOrder, stripDensity, stripMeters, stripTotal]) {
  field.addEventListener('input', () => { syncStripTotal(); renderStripSettings(); });
  field.addEventListener('change', saveStripSettings);
}

function showStripConfirmation(show) {
  stripConfirm.hidden = !show;
  stripSend.setAttribute('aria-expanded', String(show));
}

function closeStripConfirmation() {
  showStripConfirmation(false);
  (stripSend.disabled ? stripDensity : stripSend).focus();
}

stripSend.addEventListener('click', () => {
  if (needsLink()) return;
  showStripConfirmation(true);
  stripCancel.focus();
});
stripCancel.addEventListener('click', closeStripConfirmation);
stripConfirmSend.addEventListener('click', () => {
  const pixels = readStripPixels();
  closeStripConfirmation();
  if (pixels === null || needsLink()) return;
  fire(chipConfig(stripOrder.value, pixels));
});

function renderLanguage() {
  document.documentElement.lang = language;
  $$('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
  $$('[data-i18n-aria]').forEach(el => el.setAttribute('aria-label', t(el.dataset.i18nAria)));
  $$('[data-i18n-placeholder]').forEach(el => el.setAttribute('placeholder', t(el.dataset.i18nPlaceholder)));
  $$('[data-language]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.language === language)));
  renderQuick();
  renderSwatches();
  renderScenes();
  renderSequences();
  autoDuration.replaceChildren(...AUTO_DURATIONS.map(seconds => new Option(
    t(seconds < 60 ? 'durationShortSeconds' : 'durationShortMinutes', { value: seconds < 60 ? seconds : seconds / 60 }), seconds)));
  renderEffectCatalog();
  render();
  renderLinkText();
  renderTimer(timer ? (timer.end - performance.now()) / 1000 : 0);
  if (timerError.textContent) showTimerError(true);
  renderStripSettings();
  if (toastKey) text('toast', t(toastKey));
}

$$('[data-language]').forEach(button => button.addEventListener('click', () => {
  language = button.dataset.language;
  try { localStorage.setItem(LANGUAGE_KEY, language); } catch { toast('storageFailed', true); }
  renderLanguage();
}));

renderLanguage();
route();
if (storageReadFailed) toast('storageReadFailed', true);
else if (storageInvalid) toast('storageInvalid', true);
setInterval(() => { renderLastSent(); updateTimer(); }, 1000);
