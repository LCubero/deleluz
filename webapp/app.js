import { power, color, brightness, effect, speed, voiceMode } from '../lab/web/protocol.js';
import { effectName } from './effects.js';
import { PRESETS, presetFrames } from '../lab/web/presets.js';
import { createSender } from './sender.js';
import { runStartup } from './startup.js';
import { createPlayer } from './player.js';
import { smoothSteps } from './smooth.js';
import { persistState } from './state.js';
import { MAX_SHORTCUTS, loadShortcuts, saveShortcuts, addShortcut, replaceShortcut, removeShortcut, moveShortcut, gridColumns } from './shortcuts.js';
import { MAX_SEQUENCES, MAX_COLORS, loadSequences, saveSequences, createSequence, updateSequence,
  removeSequence, setColor as setFrameColor, addColor, removeColor } from './sequences.js';
import { formatRemaining, fadeBrightness, parseTimerDuration } from './timer.js';
import { createLink } from './ble.js';
import { hueToRgb, hueFromPoint, rgbCss } from './color.js';

import { LANGUAGE_KEY, loadLanguage, translate } from './i18n.js';

let language = loadLanguage({ getItem: key => localStorage.getItem(key) });
const t = (key, vars) => translate(language, key, vars);

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const bind = name => $$(`[data-bind="${name}"]`);
const text = (name, value) => bind(name).forEach(el => { el.textContent = value; });

// ---- state (what the page last sent; the controller cannot report its real state) ----
const STORE = 'deleluz.webapp.state';
const WARM = [255, 200, 128];
const WHITE = [255, 255, 255];
const saved = (() => { try { return JSON.parse(localStorage.getItem(STORE)) ?? {}; } catch { return {}; } })();
const state = { on: false, bri: 80, rgb: WARM, label: ['warmWhite'], scene: 'warm', fx: 1, speed: 50, lastSentAt: null, ...saved };
const persist = () => {
  const { on, bri, rgb, label, scene, mode, fx, speed: sp } = state;
  persistState(STORE, { on, bri, rgb, label, scene, mode, fx, speed: sp });
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
  if (await send(bytes, 'color') === 'sent' && run === playback && activeSequence) {
    state.rgb = Array.from(bytes.subarray(3, 6));
    renderStrip();
  }
} });
let playback = 0;
let activeSequence = null;
function stopPlayback() {
  playback++;
  player.stop();
  sender.cancel();
  activeSequence = null;
  renderSequencePlayback();
}

async function startMode(mode) {
  stopPlayback();
  const run = playback;
  if (mode.colors) {
    activeSequence = state.scene;
    renderSequencePlayback();
  }
  try {
    const ready = await runStartup(send, [
      { bytes: power(true), key: 'power' },
      { bytes: brightness(targetBrightness()), key: 'brightness' },
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
  } catch {
    if (run === playback && dialog.open) {
      if (selected) text('preview-error', t('sceneFailed'));
      if (activeSequence === sequenceKey(editingSequence)) text('sequence-error', t('sceneFailed'));
    }
  } finally {
    if (run === playback && mode.colors) {
      activeSequence = null;
      renderSequencePlayback();
    }
  }
}

let toastKey;
function toast(key, error = false) {
  toastKey = key;
  const el = bind('toast')[0];
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

async function send(bytes, key) {
  if (!link.ready) {
    toast('connectFirst', true);
    throw new Error('Not connected');
  }
  try {
    const result = await sender.send(bytes, key);
    if (result === 'sent') { state.lastSentAt = Date.now(); renderLastSent(); }
    return result;
  } catch (error) {
    toast('commandFailed', true);
    throw error;
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
const presetIds = PRESETS.map(p => p.id);
let shortcuts = loadShortcuts(localStorage, presetIds);
const hex = rgb => `#${rgb.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
const shortcutName = item => item.kind === 'scene' ? t(item.preset) : item.name ? t(item.name) : t('colorHex', { hex: hex(item.rgb) });
const shortcutId = item => item.kind === 'scene' ? item.preset : `color:${item.rgb.join(',')}`;

function storeShortcuts(next) {
  shortcuts = next;
  saveShortcuts(localStorage, shortcuts);
  renderQuick();
  render();
}

function applyShortcut(item) {
  if (item.kind === 'scene') playPreset(item.preset);
  else setColor(item.rgb, item.name ? [item.name] : ['colorHex', { hex: hex(item.rgb) }], shortcutId(item));
}

const HOLD_MS = 450;
const SLOP = 8;
// Tap applies; press and hold opens the options; hold and drag reorders.
function attachPress(button, index, item) {
  let timer;
  let start = null;
  let lifted = false;
  let moved = false;
  let suppress = false;
  const reset = () => {
    clearTimeout(timer);
    button.classList.remove('lifted');
    button.style.transform = '';
    button.style.pointerEvents = '';
    start = null;
    lifted = false;
  };
  button.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    start = { x: event.clientX, y: event.clientY, id: event.pointerId };
    moved = false;
    timer = setTimeout(() => {
      lifted = true;
      button.classList.add('lifted');
      try { button.setPointerCapture(start.id); } catch { /* the pointer may already be gone */ }
      navigator.vibrate?.(15);
    }, HOLD_MS);
  });
  button.addEventListener('pointermove', event => {
    if (!start) return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    if (!lifted) {
      if (Math.hypot(dx, dy) > SLOP) { clearTimeout(timer); start = null; }
      return;
    }
    if (Math.hypot(dx, dy) > SLOP) moved = true;
    if (moved) {
      button.style.pointerEvents = 'none';
      button.style.transform = `translate(${dx}px,${dy}px)`;
    }
  });
  button.addEventListener('touchmove', event => { if (lifted) event.preventDefault(); }, { passive: false });
  button.addEventListener('pointerup', event => {
    if (!lifted) { reset(); return; }
    suppress = true;
    const target = moved ? document.elementFromPoint(event.clientX, event.clientY)?.closest('[data-index]') : null;
    const wasMoved = moved;
    reset();
    if (wasMoved) {
      const to = target ? Number(target.dataset.index) : index;
      if (to !== index) storeShortcuts(moveShortcut(shortcuts, index, to));
    } else openShortcutMenu(index, button);
  });
  button.addEventListener('pointercancel', reset);
  button.addEventListener('click', event => {
    if (suppress) { suppress = false; event.preventDefault(); return; }
    applyShortcut(item);
  });
  button.addEventListener('contextmenu', event => {
    event.preventDefault();
    if (start || lifted) return; // a touch long-press is handled by the hold timer
    openShortcutMenu(index, button);
  });
}

function renderQuick() {
  const grid = bind('quick')[0];
  const tiles = shortcuts.map((item, index) => {
    const button = document.createElement('button');
    button.className = 'tile';
    button.dataset.index = String(index);
    button.dataset.scene = shortcutId(item);
    const sw = document.createElement('span');
    sw.className = 'sw';
    sw.style.background = item.kind === 'scene' ? presetSwatch(item.preset) : rgbCss(item.rgb);
    button.append(sw, shortcutName(item));
    attachPress(button, index, item);
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

function openShortcutChooser(index, trigger) {
  shortcutIndex = index;
  bind('shortcut-colors')[0].replaceChildren(...SWATCHES.map(([name, rgb]) => {
    const button = document.createElement('button');
    button.className = 'swatch';
    button.style.background = rgbCss(rgb);
    button.setAttribute('aria-label', t(name));
    button.addEventListener('click', () => chooseShortcut({ kind: 'color', name, rgb: [...rgb] }));
    return button;
  }));
  bind('shortcut-scenes')[0].replaceChildren(...PRESETS.map(({ id }) => {
    const button = document.createElement('button');
    button.className = 'tile';
    const sw = document.createElement('span');
    sw.className = 'sw';
    sw.style.background = presetSwatch(id);
    button.append(sw, t(id));
    button.addEventListener('click', () => chooseShortcut({ kind: 'scene', preset: id }));
    return button;
  }));
  openSheet('shortcut-pick', t(index === null ? 'addShortcut' : 'changeShortcut'), trigger);
}

function chooseShortcut(item) {
  storeShortcuts(shortcutIndex === null ? addShortcut(shortcuts, item) : replaceShortcut(shortcuts, shortcutIndex, item));
  closeSheet();
}

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
const SWATCHES = [['red', [255, 0, 0]], ['orange', [255, 110, 0]], ['yellow', [255, 200, 0]], ['green', [0, 255, 0]],
  ['cyan', [0, 255, 255]], ['blue', [0, 0, 255]], ['pink', [255, 0, 120]], ['white', WHITE]];
function renderSwatches() {
  bind('swatches')[0].replaceChildren(...SWATCHES.map(([name, rgb]) => {
    const b = document.createElement('button');
    b.className = 'swatch';
    b.style.background = rgbCss(rgb);
    b.setAttribute('aria-label', t(name));
    b.dataset.rgb = rgb.join(',');
    b.addEventListener('click', () => setColor(rgb, [name]));
    return b;
  }));
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

const wheel = bind('wheel')[0];
let hue = 0;
function pickHue(next) {
  hue = (next + 360) % 360;
  setColor(hueToRgb(hue), ['hueValue', { degrees: hue }]);
}
function wheelPoint(event) {
  const r = wheel.getBoundingClientRect();
  pickHue(hueFromPoint(event.clientX - r.left - r.width / 2, event.clientY - r.top - r.height / 2));
}
wheel.addEventListener('pointerdown', event => { wheel.setPointerCapture(event.pointerId); wheelPoint(event); });
wheel.addEventListener('pointermove', event => { if (wheel.hasPointerCapture(event.pointerId)) wheelPoint(event); });
wheel.addEventListener('keydown', event => {
  const step = { ArrowRight: 5, ArrowUp: 5, ArrowLeft: -5, ArrowDown: -5 }[event.key];
  if (step) { event.preventDefault(); pickHue(hue + step); }
});

// ---- built-in effects ----
$$('[data-mode]').forEach(button => button.addEventListener('click', () => {
  $$('[data-mode]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  $$('[data-panel]').forEach(p => { p.hidden = p.dataset.panel !== button.dataset.mode; });
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
fxInput.addEventListener('input', () => text('fx-name', effectName(clampFx(Number(fxInput.value)))));
$('[data-action="fx-prev"]').addEventListener('click', () => playEffect(clampFx(state.fx - 1)));
$('[data-action="fx-next"]').addEventListener('click', () => playEffect(clampFx(state.fx + 1)));
$('[data-action="fx-play"]').addEventListener('click', () => playEffect(clampFx(Number(fxInput.value))));
$('[data-action="fx-auto"]').addEventListener('click', () => playEffect('AUTO'));
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

bind('speed')[0].addEventListener('input', event => {
  state.speed = Number(event.target.value);
  persist();
  text('speed-out', String(state.speed));
  fire(speed(state.speed), 'speed');
});

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
  renderLinkText(s);
  if (s.status === 'lost') {
    trying = false;
    if (activeSequence && activeSequence === sequenceKey(editingSequence)) text('sequence-error', t('previewLost'));
    stopPlayback();
    if (selected) text('preview-error', t('previewLost'));
    toast('reconnectPrompt', true);
  }
}

$('[data-action="disconnect"]').addEventListener('click', () => {
  stopPlayback();
  link.disconnect();
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
  $$('.tile').forEach(t => t.setAttribute('aria-pressed', String(state.on && t.dataset.scene === quickId)));
  $$('.swatch[data-rgb]').forEach(s => s.setAttribute('aria-pressed', String(s.dataset.rgb === state.rgb.join(','))));
  wheel.style.setProperty('--c', rgbCss(state.rgb));
  bind('wheel-handle')[0].style.cssText = `left:${50 + 38 * Math.sin(hue * Math.PI / 180)}%;top:${50 - 38 * Math.cos(hue * Math.PI / 180)}%`;
  wheel.setAttribute('aria-valuenow', String(hue));
  voiceButtons.forEach(button => button.setAttribute('aria-pressed', String(state.on && state.mode?.voice === Number(button.dataset.voice))));
  fxInput.value = state.fx;
  text('fx-out', String(state.fx));
  text('fx-name', effectName(state.fx));
  bind('speed')[0].value = state.speed;
  bind('speed')[0].style.setProperty('--p', `${state.speed}%`);
  text('speed-out', String(state.speed));
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
  $$('[data-sheet]').forEach(section => { section.hidden = section.dataset.sheet !== panel; });
  dialog.showModal();
  focus.focus();
}

function closeSheet({ restoreTry = true } = {}) {
  if (trying) {
    trying = false;
    stopPlayback();
    if (restoreTry && link.ready) {
      if (state.on) startMode(currentMode());
      else fire(power(false), 'power');
    }
  }
  clearInterval(previewClock);
  selected = null;
  editingSequence = null;
  dialog.close();
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
$('[data-action="shortcut-remove"]').addEventListener('click', () => { storeShortcuts(removeShortcut(shortcuts, shortcutIndex)); closeSheet(); });
bind('shortcut-other')[0].addEventListener('change', event => {
  const value = event.target.value.slice(1);
  chooseShortcut({ kind: 'color', rgb: [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16)) });
});

// ---- saved color sequences ----
const sequenceStorage = {
  getItem: key => localStorage.getItem(key),
  setItem: (key, value) => localStorage.setItem(key, value),
};
let sequences = loadSequences(sequenceStorage);
let editingSequence = null;
let selectedFrame = 0;
const sequenceKey = id => `sequence:${id}`;
const sequenceList = bind('sequence-list')[0];
const frameList = bind('sequence-frames')[0];
const sequenceOther = bind('sequence-other')[0];
const sequenceSpeed = $('#sequence-speed');
const sequenceBri = $('#sequence-bri');
const sequenceStop = $('[data-action="sequence-stop"]');
const editedSequence = () => sequences.find(item => item.id === editingSequence);
const sequenceCard = id => [...sequenceList.children].find(button => button.dataset.id === sequenceKey(id));

$$('[data-scene-tab]').forEach(button => button.addEventListener('click', () => {
  $$('[data-scene-tab]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  $$('[data-scene-panel]').forEach(panel => { panel.hidden = panel.dataset.scenePanel !== button.dataset.sceneTab; });
}));

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
    button.addEventListener('click', () => openSequence(item.id, button));
    return button;
  });
  if (sequences.length < MAX_SEQUENCES) {
    const add = document.createElement('button');
    add.className = 'scene sequence-card sequence-new';
    add.textContent = t('newSequence');
    add.addEventListener('click', () => {
      sequences = createSequence(sequences, number => t('sequenceName', { number }));
      const { id } = sequences.at(-1);
      const saved = saveSequences(sequenceStorage, sequences);
      renderSequences();
      openSequence(id, sequenceCard(id));
      showSequenceSave(saved);
    });
    cards.push(add);
  }
  sequenceList.replaceChildren(...cards);
  renderSceneSelection();
}

function renderSequencePlayback() {
  // Only the sequence in this editor can be stopped from here.
  sequenceStop.disabled = !editingSequence || activeSequence !== sequenceKey(editingSequence);
}

function renderSequenceFrames(item, focusFrame = false) {
  const squares = item.colors.map((rgb, i) => {
    const button = document.createElement('button');
    button.className = 'swatch sequence-frame';
    button.style.background = rgbCss(rgb);
    button.setAttribute('aria-label', t('sequenceFrame', { number: i + 1, hex: hex(rgb) }));
    button.addEventListener('click', () => { selectedFrame = i; renderSequencePalette(item); });
    return button;
  });
  const add = document.createElement('button');
  add.className = 'btn ghost sequence-frame';
  add.textContent = '+';
  add.setAttribute('aria-label', t('addFrame'));
  add.disabled = item.colors.length === MAX_COLORS;
  add.addEventListener('click', () => {
    const next = addColor(item);
    selectedFrame = next.colors.length - 1;
    editSequence(next, 'colors', true);
  });
  frameList.replaceChildren(...squares, add);
  $('[data-action="sequence-remove-color"]').disabled = item.colors.length === 1;
  renderSequencePalette(item);
  if (focusFrame) squares[selectedFrame].focus();
}

function renderSequencePalette(item) {
  const rgb = item.colors[selectedFrame];
  [...frameList.querySelectorAll('.swatch')].forEach((button, i) => button.setAttribute('aria-pressed', String(i === selectedFrame)));
  [...bind('sequence-swatches')[0].children].forEach((button, i) => {
    button.setAttribute('aria-pressed', String(hex(SWATCHES[i][1]) === hex(rgb)));
  });
  sequenceOther.value = hex(rgb).toLowerCase();
}

// The slider moves toward faster playback as the value increases; the readout is the actual interval.
const reverseInterval = value => Number(sequenceSpeed.min) + Number(sequenceSpeed.max) - Number(value);
function renderSequenceSliders(item) {
  sequenceSpeed.value = reverseInterval(item.interval);
  sequenceBri.value = item.bri;
  for (const input of [sequenceSpeed, sequenceBri]) {
    input.style.setProperty('--p', `${100 * (input.value - input.min) / (input.max - input.min)}%`);
  }
  text('sequence-speed-out', `${item.interval} ms`);
  sequenceSpeed.setAttribute('aria-valuetext', `${item.interval} ms`);
  text('sequence-bri-out', `${item.bri}%`);
  sequenceBri.setAttribute('aria-valuetext', `${item.bri}%`);
}

function openSequence(id, trigger) {
  editingSequence = id;
  selectedFrame = 0;
  const item = editedSequence();
  text('sequence-error', '');
  bind('sequence-swatches')[0].replaceChildren(...SWATCHES.map(([name, rgb]) => {
    const button = document.createElement('button');
    button.className = 'swatch';
    button.style.background = rgbCss(rgb);
    button.setAttribute('aria-label', t(name));
    button.addEventListener('click', () => editSequence(setFrameColor(editedSequence(), selectedFrame, rgb), 'colors'));
    return button;
  }));
  renderSequenceFrames(item);
  renderSequenceSliders(item);
  renderSequencePlayback();
  openSheet('sequence', item.name, trigger);
}

function showSequenceSave(saved) {
  text('sequence-error', saved ? '' : t('sequenceSaveFailed'));
}

function editSequence(next, field, focusFrame = false) {
  sequences = updateSequence(sequences, next.id, { [field]: next[field] });
  showSequenceSave(saveSequences(sequenceStorage, sequences));
  if (field === 'colors') {
    renderSequenceFrames(next, focusFrame);
    sequenceCard(next.id).lastElementChild.replaceWith(sequenceSquares(next.colors));
  } else renderSequenceSliders(next);
  if (activeSequence !== sequenceKey(next.id) || !link.ready) return;
  if (field === 'bri') {
    state.bri = next.bri;
    persist();
    renderBrightness();
    fire(brightness(targetBrightness()), 'brightness');
  } else {
    state.mode = { colors: next.colors, interval: next.interval };
    persist();
    startMode(state.mode);
  }
}

sequenceOther.addEventListener('change', () => {
  if (!editingSequence) return;
  const value = sequenceOther.value;
  const rgb = [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
  editSequence(setFrameColor(editedSequence(), selectedFrame, rgb), 'colors');
});
sequenceSpeed.addEventListener('input', () => editSequence({ ...editedSequence(), interval: reverseInterval(sequenceSpeed.value) }, 'interval'));
sequenceBri.addEventListener('input', () => editSequence({ ...editedSequence(), bri: Number(sequenceBri.value) }, 'bri'));
$('[data-action="sequence-remove-color"]').addEventListener('click', () => {
  const next = removeColor(editedSequence(), selectedFrame);
  selectedFrame = Math.min(selectedFrame, next.colors.length - 1);
  editSequence(next, 'colors', true);
});
$('[data-action="sequence-play"]').addEventListener('click', () => {
  if (!link.ready) { closeSheet(); needsLink(); return; }
  const { id, name, colors, interval, bri } = editedSequence();
  const mode = { colors, interval };
  Object.assign(state, { bri, label: name, scene: sequenceKey(id), mode, on: true });
  persist();
  render();
  startMode(mode);
});
function clearSequenceMode() {
  Object.assign(state, { label: ['colorHex', { hex: hex(state.rgb) }], scene: null, mode: null });
  persist();
  render();
}
sequenceStop.addEventListener('click', () => {
  if (activeSequence !== sequenceKey(editingSequence)) return;
  stopPlayback();
  clearSequenceMode();
  $('[data-action="sequence-play"]').focus();
});
$('[data-action="sequence-delete"]').addEventListener('click', () => {
  const key = sequenceKey(editingSequence);
  if (activeSequence === key) stopPlayback();
  if (state.scene === key) clearSequenceMode();
  sequences = removeSequence(sequences, editingSequence);
  const saved = saveSequences(sequenceStorage, sequences);
  renderSequences();
  opener = sequenceList.querySelector('.sequence-new');
  closeSheet();
  if (!saved) toast('sequenceSaveFailed', true);
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

function targetBrightness() {
  if (!timer) return state.bri;
  return fadeBrightness(state.bri, (timer.end - performance.now()) / 1000, timer.fade) ?? state.bri;
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

// ---- tabs (hash routing) ----
function route() {
  if (dialog.open) closeSheet();
  const id = (location.hash || '#home').slice(1);
  const target = document.getElementById(id)?.classList.contains('screen') ? id : 'home';
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
  try { localStorage.setItem(LANGUAGE_KEY, language); } catch { /* Keep the choice for this session. */ }
  renderLanguage();
}));

renderLanguage();
route();
setInterval(() => { renderLastSent(); renderLostDetail(); updateTimer(); }, 1000);
