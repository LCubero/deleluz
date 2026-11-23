import { power, color, brightness, effect, speed, experimentalFrame, hex } from './protocol.js';

import { PRESETS, SEND_INTERVAL, presetFrames } from './presets.js';

const $ = id => document.getElementById(id);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const rgb = value => value.slice(1).match(/../g).map(byte => Number.parseInt(byte, 16));
const mix = (from, to, ratio) => rgb(from).map((byte, i) => Math.round(byte + (rgb(to)[i] - byte) * ratio));
const colorHex = channels => '#' + hex(channels).replaceAll(' ', '').toLowerCase();
function number(input) {
  if (!input.reportValidity()) throw new Error('Check the highlighted number');
  return input.valueAsNumber;
}
const results = ['worked', 'no change', 'unexpected'];
function log(message, sent) {
  const target = $('log');
  const row = document.createElement('div');
  const label = document.createElement('div');
  label.textContent = `${sent?.sentAt ?? new Date().toISOString()}  ${message}`;
  row.append(label);
  if (sent) {
    const controls = document.createElement('div');
    controls.className = 'log-actions';
    const status = document.createElement('span');
    status.setAttribute('role', 'status');
    for (const result of results) {
      const button = document.createElement('button');
      button.textContent = result;
      button.onclick = () => {
        try {
          saveObservation(sent, result);
          status.textContent = `Saved: ${result}`;
        } catch (error) { log(`Error: ${error.message}`); }
      };
      controls.append(button);
    }
    controls.append(status);
    row.append(controls);
  }
  target.append(row);
  if (target.childElementCount > 500) target.firstElementChild.remove();
  target.scrollTop = target.scrollHeight;
}
function action(id, handler) {
  $(id).addEventListener('click', async () => {
    try { await handler(); } catch (error) { log(`Error: ${error.message}`); }
  });
}

let device, writer, connecting = false, generation = 0;
const simulate = $('simulate');
if (!navigator.bluetooth) simulate.checked = simulate.disabled = true;
function connectionStatus() {
  $('status').textContent = simulate.checked ? 'Simulation: no Bluetooth writes' : connecting ? 'Connecting…' : writer ? `Connected: ${device.name}` : 'Disconnected';
  $('connect').disabled = simulate.checked || connecting || !!writer;
  $('reconnect').disabled = $('connect').disabled || !device;
  $('disconnect').disabled = !writer || connecting;
  if (navigator.bluetooth) simulate.disabled = connecting;
}
function disconnected() {
  writer = undefined;
  generation++;
  playback?.abort();
  rateRun?.controller.abort();
  $('unlock').checked = false;
  connectionStatus();
  log('Disconnected');
}
function step(label, promise, ms = 15000) {
  log(`${label}…`);
  let timer;
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms / 1000} s`)), ms); });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
async function connect(reconnect) {
  connecting = true;
  connectionStatus();
  try {
    if (!reconnect) {
      const chosen = await navigator.bluetooth.requestDevice({ filters: [{ namePrefix: 'LEDDMX' }], optionalServices: [0xffe0] });
      device?.removeEventListener('gattserverdisconnected', disconnected);
      device = chosen;
      device.addEventListener('gattserverdisconnected', disconnected);
    }
    // Lab runs 5-5b: about half of fresh connects fail at once with "Connection attempt failed"; an immediate retry usually works.
    let server;
    for (let attempt = 1; ; attempt++) {
      try { server = await step(`GATT connect (attempt ${attempt})`, device.gatt.connect()); break; }
      catch (error) {
        if (attempt >= 4 || !/attempt failed/i.test(error.message)) throw error;
        log(`Connect attempt ${attempt} failed; retrying`);
        await new Promise(resolve => setTimeout(resolve, 300));
      }
    }
    const service = await step('Service FFE0', server.getPrimaryService(0xffe0));
    const writeChar = await step('Characteristic FFE1', service.getCharacteristic(0xffe1));
    if (!writeChar.properties.writeWithoutResponse) throw new Error('FFE1 does not support write without response');
    for (const [uuid, label] of [[0xffe1, 'FFE1'], [0xffe2, 'FFE2']]) {
      try {
        const characteristic = uuid === 0xffe1 ? writeChar : await step(`Characteristic ${label}`, service.getCharacteristic(uuid), 5000);
        await step(`${label} notifications`, characteristic.startNotifications(), 5000);
        characteristic.oncharacteristicvaluechanged = ({ target: { value } }) => {
          log(`RX ${label} ${hex(new Uint8Array(value.buffer, value.byteOffset, value.byteLength))}`);
        };
      } catch (error) { log(`${label} notifications unavailable: ${error.message}`); }
    }
    if (!server.connected) throw new Error('Device disconnected during setup');
    writer = writeChar;
    log(`Connected: ${device.name}`);
  } catch (error) {
    if (device?.gatt.connected) device.gatt.disconnect();
    throw error;
  } finally {
    connecting = false;
    connectionStatus();
  }
}
action('connect', () => connect(false));
action('reconnect', () => connect(true));
action('disconnect', () => device.gatt.disconnect());
simulate.addEventListener('change', () => {
  generation++;
  playback?.abort();
  rateRun?.controller.abort();
  $('unlock').checked = false;
  if (simulate.checked && device?.gatt.connected) {
    writer = undefined;
    device.gatt.disconnect();
  }
  connectionStatus();
});
connectionStatus();

let queue = Promise.resolve(), nextSend = 0, lastSent, pending = 0, rateRun;
let sendId = 0;
const pageId = Date.now();
function send(bytes, twice = false, signal, rateBatch) {
  if (rateRun && rateBatch?.run !== rateRun) throw new Error('Stop the rate test before sending other commands');
  const simulated = simulate.checked;
  const destination = writer;
  const session = generation;
  if (!simulated && !destination) throw new Error('Connect or enable simulation first');
  if (pending >= 12) throw new Error('Send queue is full; wait for pending frames');
  pending++;
  const task = queue.then(async () => {
    async function write() {
      while (performance.now() < nextSend) {
        const delay = nextSend - performance.now();
        await (signal ? wait(delay, signal) : sleep(delay));
      }
      signal?.throwIfAborted();
      if (session !== generation) throw new Error('Connection changed; queued frame canceled');
      const sentAt = new Date().toISOString();
      const sendMs = performance.now();
      nextSend = sendMs + (rateBatch?.interval ?? SEND_INTERVAL);
      let rate;
      if (rateBatch) {
        const previous = rateBatch.samples.at(-1);
        rate = { runId: rateBatch.run.id, intervalMs: rateBatch.interval, index: rateBatch.samples.length + 1,
          gapMs: previous ? Math.round((sendMs - previous.sendMs) * 10) / 10 : null };
      }
      const frame = hex(bytes);
      const sent = { id: `${pageId}-${++sendId}`, frame, sentAt, sendMs, simulated,
        effect: bytes[0] === 0x7b && bytes[2] === 3 ? (bytes[3] === 255 ? 'AUTO' : bytes[3]) : null,
        ...(rate && { rate }) };
      let failure;
      try {
        if (!simulated) await destination.writeValueWithoutResponse(bytes);
      } catch (error) { failure = error; }
      if (rateBatch) rateBatch.samples.push({ ...sent, ...(failure && { error: failure.message }) });
      const timing = rate ? ` · rate ${rate.intervalMs} ms #${rate.index}${rate.gapMs === null ? '' : ` · gap ${rate.gapMs} ms`}` : '';
      if (failure) {
        log(`Write failed: ${frame}${timing} (${sentAt})`);
        throw failure;
      }
      log(`${simulated ? 'SIM' : 'TX'} ${frame}${timing}`, sent);
      lastSent = sent;
      $('target').textContent = `${simulated ? 'Simulated' : 'Sent'}: ${frame}${sent.effect === null ? '' : ` (effect ${sent.effect})`}`;
    }
    await write();
    if (twice) await write();
  }).finally(() => pending--);
  queue = task.catch(() => {});
  return task;
}
action('on', () => send(power(true)));
action('off', () => send(power(false), $('repeat').checked));
action('send-color', () => send(color(...rgb($('color').value))));
for (const [name, value] of [['Red', '#ff0000'], ['Green', '#00ff00'], ['Blue', '#0000ff'], ['White', '#ffffff']]) {
  const swatch = document.createElement('button');
  swatch.textContent = name;
  swatch.style.setProperty('--swatch', value);
  $('swatches').append(swatch);
  swatch.id = `swatch-${name.toLowerCase()}`;
  action(swatch.id, () => { $('color').value = value; return send(color(...rgb(value))); });
}
action('send-brightness', () => send(brightness(number($('brightness')))));
for (let id = 1; id <= 210; id++) $('effect').add(new Option(id, id));
$('effect').add(new Option('AUTO', 'AUTO'));
const sendEffect = () => send(effect($('effect').value === 'AUTO' ? 'AUTO' : Number($('effect').value)));
action('send-effect', sendEffect);
for (const [id, delta] of [['prev', -1], ['next', 1]]) action(id, () => {
  const list = $('effect');
  list.selectedIndex = (list.selectedIndex + delta + list.length) % list.length;
  return sendEffect();
});
action('send-speed', () => send(speed(number($('speed'))), $('repeat').checked));
action('clear-log', () => $('log').replaceChildren());
$('experimental').addEventListener('change', () => {
  $('raw-controls').disabled = !$('experimental').checked;
  $('unlock').checked = false;
});
action('send-raw', () => {
  if (!$('experimental').checked) throw new Error('Confirm experimental sending first');
  const unlocked = $('unlock').checked;
  $('unlock').checked = false;
  return send(experimentalFrame($('raw').value, unlocked));
});

function readStorage(key) {
  try {
    const value = JSON.parse(localStorage.getItem(`deleluz.${key}`) ?? '[]');
    if (!Array.isArray(value)) throw new Error('Expected a list');
    return value;
  } catch (error) { log(`Cannot load ${key}: ${error.message}`); return []; }
}
const store = (key, value) => localStorage.setItem(`deleluz.${key}`, JSON.stringify(value));
let observations = readStorage('observations');
function renderNotes() {
  $('observations').replaceChildren(...observations.slice().reverse().map(item => {
    const row = document.createElement('li');
    row.textContent = `${item.result} · ${item.frame}${item.simulated ? ' (simulation)' : ''} — ${item.note}`;
    return row;
  }));
}
renderNotes();
function saveObservation(target, result, note = '') {
  const updated = [...observations, { ...target, at: new Date().toISOString(), result, note }];
  store('observations', updated);
  observations = updated;
  renderNotes();
}
action('save-note', () => {
  if (!lastSent) throw new Error('Send a frame before recording an observation');
  saveObservation(lastSent, $('result').value, $('note').value.trim());
  $('note').value = '';
});
function download(name, type, text) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
action('json', () => download('led-lab-observations.json', 'application/json', JSON.stringify(observations, null, 2)));
action('markdown', () => download('led-lab-observations.md', 'text/markdown', '# LED lab observations\n\n' + observations.map(item =>
  `- ${item.at} — **${item.result}**${item.simulated ? ' (simulation)' : ''} — \`${item.frame}\`${item.effect === null ? '' : ` (effect ${item.effect})`}\n` +
  (item.sentAt ? `  - Send timestamp: ${item.sentAt} (page clock: ${item.sendMs.toFixed(1)} ms)\n` : '') +
  (item.rate ? `  - Run ${item.rate.runId}, target ${item.rate.intervalMs} ms${item.rate.index ? `, frame #${item.rate.index}, gap ${item.rate.gapMs ?? 'n/a'} ms` : ''}\n` : '') +
  (item.samples ?? []).map(sample => `  - #${sample.rate.index} ${sample.sentAt} (page clock: ${sample.sendMs.toFixed(1)} ms; gap ${sample.rate.gapMs ?? 'n/a'} ms) \`${sample.frame}\`${sample.error ? ' (write failed)' : ''}\n`).join('') +
  item.note.split(/\r?\n/).map(line => `  > ${line.replace(/[\\`*_{}\[\]<>]/g, '\\$&')}`).join('\n')).join('\n\n')));

// Each stage blinks its own color against black, with a black pause between stages, so stages are told apart on the strip.
const rateStages = [['red', [255, 0, 0]], ['green', [0, 255, 0]], ['blue', [0, 0, 255]], ['white', [255, 255, 255]], ['yellow', [255, 255, 0]], ['magenta', [255, 0, 255]]];
const rateBlack = color(0, 0, 0);
const ratePauseMs = 2000;
const RATE_FRAMES = 60; // about 3x longer per stage so the eye can judge it
let rateCount = 0, rateSummary;
action('start-rate', async () => {
  if (playback || rateRun || pending) throw new Error('Stop playback and wait for pending writes first');
  const intervals = $('rate-intervals').value.split(',').map(value => Number(value.trim()));
  if (intervals.length > 6 || new Set(intervals).size !== intervals.length ||
      intervals.some(ms => !Number.isInteger(ms) || ms < 10 || ms > 5000)) {
    throw new Error('Enter up to six distinct comma-separated intervals (10–5000 ms)');
  }
  if (!simulate.checked && !writer) throw new Error('Connect or enable simulation first');
  const run = { id: `${pageId}-rate-${++rateCount}`, controller: new AbortController(), simulated: simulate.checked };
  rateRun = run;
  rateSummary = undefined;
  const { signal } = run.controller;
  const choices = $('rate-skipped');
  choices.replaceChildren();
  $('mark-skipped').disabled = $('start-rate').disabled = true;
  $('stop-rate').disabled = false;
  let outcome = 'complete';
  try {
    for (const [stage, interval] of intervals.entries()) {
      const [stageName, rgb] = rateStages[stage];
      $('rate-status').textContent = `Stage ${stage + 1}: ${stageName} blinking every ${interval} ms…`;
      log(`Rate stage ${stage + 1}: ${stageName} / black at ${interval} ms`);
      const batch = { run, interval, samples: [] };
      try {
        const frames = [color(...rgb), rateBlack];
        for (let i = 0; i < RATE_FRAMES; i++) await send(frames[i % 2], false, signal, batch);
        await new Promise(resolve => setTimeout(resolve, ratePauseMs));
      } finally {
        if (batch.samples.length) {
          saveObservation({ frame: `${stageName} / black`, effect: null, simulated: run.simulated,
            rate: { runId: run.id, intervalMs: interval }, samples: batch.samples }, 'rate samples',
          `${batch.samples.length}/${RATE_FRAMES} send attempts`);
          if (batch.samples.some(sample => !sample.error)) choices.add(new Option(`${interval} ms`, interval));
        }
      }
    }
  } catch (error) {
    outcome = signal.aborted ? 'stopped' : 'failed';
    if (!signal.aborted) throw error;
  } finally {
    // Do not carry a sub-throttle gap or long test delay into ordinary sends.
    nextSend = performance.now() + SEND_INTERVAL;
    rateRun = undefined;
    rateSummary = run;
    $('start-rate').disabled = false;
    $('stop-rate').disabled = true;
    $('mark-skipped').disabled = !choices.length;
    $('rate-status').textContent = `Rate test ${outcome}. ${choices.length ? 'Select the first interval where you saw skipped changes, if any.' : 'No successful sends to mark.'}`;
  }
});
action('stop-rate', () => rateRun?.controller.abort());
action('mark-skipped', () => {
  const intervalMs = Number($('rate-skipped').value);
  saveObservation({ frame: 'Rate stages (color / black)', effect: null, simulated: rateSummary.simulated,
    rate: { runId: rateSummary.id, intervalMs } }, 'first skip', 'First interval with visually skipped changes');
  $('rate-status').textContent = `First skip saved: ${intervalMs} ms.`;
  $('mark-skipped').disabled = true;
});

let playback;
let modes = readStorage('modes');
function renderModes() {
  $('modes').replaceChildren(...modes.map((mode, i) => new Option(mode.name, i)));
  $('load-mode').disabled = !modes.length;
}
function addStep({ shade = '#ff0000', level = 50, duration = 600, fade = false } = {}) {
  const row = document.createElement('fieldset');
  row.className = 'step line';
  row.innerHTML = `<legend>Step</legend><label>Color <input type="color" data-shade></label>
    <label>Brightness (%) <input type="number" min="0" max="100" required data-level></label>
    <label>Duration (ms) <input type="number" min="150" max="600000" required data-duration></label>
    <label><input type="checkbox" data-fade> Fade to next</label><button type="button">Remove step</button>`;
  row.querySelector('[data-shade]').value = shade;
  row.querySelector('[data-level]').value = level;
  row.querySelector('[data-duration]').value = duration;
  row.querySelector('[data-fade]').checked = fade;
  row.querySelector('button').onclick = () => row.remove();
  $('steps').append(row);
}
function readSteps() {
  const steps = Array.from($('steps').children, row => ({
    shade: row.querySelector('[data-shade]').value,
    level: number(row.querySelector('[data-level]')),
    duration: number(row.querySelector('[data-duration]')),
    fade: row.querySelector('[data-fade]').checked,
  }));
  if (!steps.length) throw new Error('Add at least one step');
  return steps;
}
function wait(ms, signal) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(signal.reason); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, Math.max(0, ms));
    signal.addEventListener('abort', abort, { once: true });
  });
}
addStep();
renderModes();
action('add-step', () => addStep({ shade: '#0000ff' }));
action('save-mode', () => {
  const name = $('mode-name').value.trim();
  if (!name) throw new Error('Give this mode a name');
  const mode = { name, loop: $('loop').checked, steps: readSteps() };
  const updated = [...modes.filter(item => item.name !== name), mode];
  store('modes', updated);
  modes = updated;
  renderModes();
  $('modes').selectedIndex = modes.length - 1;
});
action('load-mode', () => {
  const mode = modes[$('modes').selectedIndex];
  $('mode-name').value = mode.name;
  $('loop').checked = mode.loop;
  $('steps').replaceChildren();
  mode.steps.forEach(addStep);
});
const presetButtons = PRESETS.map(({ id, name, interval }) => {
  const button = document.createElement('button');
  button.id = `preset-${id}`;
  button.textContent = name;
  button.title = `Default step interval: ${interval} ms`;
  $('presets').append(button);
  action(button.id, () => {
    const input = $('preset-interval');
    input.placeholder = interval;
    const plan = presetFrames(id, input.value === '' ? interval : number(input));
    return playMode(async signal => {
      for (const bytes of plan.setup) await send(bytes, false, signal);
      do {
        for (const step of plan.steps) {
          await send(step.bytes, false, signal);
          await wait(step.interval, signal);
        }
      } while (true);
    }, name);
  });
  return button;
});
async function playMode(run, name) {
  if (rateRun || playback) throw new Error('Stop the active playback or rate test first');
  playback = new AbortController();
  const { signal } = playback;
  for (const button of [$('play'), ...presetButtons]) button.disabled = true;
  $('stop').disabled = false;
  $('mode-status').textContent = `Playing: ${name}`;
  try {
    await run(signal);
    log('Mode complete');
  } catch (error) {
    if (!signal.aborted) throw error;
    log('Mode stopped');
  } finally {
    playback = undefined;
    for (const button of [$('play'), ...presetButtons]) button.disabled = false;
    $('stop').disabled = true;
    $('mode-status').textContent = '';
  }
}
action('play', () => {
  const steps = readSteps();
  const loop = $('loop').checked;
  return playMode(async signal => {
    do {
      for (const [i, step] of steps.entries()) {
        const next = steps[i + 1] ?? (loop ? steps[0] : null);
        await send(color(...rgb(step.shade)), false, signal);
        await send(brightness(step.level), false, signal);
        const start = performance.now();
        if (step.fade && next) {
          for (let elapsed = SEND_INTERVAL; elapsed < step.duration; elapsed += SEND_INTERVAL) {
            await wait(start + elapsed - performance.now(), signal);
            const actual = performance.now() - start;
            if (actual >= step.duration) break;
            await send(color(...mix(step.shade, next.shade, actual / step.duration)), false, signal);
          }
        }
        await wait(start + step.duration - performance.now(), signal);
      }
    } while (loop);
  }, $('mode-name').value);
});
action('stop', () => playback?.abort());

let pixels = [];
function setPixel(index, value) {
  pixels[index] = value;
  const button = $('pixels').children[index];
  button.style.backgroundColor = value;
  button.setAttribute('aria-label', `LED ${index + 1}: ${value}`);
  button.title = `LED ${index + 1}: ${value}`;
}
function resize() {
  const count = number($('count'));
  pixels = Array.from({ length: count }, (_, i) => pixels[i] ?? '#263241');
  $('first').max = $('last').max = count;
  for (const id of ['first', 'last']) if ($(id).valueAsNumber > count) $(id).value = count;
  $('pixels').replaceChildren(...pixels.map((_, i) => {
    const button = document.createElement('button');
    button.onclick = () => setPixel(i, $('paint').value);
    return button;
  }));
  pixels.forEach((value, i) => setPixel(i, value));
}
function paintRange(gradient) {
  const first = number($('first')) - 1, last = number($('last')) - 1;
  if (first > last) throw new Error('Range start must not exceed range end');
  for (let i = first; i <= last; i++) {
    setPixel(i, gradient ? colorHex(mix($('paint').value, $('gradient-end').value, (i - first) / (last - first || 1))) : $('paint').value);
  }
}
resize();
action('resize', resize);
action('paint-range', () => paintRange(false));
action('gradient', () => paintRange(true));
action('fill', () => pixels.forEach((_, i) => setPixel(i, $('paint').value)));
