import { power, color, brightness, effect, speed, voiceMode } from '../lab/web/protocol.js';
import { effectName } from './effects.js';
import { PRESETS, presetFrames } from '../lab/web/presets.js';
import { createSender } from './sender.js';
import { runStartup } from './startup.js';
import { createPlayer } from './player.js';
import { smoothSteps } from './smooth.js';
import { loadState, persistState, solidSelection } from './state.js';
import { MAX_SHORTCUTS, loadShortcuts, saveShortcuts, addShortcut, replaceShortcut,
  removeShortcut, moveShortcut, gridColumns, filterShortcuts } from './shortcuts.js';
import { MAX_SEQUENCES, MAX_COLORS, loadSequences, saveSequences, createSequence, updateSequence,
  removeSequence, setColor as setFrameColor, addColor, removeColor, moveColor, speedPercent, intervalFromSpeed } from './sequences.js';
import { formatRemaining, fadeBrightness, parseTimerDuration } from './timer.js';
import { createLink } from './ble.js';
import { hueToRgb, hueFromPoint, rgbCss, rgbFromHex } from './color.js';
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
const state = loadState(STORE, { on: false, bri: 80, rgb: WARM, label: ['warmWhite'], scene: 'warm', fx: 1, speed: 50, lastSentAt: null },
  sequences.map(item => sequenceKey(item.id)), () => localStore, presetIds);
let lastPlayedRgb;
const persist = () => {
  const { on, bri, rgb, label, scene, mode, fx, speed: sp } = state;
  if (!persistState(STORE, { on, bri, rgb, label, scene, mode, fx, speed: sp })) toast('storageFailed', true);
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
    else if (mode.voice) await send(voiceMode(mode.voice), 'effect');
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
  button.append(sw, shortcutName(item));
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
    return value !== '0';
  } catch { return true; }
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
const renderColorWheel = createHueWheel(bind('wheel')[0], (rgb, degrees) => chooseColor(rgb, ['hueValue', { degrees }]));

// ---- built-in effects ----
$$('[data-mode]').forEach(button => button.addEventListener('click', () => {
  $$('[data-mode]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  $$('[data-panel]').forEach(p => { p.hidden = p.dataset.panel !== button.dataset.mode; });
  bind('effect-speed')[0].hidden = button.dataset.mode !== 'effects';
}));
const fxInput = bind('fx')[0];
function playEffect(id) {
  if (needsLink()) return;
  if (id !== 'AUTO') state.fx = id;
  const mode = { effect: id };
  Object.assign(state, { label: effectLabel(id), scene: `effect:${id}`, mode, on: true });
  persist();
  render();
  startMode(mode);
}
const clampFx = n => Math.min(210, Math.max(1, Math.round(n) || 1));
const fxAuto = $('[data-action="fx-auto"]');
const isAutoEffect = () => state.on && state.mode?.effect === 'AUTO';
function renderEffect() {
  const auto = isAutoEffect();
  const current = auto ? t('allEffects') : String(state.fx);
  fxInput.value = auto ? '' : current;
  fxInput.placeholder = auto ? current : '';
  fxAuto.setAttribute('aria-pressed', String(auto));
  text('fx-out', current);
  text('fx-name', auto ? t('autoCycleAll') : effectName(state.fx));
}
fxInput.addEventListener('input', () => {
  if (!isAutoEffect() && /^\d+$/.test(fxInput.value)) text('fx-name', effectName(clampFx(Number(fxInput.value))));
});
$('[data-action="fx-prev"]').addEventListener('click', () => playEffect(clampFx(state.fx - 1)));
$('[data-action="fx-next"]').addEventListener('click', () => playEffect(clampFx(state.fx + 1)));
// Typing a number applies it when done (Enter / Listo or leaving the field), like the arrows.
fxInput.addEventListener('change', () => {
  const value = fxInput.value.trim();
  if (/^\d+$/.test(value)) playEffect(clampFx(Number(value)));
  renderEffect();
});
fxInput.addEventListener('keydown', event => {
  if (event.key === 'Enter') { event.preventDefault(); fxInput.blur(); }
  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
    event.preventDefault();
    playEffect(clampFx(state.fx + (event.key === 'ArrowUp' ? 1 : -1)));
  }
});
fxAuto.addEventListener('click', () => playEffect('AUTO'));
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
  text('speed-out', `${state.speed} %`);
}
bind('speed').forEach(input => input.addEventListener('input', () => {
  state.speed = Number(input.value);
  persist();
  renderSpeed();
  fire(speed(state.speed), 'speed');
}));

// ---- connection ----
$$('[data-action="connect"], [data-action="help-connect"]').forEach(button => button.addEventListener('click', () => {
  const action = link.state.status === 'lost' ? link.reconnect() : link.connect();
  action.catch(error => toast(error.code === 'controllerUnsupported' ? error.code : 'connectFailed', true));
}));

function renderLostDetail() {
  const { name, lostAt, status } = link.state;
  const elapsed = Math.max(0, Math.floor((Date.now() - lostAt) / 1000));
  text('help-detail', status === 'lost' ? t('lostDetail', { name: name ?? 'LEDDMX', seconds: elapsed }) : '');
}

$$('.acc button').forEach(button => button.addEventListener('click', () => {
  const open = button.getAttribute('aria-expanded') === 'true';
  button.setAttribute('aria-expanded', String(!open));
  document.getElementById(button.getAttribute('aria-controls')).hidden = open;
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
  const helpConnect = $('[data-action="help-connect"]');
  helpConnect.hidden = connect.hidden;
  helpConnect.disabled = connect.disabled;
  helpConnect.textContent = connect.querySelector('span').textContent;
  bind('help-link')[0].hidden = s.status === 'simulated';
  text('help-status', t(s.status));
  renderLostDetail();
}

function renderLink(s) {
  const wasConnected = document.body.dataset.status === 'connected';
  renderLinkText(s);
  if (s.status === 'lost' && wasConnected) {
    trying = false;
    stopPlayback();
    toast('reconnectPrompt', true);
  }
}

$('[data-action="disconnect"]').addEventListener('click', () => {
  stopPlayback();
  try { link.disconnect(); } catch { toast('disconnectFailed', true); }
});

// ---- render ----
function renderBrightness() {
  bind('bri').forEach(input => { input.value = state.bri; input.style.setProperty('--p', `${state.bri}%`); });
  text('bri-out', `${state.bri}%`);
}
function renderLastSent() {
  if (!state.lastSentAt) { text('last-sent', t('noCommand')); return; }
  const s = Math.round((Date.now() - state.lastSentAt) / 1000);
  text('last-sent', t('lastCommand', { time: s < 60 ? `${s} s` : `${Math.round(s / 60)} min` }));
}
function renderStrip() {
  const strip = bind('strip')[0];
  strip.style.setProperty('--strip', state.on ? (state.mode?.preset ? presetSwatch(state.mode.preset) : rgbCss(state.rgb)) : '#2a2540');
  strip.style.setProperty('--glow', state.on ? rgbCss(state.rgb).replace(')', ' / .55)') : 'transparent');
  strip.setAttribute('aria-label', t('previewLabel', { label: state.on ? currentLabel() : t('off') }));
}
function render() {
  const pw = $('[data-action="power"]');
  pw.setAttribute('aria-pressed', String(state.on));
  pw.setAttribute('aria-label', t(state.on ? 'powerOn' : 'powerOff'));
  text('power-label', state.on ? t('onLabel', { label: currentLabel() }) : t('off'));
  const quickId = state.mode?.preset ?? state.scene;
  renderStrip();
  $$('.tile[data-scene]').forEach(t => t.setAttribute('aria-pressed', String(state.on && t.dataset.scene === quickId)));
  $$('.swatch[data-rgb]').forEach(s => s.setAttribute('aria-pressed', String(s.dataset.rgb === state.rgb.join(','))));
  renderColorWheel(state.rgb);
  voiceButtons.forEach(button => button.setAttribute('aria-pressed', String(state.on && state.mode?.voice === Number(button.dataset.voice))));
  renderEffect();
  renderSpeed();
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
    button.className = 'scene';
    button.dataset.id = scene.id;
    const strip = document.createElement('span');
    strip.className = 'strip';
    strip.style.setProperty('--strip', sceneSwatch(scene));
    const name = document.createElement('b');
    name.className = 'meta';
    name.textContent = sceneName(scene);
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = t(scene.preset ? 'page' : 'builtInTag');
    button.append(strip, name, tag);
    button.addEventListener('click', () => openPreview(scene, button));
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
  const draft = createSequence(sequences, number => t('sequenceName', { number })).at(-1);
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
  text('sequence-speed-out', `${sequenceSpeed.value} %`);
  sequenceSpeed.setAttribute('aria-valuetext', `${sequenceSpeed.value} %`);
  text('sequence-bri-out', `${item.bri}%`);
  sequenceBri.setAttribute('aria-valuetext', `${item.bri}%`);
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
  const { id } = editingSequence;
  const next = isNewSequence ? [...sequences, editingSequence] : updateSequence(sequences, id, editingSequence);
  if (!saveSequences(localStore, next)) {
    toast('sequenceSaveFailed', true);
    return;
  }
  sequences = next;
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

// ---- tabs (hash routing) ----
function route() {
  if (dialog.open) closeSheet();
  const id = (location.hash || '#home').slice(1);
  const target = document.getElementById(id)?.classList.contains('screen') ? id : 'home';
  if (target !== 'color') colorPalette?.clearSlot();
  $$('.screen').forEach(s => { s.hidden = s.id !== target; });
  $$('nav.tabs a').forEach(a => (a.getAttribute('href') === `#${target}` ? a.setAttribute('aria-current', 'page') : a.removeAttribute('aria-current')));
  window.scrollTo(0, 0);
}
addEventListener('hashchange', route);
document.addEventListener('visibilitychange', () => {
  if (document.hidden && player.playing) toast('backgroundPause', true);
  if (!document.hidden) { updateTimer(); requestWakeLock(); }
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
  render();
  renderLinkText();
  renderTimer(timer ? (timer.end - performance.now()) / 1000 : 0);
  if (timerError.textContent) showTimerError(true);
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
setInterval(() => { renderLastSent(); renderLostDetail(); updateTimer(); }, 1000);
