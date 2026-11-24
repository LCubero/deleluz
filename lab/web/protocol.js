// Wire format and capture allowlist: docs/PROTOCOL.md.
function integer(value, min, max, label) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`${label} must be an integer from ${min} to ${max}`);
  }
  return value;
}

const framed = (op, a, b, c, d) => Uint8Array.of(0x7b, 0xff, op, a, b, c, d, 0xff, 0xbf);

export function power(on) {
  if (typeof on !== 'boolean') throw new TypeError('Power requires a boolean');
  return framed(4, Number(on), 255, 255, 255);
}

export function color(r, g, b) {
  return framed(7, integer(r, 0, 255, 'Red'), integer(g, 0, 255, 'Green'), integer(b, 0, 255, 'Blue'), 0);
}

export function brightness(pct) {
  integer(pct, 0, 100, 'Brightness');
  return framed(1, Math.floor(pct * 32 / 100), pct, 0, 255);
}

export function effect(id) {
  return framed(3, id === 'AUTO' || id === 255 ? 255 : integer(id, 1, 210, 'Effect'), 255, 255, 255);
}

export function speed(pct) {
  return framed(2, integer(pct, 1, 100, 'Speed'), 255, 0, 255);
}

export function voiceMode(mode) {
  return framed(0x0b, integer(mode, 1, 4, 'Voice mode'), 0, 255, 255);
}

// Higher value = more sensitive (lab L59).
export function micSensitivity(pct) {
  return framed(0x0c, integer(pct, 0, 100, 'Mic sensitivity'), 0, 255, 255);
}

export const CHIP_ORDERS = Object.freeze(['RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR', 'RGBW', 'RBGW', 'GRBW', 'GBRW', 'BRGW', 'BGRW']);

export function chipConfig(order, pixels) {
  const code = CHIP_ORDERS.indexOf(order) + 1;
  if (!code) throw new RangeError('Unknown chip color order');
  integer(pixels, 1, 1024, 'Pixel count');
  return framed(5, 4, pixels >> 8, pixels & 0xff, code);
}

export const hex = bytes => Array.from(bytes, byte => byte.toString(16).padStart(2, '0').toUpperCase()).join(' ');

function parseBytes(text) {
  const input = typeof text === 'string' ? text.trim() : '';
  if (!/^(?:[\da-f]{2}\s*){8}[\da-f]{2}$/i.test(input)) throw new Error('Enter exactly nine hex bytes');
  return Uint8Array.from(input.match(/[\da-f]{2}/gi), byte => Number.parseInt(byte, 16));
}

export function parseRaw(text) {
  const bytes = parseBytes(text);
  if (bytes[0] !== 0x7b || bytes[8] !== 0xbf) throw new Error('Expected 7B … BF framing');
  return bytes;
}

export function experimentalFrame(text, dedicatedTest = false) {
  const bytes = parseBytes(text);
  const wire = hex(bytes);
  if (wire === '2A 02 A1 23 45 67 F6 39 AF' || wire === '7B FF 05 04 00 96 03 FF BF') {
    if (dedicatedTest !== true) throw new Error('Dedicated reversible test unlock required');
    return bytes;
  }
  const [, , op, a, b, c] = parseRaw(text);
  let expected;
  switch (op) {
    case 1: expected = brightness(b); break;
    case 2: expected = speed(a); break;
    case 3: expected = effect(a); break;
    case 4: if (a === 0 || a === 1) expected = power(a === 1); break;
    case 7: expected = color(a, b, c); break;
  }
  if (!expected || hex(expected) !== wire) throw new Error('Only documented frames are allowed; variants and unknown opcodes are blocked');
  return bytes;
}
