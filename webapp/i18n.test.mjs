import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PRESETS } from '../lab/web/presets.js';
import { dictionaries, loadLanguage, LANGUAGE_KEY, translate } from './i18n.js';

const storage = value => ({ getItem: key => key === LANGUAGE_KEY ? value : null });

test('dictionaries have identical keys and nonempty strings', () => {
  assert.deepEqual(Object.keys(dictionaries.es).sort(), Object.keys(dictionaries.en).sort());
  for (const dictionary of Object.values(dictionaries)) {
    for (const [key, value] of Object.entries(dictionary)) assert.ok(value.trim(), key);
  }
});

test('language defaults to Spanish and honors stored English', () => {
  assert.equal(loadLanguage(storage(null)), 'es');
  assert.equal(loadLanguage(storage('en')), 'en');
  assert.equal(loadLanguage(storage('fr')), 'es');
  assert.equal(loadLanguage({ getItem() { throw new Error(); } }), 'es');
});

test('translation interpolates variables', () => {
  assert.equal(translate('en', 'effectNumber', { id: 12 }), 'Effect 12');
  assert.equal(translate('es', 'effectNumber', { id: 12 }), 'Efecto 12');
  assert.equal(translate('es', 'onLabel', { label: 'Mi escena {id}' }), 'Encendido · Mi escena {id}');
  assert.equal(translate('es', 'sequenceName', { number: 2 }), 'Secuencia 2');
  assert.equal(translate('en', 'sequenceName', { number: 2 }), 'Sequence 2');
  assert.equal(translate('en', 'sequenceFrame', { number: 3, hex: '#00FF00' }), 'Square 3: #00FF00');
});

test('custom shortcut names are literal text, not dictionary keys', () => {
  assert.equal(translate('en', '<img src=x> {id}'), '<img src=x> {id}');
  assert.equal(translate('es', '__proto__'), '__proto__');
});

test('all HTML translation attributes have dictionary entries', () => {
  const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
  const keys = [...html.matchAll(/\bdata-i18n(?:-[\w-]+)?="([^"]+)"/g)].map(match => match[1]);
  assert.ok(keys.length);
  for (const key of keys) assert.ok(Object.hasOwn(dictionaries.es, key), key);
});

test('all included page scenes have names in both languages', () => {
  for (const { id, name } of PRESETS) {
    assert.equal(translate('en', id), name);
    assert.ok(translate('es', id).trim(), id);
  }
});
