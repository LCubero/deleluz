import 'dart:convert';

import 'package:deleluz/link.dart';
import 'package:deleluz/model/effects.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/model/timer.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements LocalStore {
  final values = <String, String>{};
  bool denied = false;
  @override
  String? read(String key) => denied ? throw StateError('denied') : values[key];
  @override
  Future<bool> write(String key, String? value) async {
    if (denied) throw StateError('denied');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    return true;
  }
}

void main() {
  late MemoryStore storage;
  late Models models;
  setUp(() {
    storage = MemoryStore();
    models = Models(storage, presetIds: {'warm', 'rasta'});
  });

  test('unreadable storage uses defaults and writes fail without throwing', () async {
    storage.denied = true;
    expect(models.loadState(), defaultState);
    expect(models.loadSequences(), isEmpty);
    expect(models.loadShortcuts(), defaultShortcuts);
    expect(models.loadPalette(), defaultPalette);
    expect(models.loadStripSettings().pixels, 150);
    expect(models.loadLanguage(), 'es');
    expect(models.loadRemembered(), isNull);
    expect(await models.saveState(defaultState), isFalse);
    expect(await models.saveSequences([]), isFalse);
    expect(await models.saveShortcuts([]), isFalse);
  });

  test('snapshot accepts individual valid fields, strips unknowns and rejects bad writes', () async {
    storage.values[Models.stateKey] = jsonEncode({
      'on': true, 'bri': 101, 'speed': 0, 'micSens': 100, 'fx': 'AUTO',
      'rgb': [0, 255, 0], 'label': ['green', {'value': 42}],
      'mode': {'voice': 4}, 'extra': 123,
    });
    final state = models.loadState();
    expect(state, {...defaultState, 'on': true, 'speed': 0, 'micSens': 100,
      'fx': 'AUTO', 'rgb': [0, 255, 0], 'label': ['green', {'value': 42}],
      'mode': {'voice': 4}});
    expect(await models.saveState(state), isTrue);
    final before = Map.of(storage.values);
    for (final invalid in [-1, 101, 1.5, '50']) {
      expect(await models.saveState({...state, 'micSens': invalid}), isFalse);
    }
    expect(storage.values, before);
    expect(models.loadState(), state);
  });

  test('snapshot restores modes and stale sequences fall back to solid', () async {
    final scenes = createSequence([]);
    await models.saveSequences(scenes);
    final state = {...defaultState, 'scene': 'sequence:1', 'mode': {'colors': [[0, 1, 255]], 'interval': 150}};
    expect(await models.saveState(state), isTrue);
    expect(models.loadState(), state);
    await models.saveSequences([]);
    expect(models.loadState(), {...defaultState, ...solidSelection([255, 200, 128])});
    for (final mode in [{'preset': 'rasta', 'interval': 50}, {'effect': 210}, {'effect': 'AUTO'}, null]) {
      expect(await models.saveState({...defaultState, 'mode': mode}), isTrue);
      expect(models.loadState()['mode'], mode);
    }
  });

  const red = {'kind': 'color', 'rgb': [255, 0, 0]};
  const scene = {'kind': 'scene', 'preset': 'rasta'};
  const sequence = {'kind': 'sequence', 'id': '1'};
  test('shortcut defaults, malformed values, and intentional empty list', () async {
    expect(models.loadShortcuts(), defaultShortcuts);
    for (final raw in ['{', '{}', 'null']) {
      storage.values[Models.shortcutsKey] = raw;
      expect(models.loadShortcuts(), defaultShortcuts);
    }
    expect(await models.saveShortcuts([]), isTrue);
    expect(models.loadShortcuts(), isEmpty);
  });

  test('shortcut loading filters invalid items, caps at six and checks scene references', () async {
    await models.saveSequences(createSequence([]));
    storage.values[Models.shortcutsKey] = jsonEncode([
      {'kind': 'sequence', 'id': 1}, {'kind': 'color', 'rgb': [256, 0, 0]},
      {'kind': 'scene', 'preset': 'unknown'}, scene, sequence, ...List.filled(9, red),
    ]);
    expect(models.loadShortcuts(), [scene, sequence, ...List.filled(4, red)]);
    expect(await models.saveShortcuts([red, sequence]), isTrue);
    final before = Map.of(storage.values);
    expect(await models.saveShortcuts(List.filled(7, red)), isFalse);
    expect(await models.saveShortcuts([{'kind': 'sequence', 'id': '2'}]), isFalse);
    expect(storage.values, before);
    await models.saveSequences([]);
    expect(models.loadShortcuts(), [red]);
    expect(models.filterShortcuts([red, sequence]), [red]);
  });

  test('shortcut operations reorder, replace, remove and enforce capacity', () {
    final full = List.filled(6, red);
    expect(addShortcut(full, scene), full);
    expect(addShortcut([red], scene), [red, scene]);
    expect(replaceShortcut([red, red], 1, scene), [red, scene]);
    expect(removeShortcut([red, scene], 0), [scene]);
    expect(moveItem([red, scene], 0, 1), [scene, red]);
    expect(moveItem([red, scene], 0, 2), [red, scene]);
    expect([1, 2, 3, 4, 5, 6].map(gridColumns), [1, 2, 3, 2, 3, 3]);
  });

  test('sequence speed is linear, reversible and clamped', () {
    expect([0, 50, 100].map(intervalFromSpeed), [2000, 1075, 150]);
    expect(intervalFromSpeed(-1), 2000);
    expect(speedPercent(149), 100);
    for (var p = 0; p <= 100; p++) {
      expect(speedPercent(intervalFromSpeed(p)), p);
    }
  });

  test('creates independent sequence defaults and first free ID/name up to twelve', () {
    final first = createSequence([]);
    expect(first.single, {'id': '1', 'name': 'Secuencia 1', 'colors': [[0, 255, 0], [255, 200, 0], [255, 0, 0]], 'interval': 500, 'bri': 80});
    final second = createSequence(first);
    expect(second.last['name'], 'Secuencia 2');
    expect(identical(first.first['colors'], second.last['colors']), isFalse);
    expect(createSequence(removeSequence(second, '1')).last['id'], '1');
    expect(createSequence([], nameFor: (n) => 'Sequence $n').single['name'], 'Sequence 1');
    var list = second;
    for (var i = 0; i < 12; i++) {
      list = createSequence(list);
    }
    expect(list, hasLength(12));
  });

  test('scene names are trimmed, 1–24 characters and unique ignoring case', () async {
    final list = createSequence(createSequence([]));
    expect(await models.saveSequences(list), isTrue);
    final before = Map.of(storage.values);
    for (final name in ['  ', 'x' * 25, ' sECUENCIA 2 ']) {
      expect(renameSequence(list, '1', name), same(list));
      expect(await models.saveSequences([{...list.first, 'name': name}, list.last]), isFalse);
    }
    expect(storage.values, before);
    expect(renameSequence(list, 'missing', 'Valid'), same(list));
    expect(renameSequence(list, '1', ' SECUENCIA 1 ').first['name'], 'SECUENCIA 1');
    expect(renameSequence(list, '1', ' ${'x' * 24} ').first['name'], 'x' * 24);
    expect(createSequence(list, nameFor: (_) => ' '), same(list));
    expect(createSequence(list, nameFor: (_) => 'x' * 25), same(list));
    expect(createSequence(list, nameFor: (n) => ' secuencia $n ').last['name'], 'secuencia 3');
  });

  test('sequence storage rejects invalid entries and caps the salvaged list', () async {
    final scene = createSequence([]).single;
    final invalid = [
      {...scene, 'id': ''}, {...scene, 'colors': []}, {...scene, 'colors': List.filled(9, [0, 0, 0])},
      {...scene, 'colors': [[0, 0, 256]]}, {...scene, 'interval': 149}, {...scene, 'interval': 2001},
      {...scene, 'bri': 0}, {...scene, 'bri': 101}, {...scene, 'bri': 1.5},
    ];
    storage.values[Models.sequencesKey] = jsonEncode([null, ...invalid, scene, scene,
      ...List.generate(13, (i) => {...scene, 'id': 'a$i', 'name': 'Escena $i'})]);
    expect(models.loadSequences(), hasLength(12));
    expect(models.loadSequences().first, scene);
    final before = Map.of(storage.values);
    for (final item in invalid) {
      expect(await models.saveSequences([item]), isFalse);
    }
    expect(storage.values, before);
    final updated = updateSequence([scene], '1', {'interval': 2000, 'bri': 1});
    expect(await models.saveSequences(updated), isTrue);
    expect(models.loadSequences(), updated);
    expect(updateSequence(updated, '1', {'bri': 100, 'interval': 150}).first['bri'], 100);
  });

  test('scene color edits are immutable and enforce indices and 1–8 colors', () {
    final scene = createSequence([]).single;
    final rgb = [0, 42, 255];
    final changed = setColor(scene, 1, rgb);
    rgb[0] = 123;
    expect((changed['colors'] as List)[1], [0, 42, 255]);
    expect(setColor(scene, -1, rgb), same(scene));
    expect(setColor(scene, 0, [0, 0, -1]), same(scene));
    var next = changed;
    for (var i = 0; i < 9; i++) {
      next = addColor(next);
    }
    expect(next['colors'], hasLength(8));
    for (var i = 0; i < 9; i++) {
      next = removeColor(next, 0);
    }
    expect(next['colors'], hasLength(1));
    expect(removeColor(next, 0), same(next));
    expect(moveColor(moveColor(scene, 0, 2), 2, 0), scene);
    expect(moveColor(scene, 0, 3), same(scene));
    expect(moveColor(scene, 1, 1), same(scene));
  });

  test('palette defaults, normalization, migration and invalid fallback', () {
    expect(models.loadPalette().map(colorName), ['green', 'yellow', 'red']);
    expect(colorName('#FFC880'), 'warmWhite');
    expect(colorName('#123456'), 'solid');
    storage.values[Models.legacyPaletteKey] = '["#FF0000", "#010101"]';
    expect(models.loadPalette(), [...defaultPalette, '#010101']);
    storage.values[Models.paletteKey] = '["#ABCDEF"]';
    expect(models.loadPalette(), ['#abcdef']);
    for (final raw in ['{', 'null', '{}', '[]', '["bad"]', '["#AA0000", "#aa0000"]']) {
      storage.values[Models.paletteKey] = raw;
      expect(models.loadPalette(), defaultPalette);
    }
  });

  test('palette adds, replaces, removes and moves; rejects without writing', () async {
    var colors = defaultPalette;
    for (var i = 0; i < 13; i++) {
      colors = addPaletteColor(colors, '#${i.toRadixString(16).padLeft(6, '0')}');
    }
    expect(colors, hasLength(15));
    expect(addPaletteColor(colors, '#AABBCC'), same(colors));
    expect(addPaletteColor(defaultPalette, '#FF0000'), same(defaultPalette));
    expect(replacePaletteColor(defaultPalette, 4, '#AABBCC'), same(defaultPalette));
    expect(replacePaletteColor(defaultPalette, 0, 'red'), same(defaultPalette));
    expect(replacePaletteColor(defaultPalette, 0, '#FF0000'), same(defaultPalette));
    expect(removeItem(['#ff0000'], 0), isEmpty);
    final edited = moveItem(replacePaletteColor(defaultPalette, 0, '#AABBCC'), 0, 2);
    expect(edited, ['#ffc800', '#ff0000', '#aabbcc']);
    expect(await models.savePalette(edited), isTrue);
    final before = Map.of(storage.values);
    expect(await models.savePalette([...colors, '#aaaaaa']), isFalse);
    expect(await models.savePalette(['red']), isFalse);
    expect(await models.savePalette(['#ff0000', '#FF0000']), isFalse);
    expect(storage.values, before);
    expect(models.loadPalette(), edited);
  });

  test('strip counts accept only 1–1024 whole LEDs and round density times length', () {
    expect(validPixels(1), 1);
    expect(validPixels(1024), 1024);
    for (final value in [0, 1025, 1.5, '30', double.nan, double.infinity]) {
      expect(validPixels(value), isNull);
    }
    expect(stripPixels(30, 2.55), 77);
    expect(stripPixels(60, 20), isNull);
    expect(stripPixels(0, 2), isNull);
    expect(stripPixels(60, double.nan), isNull);
  });

  test('strip settings persist valid orders and reject invalid input without writing', () async {
    expect(models.loadStripSettings().order, 'GRB');
    expect(await models.saveStripSettings(order: 'RGB', pixels: 1024), isTrue);
    expect(models.loadStripSettings().pixels, 1024);
    final before = Map.of(storage.values);
    expect(await models.saveStripSettings(order: 'BAD', pixels: 150), isFalse);
    expect(await models.saveStripSettings(order: 'GRB', pixels: 1025), isFalse);
    expect(await models.saveStripSettings(order: 'GRB', density: 0, meters: 1), isFalse);
    expect(storage.values, before);
    expect(await models.saveStripSettings(order: 'GRB', density: 30, meters: 2), isTrue);
    expect(models.loadStripSettings().pixels, 60);
    expect(models.loadStripSettings().meters, 2);
    storage.values[Models.stripSettingsKey] = '{"order":"BAD","pixels":1}';
    expect(models.loadStripSettings().pixels, 150);
  });

  test('language defaults to Spanish, persists English and rejects other codes', () async {
    expect(models.loadLanguage(), 'es');
    expect(await models.saveLanguage('en'), isTrue);
    expect(models.loadLanguage(), 'en');
    expect(await models.saveLanguage('fr'), isFalse);
    expect(models.loadLanguage(), 'en');
    storage.values[Models.languageKey] = 'fr';
    expect(models.loadLanguage(), 'es');
  });

  test('remembered strip round trips id/name, can be forgotten, and rejects invalid records', () async {
    expect(await models.saveRemembered(const Strip('demo-id', 'LEDDMX Demo')), isTrue);
    expect(models.loadRemembered()?.id, 'demo-id');
    expect(models.loadRemembered()?.name, 'LEDDMX Demo');
    final before = Map.of(storage.values);
    expect(await models.saveRemembered(const Strip('', 'LEDDMX Demo')), isFalse);
    expect(storage.values, before);
    expect(await models.saveRemembered(null), isTrue);
    expect(models.loadRemembered(), isNull);
    storage.values[Models.rememberedKey] = '{"id":42,"name":"Demo"}';
    expect(models.loadRemembered(), isNull);
  });

  test('remembered strips migrate once and persist aliases, recency and forgetting', () async {
    await models.saveRemembered(const Strip('old', 'LEDDMX Legacy'));
    final migrated = models.loadRememberedStrips();
    expect(migrated.single.id, 'old');
    expect(storage.values[Models.rememberedStripsKey], contains('LEDDMX Legacy'));
    final renamed = migrated.single.renamed('  ${'a' * 30}   ');
    expect(renamed.alias, 'a' * 24);
    expect(renamed.renamed('   ').alias, isNull);
    final added = RememberedStrip.remember([renamed], const Strip('new', 'LEDDMX New'));
    expect(added.map((strip) => strip.id), ['new', 'old']);
    final recent = RememberedStrip.remember(added, const Strip('old', 'LEDDMX Updated'));
    await models.saveRememberedStrips(recent);
    final restored = models.loadRememberedStrips();
    expect(restored.map((strip) => strip.id), ['old', 'new']);
    expect(restored.first.alias, renamed.alias);
    expect(restored.first.name, 'LEDDMX Updated');
    await models.saveRememberedStrips([]);
    expect(models.loadRememberedStrips(), isEmpty);
  });

  test('invalid saved lists fall back safely without resurrecting legacy strips', () async {
    await models.saveRemembered(const Strip('old', 'LEDDMX Legacy'));
    for (final invalid in ['{broken', 'null', '{}']) {
      storage.values[Models.rememberedStripsKey] = invalid;
      expect(models.loadRememberedStrips(), isEmpty);
    }
    storage.values[Models.rememberedStripsKey] = '[42,{"id":"valid","name":"Demo","alias":42},'
      '{"id":"valid","name":"Duplicate"},{"id":" ","name":"Invalid"}]';
    final valid = models.loadRememberedStrips().single;
    expect(valid.label, 'Demo');
    expect(valid.alias, isNull);
  });

  test('custom timer accepts whole fields from one second to 720 minutes only', () {
    expect(parseTimerDuration('', ' 01 '), 1);
    expect(parseTimerDuration('720', ''), 43200);
    expect(parseTimerDuration('719', '59'), 43199);
    for (final (minutes, seconds) in [('', ''), ('720', '1'), ('721', '0'), ('1', '60'), ('1.5', '0'), ('-1', '2'), ('0x1', '0')]) {
      expect(parseTimerDuration(minutes, seconds), isNull);
    }
  });

  test('remaining time rounds up and fade steps every five seconds', () {
    expect(formatRemaining(61.1), '01:02');
    expect(formatRemaining(43200), '720:00');
    expect(formatRemaining(-1), '00:00');
    expect(fadeBrightness(60, 56, true), isNull);
    expect(fadeBrightness(60, 55, true), 55);
    expect(fadeBrightness(60, 51, true), 55);
    expect(fadeBrightness(60, 50, true), 50);
    expect(fadeBrightness(0, 1, true), 1);
    expect(fadeBrightness(60, 0, true), isNull);
    expect(fadeBrightness(60, 50, false), isNull);
  });

  test('effect names follow all 210 controller IDs and reject out of range IDs', () {
    expect(effectNames, hasLength(210));
    expect(effectNames.every((name) => name.isNotEmpty && name.trim() == name), isTrue);
    expect(effectName(1), 'Forward Dreaming');
    expect(effectName(3), 'Forward 7 Colors');
    expect(effectName(80), 'Strobe White');
    expect(effectName(95), 'Forward Run 7 Colors');
    expect(effectName(210), 'Close Curtain Swab CN/VT');
    for (final id in [0, 211, 255, 1.5, 'AUTO']) {
      expect(effectName(id), isNull);
    }
  });
}
