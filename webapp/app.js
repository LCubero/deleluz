import { power, color, brightness, effect, speed } from '../lab/web/protocol.js';
import { PRESETS, presetFrames } from '../lab/web/presets.js';
import { createSender } from './sender.js';
import { runStartup } from './startup.js';
import { createPlayer } from './player.js';
import { smoothSteps } from './smooth.js';
import { loadScenes, saveScene, deleteScene } from './scenes.js';
import { formatRemaining, fadeBrightness, parseTimerDuration } from './timer.js';
import { createLink } from './ble.js';
import { hueToRgb, hueFromPoint, rgbCss } from './color.js';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const bind = name => $$(`[data-bind="${name}"]`);
const text = (name, value) => bind(name).forEach(el => { el.textContent = value; });

// ---- state (what the page last sent; the controller cannot report its real state) ----
const STORE = 'deleluz.webapp.state';
const WARM = [255, 200, 128];
const WHITE = [255, 255, 255];
const saved = (() => { try { return JSON.parse(localStorage.getItem(STORE)) ?? {}; } catch { return {}; } })();
const state = { on: false, bri: 80, rgb: WARM, label: 'Warm white', scene: 'warm', fx: 1, speed: 50, lastSentAt: null, ...saved };
const persist = () => {
  const { on, bri, rgb, label, scene, mode, fx, speed: sp } = state;
  localStorage.setItem(STORE, JSON.stringify({ on, bri, rgb, label, scene, mode, fx, speed: sp }));
};

// ---- link, sender, player ----
const simulate = new URLSearchParams(location.search).has('sim');
const link = createLink({ simulate, onChange: renderLink });
// Lab runs 2-4 (docs/CAPABILITIES.md, Send rate): the strip follows every change down to ~35 ms;
// 50 ms keeps a margin. Page-mode steps keep their own interval (player MIN_INTERVAL).
const SEND_GAP_MS = 50;
const sender = createSender({ write: bytes => link.write(bytes), interval: SEND_GAP_MS });
const player = createPlayer({ send: bytes => { if (!document.hidden) return send(bytes, 'color'); } });
let playback = 0;
function stopPlayback() {
  playback++;
  player.stop();
  sender.cancel();
}

async function startMode(mode) {
  stopPlayback();
  const run = playback;
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
    } else if (mode.rgb) await send(color(...mode.rgb), 'color');
    else await send(effect(mode.effect), 'effect');
  } catch (error) {
    if (run === playback && dialog.open && selected) text('preview-error', error.message);
  }
}

function toast(message, error = false) {
  const el = bind('toast')[0];
  el.textContent = message;
  el.classList.toggle('error', error);
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { el.textContent = ''; }, error ? 6000 : 2500);
}

// User actions that change the strip do nothing until a strip is connected (or simulated),
// so the page never shows On / a color that was not sent.
function needsLink() {
  if (link.ready) return false;
  toast(link.state.status === 'lost' ? 'Connection lost. Tap Reconnect first.' : 'Connect to the strip first.', true);
  return true;
}

async function send(bytes, key) {
  if (!link.ready) {
    toast('Connect to the strip first.', true);
    throw new Error('Not connected');
  }
  try {
    const result = await sender.send(bytes, key);
    if (result === 'sent') { state.lastSentAt = Date.now(); renderLastSent(); }
    return result;
  } catch (error) {
    toast(`Command not sent: ${error.message}`, true);
    throw error;
  }
}
const fire = (bytes, key) => send(bytes, key).catch(() => {});

// ---- quick scenes (Home) ----
const presetName = id => PRESETS.find(p => p.id === id).name;
const QUICK = [
  { id: 'warm', name: 'Warm', label: 'Warm white', rgb: WARM },
  { id: 'christmas-moving', name: 'Christmas', preset: 'christmas-moving', sw: 'linear-gradient(90deg,#ef4444,#22c55e,#fff7e6)' },
  { id: 'police', name: 'Police', preset: 'police', sw: 'linear-gradient(90deg,#ef4444,#3b82f6)' },
  { id: 'rasta', name: 'Rasta', preset: 'rasta', sw: 'linear-gradient(90deg,#22c55e,#facc15,#ef4444)' },
  { id: 'movie', name: 'Movie night', label: 'Movie night', rgb: [124, 58, 237] },
  { id: 'flashing', name: 'Flashing', preset: 'flashing', sw: '#fff' },
];

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

function playPreset(id, interval = PRESETS.find(p => p.id === id).interval, label = presetName(id), scene = id) {
  if (needsLink()) return;
  const mode = { preset: id, interval };
  Object.assign(state, { label, scene, mode, on: true });
  persist();
  render();
  return startMode(mode);
}

function renderQuick() {
  const grid = bind('quick')[0];
  grid.replaceChildren(...QUICK.map(q => {
    const b = document.createElement('button');
    b.className = 'tile';
    b.dataset.scene = q.id;
    const sw = document.createElement('span');
    sw.className = 'sw';
    sw.style.background = q.sw ?? rgbCss(q.rgb);
    b.append(sw, q.name);
    b.addEventListener('click', () => (q.preset ? playPreset(q.preset) : setColor(q.rgb, q.label, q.id)));
    return b;
  }));
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
$('[data-action="white"]').addEventListener('click', () => setColor(WHITE, 'White', 'white'));
$('[data-action="warm"]').addEventListener('click', () => setColor(WARM, 'Warm white', 'warm'));

// ---- color wheel and swatches ----
const SWATCHES = [['Red', [255, 0, 0]], ['Orange', [255, 110, 0]], ['Yellow', [255, 200, 0]], ['Green', [0, 255, 0]],
  ['Cyan', [0, 255, 255]], ['Blue', [0, 0, 255]], ['Pink', [255, 0, 120]], ['White', WHITE]];
bind('swatches')[0].replaceChildren(...SWATCHES.map(([name, rgb]) => {
  const b = document.createElement('button');
  b.className = 'swatch';
  b.style.background = rgbCss(rgb);
  b.setAttribute('aria-label', name);
  b.dataset.rgb = rgb.join(',');
  b.addEventListener('click', () => setColor(rgb, name));
  return b;
}));

const wheel = bind('wheel')[0];
let hue = 0;
function pickHue(next) {
  hue = (next + 360) % 360;
  setColor(hueToRgb(hue), `Hue ${hue}°`);
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
  Object.assign(state, { label: id === 'AUTO' ? 'Auto cycle' : `Effect ${id}`, scene: `effect:${id}`, mode, on: true });
  persist();
  render();
  startMode(mode);
}
const clampFx = n => Math.min(210, Math.max(1, Math.round(n) || 1));
$('[data-action="fx-prev"]').addEventListener('click', () => playEffect(clampFx(state.fx - 1)));
$('[data-action="fx-next"]').addEventListener('click', () => playEffect(clampFx(state.fx + 1)));
$('[data-action="fx-play"]').addEventListener('click', () => playEffect(clampFx(Number(fxInput.value))));
$('[data-action="fx-auto"]').addEventListener('click', () => playEffect('AUTO'));
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
  action.catch(error => toast(`Could not connect: ${error.message}`, true));
}));

function renderLostDetail() {
  const { name, lostAt, status } = link.state;
  const elapsed = Math.max(0, Math.floor((Date.now() - lostAt) / 1000));
  text('help-detail', status === 'lost' ? `${name ?? 'LEDDMX'} · ${elapsed} s ago. The strip keeps its last color.` : '');
}

$$('.acc button').forEach(button => button.addEventListener('click', () => {
  const open = button.getAttribute('aria-expanded') === 'true';
  button.setAttribute('aria-expanded', String(!open));
  document.getElementById(button.getAttribute('aria-controls')).hidden = open;
}));

function renderLink(s = link.state) {
  document.body.dataset.status = s.status;
  $('[data-action="power"]').setAttribute('aria-disabled', String(!link.ready));
  const labels = { idle: 'Not connected', connecting: 'Connecting…', connected: 'Connected', lost: 'Connection lost', simulated: 'Simulation' };
  text('chip-text', labels[s.status]);
  text('name', s.name ?? 'LEDDMX');
  text('device-sub', s.status === 'simulated'
    ? (s.supported ? 'Frames are logged, not sent' : 'This browser has no Web Bluetooth; frames are logged')
    : s.status === 'lost' ? 'The strip keeps its last color' : 'LED strip controller');
  const connect = $('[data-action="connect"]');
  connect.hidden = !['idle', 'lost', 'connecting'].includes(s.status);
  connect.disabled = s.status === 'connecting';
  connect.querySelector('span').textContent = s.status === 'lost' ? 'Reconnect' : s.status === 'connecting' ? 'Connecting…' : 'Connect';
  const helpConnect = $('[data-action="help-connect"]');
  helpConnect.hidden = connect.hidden;
  helpConnect.disabled = connect.disabled;
  helpConnect.textContent = connect.querySelector('span').textContent;
  bind('help-link')[0].hidden = s.status === 'simulated';
  text('help-status', labels[s.status]);
  renderLostDetail();
  if (s.status === 'lost') {
    trying = false;
    stopPlayback();
    if (selected) text('preview-error', 'Connection lost. Reconnect from Home or Help.');
    toast('Connection lost. Tap Reconnect.', true);
  }
}

// ---- render ----
function renderBrightness() {
  bind('bri').forEach(input => { input.value = state.bri; input.style.setProperty('--p', `${state.bri}%`); });
  text('bri-out', `${state.bri}%`);
}
function renderLastSent() {
  if (!state.lastSentAt) { text('last-sent', 'No command sent yet'); return; }
  const s = Math.round((Date.now() - state.lastSentAt) / 1000);
  text('last-sent', `Last command sent ${s < 60 ? `${s} s` : `${Math.round(s / 60)} min`} ago`);
}
function render() {
  const pw = $('[data-action="power"]');
  pw.setAttribute('aria-pressed', String(state.on));
  pw.setAttribute('aria-label', state.on ? 'Power: on. Tap to turn off' : 'Power: off. Tap to turn on');
  text('power-label', state.on ? `On · ${state.label}` : 'Off');
  const quickId = state.mode?.preset ?? state.scene;
  const quick = QUICK.find(q => q.id === quickId);
  const strip = bind('strip')[0];
  strip.style.setProperty('--strip', state.on ? (quick?.sw ?? rgbCss(state.rgb)) : '#2a2540');
  strip.style.setProperty('--glow', state.on ? rgbCss(state.rgb).replace(')', ' / .55)') : 'transparent');
  strip.setAttribute('aria-label', `Strip preview: ${state.on ? state.label : 'off'}`);
  $$('.tile').forEach(t => t.setAttribute('aria-pressed', String(state.on && t.dataset.scene === quickId)));
  $$('.swatch').forEach(s => s.setAttribute('aria-pressed', String(s.dataset.rgb === state.rgb.join(','))));
  wheel.style.setProperty('--c', rgbCss(state.rgb));
  bind('wheel-handle')[0].style.cssText = `left:${50 + 38 * Math.sin(hue * Math.PI / 180)}%;top:${50 - 38 * Math.cos(hue * Math.PI / 180)}%`;
  wheel.setAttribute('aria-valuenow', String(hue));
  fxInput.value = state.fx;
  text('fx-out', String(state.fx));
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
  dialog.close();
  if (opener?.isConnected && !opener.closest('[hidden]')) opener.focus();
  else $('[data-collection="mine"]').focus();
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
  ...PRESETS.map(({ id, name, interval }) => ({ id, name, interval, preset: id })),
  ...['AUTO', 1, 2].map(id => ({ id: `effect:${id}`, name: id === 'AUTO' ? 'Auto cycle' : `Effect ${id}`, effect: id })),
];
let collection = 'included';
const intervalInput = $('#step-interval');
const uiMinInterval = Number(intervalInput.min);
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

function currentMode() {
  const legacy = PRESETS.find(p => p.id === state.scene);
  return state.mode ?? (legacy ? { preset: legacy.id, interval: legacy.interval } : { rgb: state.rgb });
}

function sceneSwatch(scene) {
  if (scene.rgb) return rgbCss(scene.rgb);
  if (scene.preset) return QUICK.find(q => q.id === scene.preset)?.sw ?? 'linear-gradient(90deg,#ef4444,#4f46e5)';
  return 'linear-gradient(90deg,#ec4899,#a855f7,#22d3ee)';
}

function renderSceneSelection() {
  $$('.scene').forEach(button => button.setAttribute('aria-current', String(state.on && button.dataset.id === state.scene)));
}

function renderScenes() {
  const mine = loadScenes(localStorage).map(scene => ({ ...scene, id: `mine:${scene.name}`, own: true }));
  text('mine-count', `Mine (${mine.length})`);
  $$('[data-collection]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.collection === collection)));
  bind('scene-empty')[0].hidden = collection !== 'mine' || mine.length > 0;
  bind('scene-list')[0].replaceChildren(...(collection === 'mine' ? mine : gallery).map(scene => {
    const button = document.createElement('button');
    button.className = 'scene';
    button.dataset.id = scene.id;
    const strip = document.createElement('span');
    strip.className = 'strip';
    strip.style.setProperty('--strip', sceneSwatch(scene));
    const name = document.createElement('b');
    name.className = 'meta';
    name.textContent = scene.name;
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = scene.preset ? 'Page' : scene.rgb ? 'Solid' : 'Built-in';
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
  $('[data-action="delete-scene"]').hidden = !scene.own;
  intervalInput.value = scene.interval ?? uiMinInterval;
  openSheet('preview', scene.name, trigger);
  updatePreview();
}

intervalInput.addEventListener('input', updatePreview);
reducedMotion.addEventListener('change', updatePreview);
$$('[data-collection]').forEach(button => button.addEventListener('click', () => { collection = button.dataset.collection; renderScenes(); }));

function useScene(apply) {
  if (!link.ready) { text('preview-error', 'Connect to the strip first.'); return; }
  const { id, name, preset, rgb, effect: fx } = selected;
  const mode = preset ? { preset, interval: Number(intervalInput.value) } : rgb ? { rgb } : { effect: fx };
  if (apply) {
    closeSheet({ restoreTry: false });
    if (preset) playPreset(preset, mode.interval, name, id);
    else if (rgb) {
      // A Try may have changed power and brightness without changing page state.
      Object.assign(state, { rgb, label: name, scene: id, mode: null, on: true });
      persist();
      render();
      startMode(mode);
    }
    else playEffect(fx);
  } else {
    text('preview-error', '');
    trying = true;
    startMode(mode);
  }
}
$('[data-action="try-scene"]').addEventListener('click', () => useScene(false));
$('[data-action="apply-scene"]').addEventListener('click', () => useScene(true));
$('[data-action="delete-scene"]').addEventListener('click', () => {
  try { deleteScene(localStorage, selected.name); }
  catch (error) { text('preview-error', `Could not delete scene: ${error.message}`); return; }
  renderScenes();
  closeSheet();
});

const saveForm = $('[data-sheet="new"]');
const nameInput = $('#scene-name');
let modeToSave;
$$('[data-action="new-scene"]').forEach(button => button.addEventListener('click', () => {
  modeToSave = currentMode();
  saveForm.reset();
  text('save-error', '');
  text('save-current', modeToSave.effect ? 'Choose a solid color or a page scene before saving.' : `Save current mode: ${state.label}`);
  saveForm.querySelector('[type="submit"]').disabled = Boolean(modeToSave.effect);
  openSheet('new', 'New scene', button, nameInput);
}));
saveForm.addEventListener('submit', event => {
  event.preventDefault();
  if (modeToSave.effect) return;
  try { saveScene(localStorage, nameInput.value, modeToSave); }
  catch (error) { text('save-error', error.message); return; }
  collection = 'mine';
  renderScenes();
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
  timerError.textContent = invalid ? 'Enter whole minutes (0–720) and seconds (0–59), at least 1 second.' : '';
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
  if (timer) chip.textContent = `Off in ${formatRemaining(remaining)}`;
  $('[data-action="cancel-timer"]').hidden = !timer;
  $('[data-action="start-timer"]').textContent = timer ? 'Restart timer' : 'Start timer';
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

$('[data-action="timer"]').addEventListener('click', event => openSheet('timer', 'Off timer', event.currentTarget));
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
  if (document.hidden && player.playing) toast('The scene pauses while the page is in the background.', true);
  if (!document.hidden) { updateTimer(); requestWakeLock(); }
});

renderQuick();
renderScenes();
render();
renderLink();
route();
setInterval(() => { renderLastSent(); renderLostDetail(); updateTimer(); }, 1000);
