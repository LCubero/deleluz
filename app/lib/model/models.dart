import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

import '../link.dart';
import '../protocol.dart';

/// String storage keeps JSON validation independent of the platform plugin.
abstract interface class LocalStore {
  String? read(String key);
  Future<bool> write(String key, String? value);
}

class PreferencesStore implements LocalStore {
  PreferencesStore(this.preferences);

  final SharedPreferences preferences;

  @override
  String? read(String key) => preferences.getString(key);

  @override
  Future<bool> write(String key, String? value) => value == null
      ? preferences.remove(key)
      : preferences.setString(key, value);
}

typedef Fields = Map<String, Object?>;
typedef StripSettings = ({String order, int pixels, num? density, num? meters});

const defaultState = <String, Object?>{
  'on': false,
  'bri': 80,
  'rgb': [255, 200, 128],
  'label': ['warmWhite'],
  'scene': 'warm',
  'fx': 1,
  'speed': 50,
  'micSens': 50,
};
const maxShortcuts = 6;
const defaultShortcuts = <Fields>[
  {'kind': 'color', 'name': 'warmWhite', 'rgb': [255, 200, 128]},
  {'kind': 'color', 'name': 'coolWhite', 'rgb': [255, 255, 255]},
];
const maxSequences = 12;
const maxColors = 8;
const maxSequenceName = 24;
const paletteLimit = 15;
const defaultPalette = ['#00ff00', '#ffc800', '#ff0000'];
const defaultStripSettings = (order: 'GRB', pixels: 150, density: null, meters: null);

int? _integer(Object? value, int min, int max) =>
    value is num && value >= min && value <= max && value == value.truncate()
    ? value.toInt()
    : null;

List<int>? _rgb(Object? value) {
  if (value is! List || value.length != 3) return null;
  final bytes = value.map((v) => _integer(v, 0, 255)).toList();
  return bytes.contains(null) ? null : List.unmodifiable(bytes.cast<int>());
}

List<List<int>>? _colors(Object? value) {
  if (value is! List || value.isEmpty || value.length > maxColors) return null;
  final colors = value.map(_rgb).toList();
  return colors.contains(null)
      ? null
      : List.unmodifiable(colors.cast<List<int>>());
}

bool _text(Object? value) => value is String && value.trim().isNotEmpty;
Object? _effect(Object? value) => value == 'AUTO' ? value : _integer(value, 1, 210);

String rgbHex(List<int> rgb) =>
    '#${rgb.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

Fields solidSelection(List<int> rgb) => {
  'scene': null,
  'mode': null,
  'label': ['colorHex', {'hex': rgbHex(rgb)}],
};

bool _validLabel(Object? label) => label is String ||
    (label is List && label.isNotEmpty && label.first is String &&
        (label.length == 1 || (label.length == 2 && label[1] is Fields &&
            (label[1] as Fields).values.every((v) => v is String || (v is num && v.isFinite)))));

const maxStripAlias = 24;

class RememberedStrip extends Strip {
  const RememberedStrip(super.id, super.name, {this.alias});

  final String? alias;
  String get label => alias ?? name;

  static String? normalizeAlias(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed.characters.take(maxStripAlias).toString().trimRight();
  }

  static List<RememberedStrip> remember(List<RememberedStrip> strips, Strip strip) => [
    RememberedStrip(strip.id, strip.name,
      alias: strips.where((item) => item.id == strip.id).firstOrNull?.alias),
    ...strips.where((item) => item.id != strip.id),
  ];

  RememberedStrip renamed(String value) => RememberedStrip(id, name, alias: normalizeAlias(value));
}

/// Local snapshots represent the last selection, not live controller state.
/// Callers own in-memory edits and decide whether a failed save is retryable.
class Models {
  Models(this.storage, {required Set<String> presetIds})
    : presetIds = Set.unmodifiable(presetIds);

  final LocalStore storage;
  final Set<String> presetIds;

  static const stateKey = 'deleluz.app.state';
  static const shortcutsKey = 'deleluz.app.shortcuts';
  static const sequencesKey = 'deleluz.app.sequences';
  static const effectFavoritesKey = 'deleluz.app.effectFavorites';
  static const paletteKey = 'deleluz.app.palette';
  static const legacyPaletteKey = 'deleluz.app.customColors';
  static const stripSettingsKey = 'deleluz.app.stripSettings';
  static const _stripSettingsMigratedKey = 'deleluz.app.stripSettingsMigrated';
  static String deviceSetupKey(String id) => 'deleluz.app.deviceSetup.$id';
  static const languageKey = 'deleluz.app.language';
  static const rememberedKey = 'deleluz.app.rememberedStrip';
  static const rememberedStripsKey = 'deleluz.app.rememberedStrips';
  static const stripsExpandedKey = 'deleluz.app.stripsExpanded';

  Object? _readJson(String key) {
    try {
      final raw = storage.read(key);
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _write(String key, String? value) async {
    try {
      return await storage.write(key, value);
    } catch (_) {
      return false;
    }
  }

  Set<String> _sequenceIds() => loadSequences().map((s) => s['id'] as String).toSet();

  Fields _stateFields(Fields saved, {required bool recover}) {
    final accepted = <String, Object?>{};
    if (saved['on'] is bool) accepted['on'] = saved['on'];
    for (final key in ['bri', 'speed', 'micSens']) {
      final value = _integer(saved[key], 0, 100);
      if (value != null) accepted[key] = value;
    }
    final fx = _effect(saved['fx']);
    final rgb = _rgb(saved['rgb']);
    if (fx != null) accepted['fx'] = fx;
    if (rgb != null) accepted['rgb'] = rgb;
    if (_validLabel(saved['label'])) accepted['label'] = saved['label'];
    final scene = saved['scene'];
    if (scene is String || (scene == null && saved.containsKey('scene'))) {
      accepted['scene'] = scene;
    }
    final mode = saved['mode'];
    if (scene is String && scene.startsWith('sequence:')) {
      final steps = mode is Fields ? sceneSteps(mode) : const <Fields>[];
      if (steps.isNotEmpty && _sequenceIds().contains(scene.substring(9))) {
        accepted['mode'] = mode is Fields && mode.containsKey('steps')
            ? {'steps': steps}
            : {'colors': _colors((mode as Fields)['colors']), 'interval': mode['interval']};
      } else if (recover) {
        accepted.addAll(solidSelection(rgb ?? defaultState['rgb'] as List<int>));
      } else {
        accepted.remove('scene');
      }
    } else if (mode is Fields) {
      final preset = mode['preset'];
      final interval = _integer(mode['interval'], 50, 2000);
      final effect = _effect(mode['effect']);
      final voice = _integer(mode['voice'], 1, 4);
      if (preset is String && presetIds.contains(preset) && interval != null) {
        accepted['mode'] = {'preset': preset, 'interval': interval};
      } else if (effect != null) {
        accepted['mode'] = {'effect': effect};
      } else if (voice != null) {
        accepted['mode'] = {'voice': voice};
      }
    } else if (mode == null && saved.containsKey('mode')) {
      accepted['mode'] = null;
    }
    return accepted;
  }

  Fields loadState() {
    final saved = _readJson(stateKey);
    return {...defaultState, if (saved is Fields) ..._stateFields(saved, recover: true)};
  }

  Future<bool> saveState(Fields state) async {
    final accepted = _stateFields(state, recover: false);
    return accepted.length == state.length &&
        await _write(stateKey, jsonEncode(accepted));
  }

  List<Fields> loadSequences() => [
    for (final scene in _sequenceList(_readJson(sequencesKey))) {
      ...scene,
      // Read-only swatch projection for the existing Home shortcut tiles.
      'colors': (scene['steps'] as List<Fields>).map((step) => step['rgb']).whereType<List<int>>().toList(),
    },
  ];

  Future<bool> saveSequences(List<Fields> items) async {
    final accepted = _sequenceList(items);
    return accepted.length == items.length &&
        await _write(sequencesKey, jsonEncode(accepted));
  }

  /// Refilter after deleting scenes before reusing a freed sequence ID.
  List<Fields> filterShortcuts(List items) {
    final ids = _sequenceIds();
    final result = <Fields>[];
    for (final item in items.whereType<Fields>()) {
      switch (item['kind']) {
        case 'color':
          final rgb = _rgb(item['rgb']);
          final name = item['name'];
          if (rgb != null && (!item.containsKey('name') || name is String)) {
            result.add({'kind': 'color', 'rgb': rgb,
              if (name is String && name.isNotEmpty) 'name': name});
          }
        case 'effect':
          final effect = _integer(item['effect'], 1, 210);
          if (effect != null) result.add({'kind': 'effect', 'effect': effect});
        case 'scene':
          if (presetIds.contains(item['preset'])) {
            result.add({'kind': 'scene', 'preset': item['preset']});
          }
        case 'sequence':
          if (ids.contains(item['id'])) {
            result.add({'kind': 'sequence', 'id': item['id']});
          }
      }
      if (result.length == maxShortcuts) break;
    }
    return result;
  }

  List<Fields> loadShortcuts() {
    final saved = _readJson(shortcutsKey);
    return saved is List ? filterShortcuts(saved) : [...defaultShortcuts];
  }

  Future<bool> saveShortcuts(List<Fields> items) async {
    final accepted = filterShortcuts(items);
    return accepted.length == items.length &&
        await _write(shortcutsKey, jsonEncode(accepted));
  }

  static const appAutoDurations = [10, 30, 60, 300];
  static const _appAutoKey = 'deleluz.app.auto';

  ({int seconds, bool favorites}) loadAppAuto() {
    final saved = _readJson(_appAutoKey);
    return switch (saved) {
      {'seconds': final int seconds, 'favorites': final bool favorites}
          when appAutoDurations.contains(seconds) => (seconds: seconds, favorites: favorites),
      _ => (seconds: 30, favorites: false),
    };
  }

  Future<bool> saveAppAuto(int seconds, bool favorites) =>
      _write(_appAutoKey, jsonEncode({'seconds': seconds, 'favorites': favorites}));

  Set<int> loadEffectFavorites() {
    final saved = _readJson(effectFavoritesKey);
    return saved is List
        ? {for (final id in saved.whereType<int>()) if (id >= 1 && id <= 210) id}
        : {};
  }

  Future<bool> saveEffectFavorites(Set<int> ids) async =>
      ids.every((id) => id >= 1 && id <= 210) &&
      await _write(effectFavoritesKey, jsonEncode(ids.toList()));

  List<String> loadPalette() {
    try {
      final raw = storage.read(paletteKey);
      if (raw == null) {
        final legacy = _readJson(legacyPaletteKey);
        if (legacy is List && legacy.every((color) => _hex(color) != null)) {
          return legacy.fold<List<String>>([...defaultPalette], addPaletteColor);
        }
      } else {
        final saved = _palette(jsonDecode(raw));
        if (saved != null && saved.isNotEmpty) return saved;
      }
    } catch (_) {
      // Only a missing key may trigger migration.
    }
    return [...defaultPalette];
  }

  Future<bool> savePalette(List<String> colors) async {
    final accepted = _palette(colors);
    return accepted != null && await _write(paletteKey, jsonEncode(accepted));
  }

  StripSettings loadStripSettings({String? deviceId}) =>
      (deviceId == null ? null : _decodeStripSettings(_readJson(deviceSetupKey(deviceId)))) ??
      _decodeStripSettings(_readJson(stripSettingsKey)) ?? defaultStripSettings;

  /// Keep the legacy key as a fallback, but only snapshot it once.
  Future<bool> migrateStripSettings(String? deviceId) async {
    if (_readJson(_stripSettingsMigratedKey) == true) return true;
    final legacy = _readJson(stripSettingsKey);
    if (_decodeStripSettings(legacy) == null) return true;
    if (deviceId != null && _readJson(deviceSetupKey(deviceId)) == null &&
        !await _write(deviceSetupKey(deviceId), jsonEncode(legacy))) {
      return false;
    }
    return _write(_stripSettingsMigratedKey, 'true');
  }

  Future<bool> removeDeviceSetup(String id) => _write(deviceSetupKey(id), null);

  StripSettings? _decodeStripSettings(Object? saved) {
    if (saved is! Fields || !chipOrders.contains(saved['order'])) return null;
    final density = saved['density'];
    final meters = saved['meters'];
    final computed = stripPixels(density, meters);
    final pixels = validPixels(saved['pixels'] ?? computed);
    final meter = saved['mode'] == 'meter';
    if (pixels == null || (meter && computed != pixels)) return null;
    if (saved['mode'] != null && saved['mode'] != 'total' && !meter) return null;
    return (order: saved['order'] as String, pixels: pixels,
      density: meter ? density as num : null, meters: meter ? meters as num : null);
  }

  Future<bool> saveStripSettings({String? deviceId, required String order,
    Object? pixels, num? density, num? meters}) async {
    if (!chipOrders.contains(order)) return false;
    final meter = density != null || meters != null;
    final count = meter ? stripPixels(density, meters) : validPixels(pixels);
    if (count == null || (meter && pixels != null && validPixels(pixels) != count)) return false;
    return _write(deviceId == null ? stripSettingsKey : deviceSetupKey(deviceId), jsonEncode({
      'order': order, 'mode': meter ? 'meter' : 'total', 'pixels': count,
      if (meter) ...{'density': density, 'meters': meters},
    }));
  }

  String loadLanguage() {
    try {
      return storage.read(languageKey) == 'en' ? 'en' : 'es';
    } catch (_) {
      return 'es';
    }
  }

  Future<bool> saveLanguage(String language) async =>
      (language == 'es' || language == 'en') && await _write(languageKey, language);

  /// List order is most recently connected first. An empty list is authoritative,
  /// so forgetting every strip cannot resurrect a legacy entry.
  List<RememberedStrip> loadRememberedStrips() {
    try {
      final raw = storage.read(rememberedStripsKey);
      if (raw == null) {
        final legacy = loadRemembered();
        if (legacy == null) return [];
        final migrated = RememberedStrip.remember([], legacy);
        unawaited(saveRememberedStrips(migrated));
        return migrated;
      }
      final saved = jsonDecode(raw);
      if (saved is! List) return [];
      final seen = <String>{};
      return [
        for (final row in saved)
          if (row is Fields && _text(row['id']) && _text(row['name']) && seen.add(row['id'] as String))
            RememberedStrip(row['id'] as String, row['name'] as String,
              alias: row['alias'] is String ? RememberedStrip.normalizeAlias(row['alias'] as String) : null),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<bool> saveRememberedStrips(List<RememberedStrip> strips) =>
    _write(rememberedStripsKey, jsonEncode([
      for (final strip in strips) {
        'id': strip.id, 'name': strip.name,
        if (strip.alias != null) 'alias': RememberedStrip.normalizeAlias(strip.alias!),
      },
    ]));

  bool loadStripsExpanded() => _readJson(stripsExpandedKey) != false;
  Future<bool> saveStripsExpanded(bool expanded) => _write(stripsExpandedKey, jsonEncode(expanded));

  Strip? loadRemembered() {
    final saved = _readJson(rememberedKey);
    if (saved is! Fields || !_text(saved['id']) || !_text(saved['name'])) return null;
    return Strip(saved['id'] as String, saved['name'] as String);
  }

  /// Pass the selected Link.strip on a non-null onRemember callback; null forgets it.
  Future<bool> saveRemembered(Strip? strip) async {
    if (strip == null) return _write(rememberedKey, null);
    if (!_text(strip.id) || !_text(strip.name)) return false;
    return _write(rememberedKey, jsonEncode({'id': strip.id, 'name': strip.name}));
  }
}

int? validPixels(Object? pixels) => _integer(pixels, 1, 1024);

int? stripPixels(Object? density, Object? meters) {
  if (density is! num || !density.isFinite || density <= 0 ||
      meters is! num || !meters.isFinite || meters <= 0) {
    return null;
  }
  final total = density.toDouble() * meters;
  return total < 1024.5 ? validPixels(total.round()) : null;
}

bool _index(List list, int index) => index >= 0 && index < list.length;

List<T> _replace<T>(List<T> list, int index, T item) =>
    _index(list, index) ? ([...list]..[index] = item) : list;

List<T> removeItem<T>(List<T> list, int index) =>
    _index(list, index) ? ([...list]..removeAt(index)) : list;

List<T> moveItem<T>(List<T> list, int from, int to) {
  if (from == to || !_index(list, from) || !_index(list, to)) return list;
  final copy = [...list];
  final item = copy.removeAt(from);
  copy.insert(to, item);
  return copy;
}

List<Fields> addShortcut(List<Fields> items, Fields item) =>
    items.length < maxShortcuts ? [...items, item] : items;
List<Fields> replaceShortcut(List<Fields> items, int index, Fields item) =>
    _replace(items, index, item);
List<Fields> removeShortcut(List<Fields> items, int index) => removeItem(items, index);
int gridColumns(int cells) => cells <= 3 ? cells.clamp(1, 3) : cells == 4 ? 2 : 3;

int speedPercent(num interval) => ((2000 - interval) * 100 / 1850).clamp(0, 100).round();
int intervalFromSpeed(num percent) => (2000 - percent.clamp(0, 100) * 1850 / 100).round();

List<Fields> colorSteps(List<List<int>> colors, int interval) => [
  for (final rgb in colors) {'rgb': rgb, 'durationMs': interval},
];

List<Fields> sceneSteps(Fields item) {
  if (!item.containsKey('steps')) {
    final colors = _colors(item['colors']);
    final interval = _integer(item['interval'], 150, 2000);
    return colors == null || interval == null ? [] : colorSteps(colors, interval);
  }
  final raw = item['steps'];
  if (raw is! List) return [];
  final steps = <Fields>[];
  for (final step in raw.whereType<Fields>()) {
    if (step.containsKey('effect') == step.containsKey('rgb')) continue;
    if (step.containsKey('effect')) {
      final effect = _integer(step['effect'], 1, 210);
      final duration = _integer(step['durationMs'], 1000, 600000);
      if (effect != null && duration != null) steps.add({'effect': effect, 'durationMs': duration});
    } else {
      final rgb = _rgb(step['rgb']);
      final duration = _integer(step['durationMs'], 150, 2000);
      if (rgb != null && duration != null) steps.add({'rgb': rgb, 'durationMs': duration});
    }
    if (steps.length == maxColors) break;
  }
  return steps;
}

Fields? _sequence(Fields item) {
  final id = item['id'];
  final name = item['name'];
  final steps = sceneSteps(item);
  final bri = _integer(item['bri'], 1, 100);
  if (!_text(id) || !_text(name) || steps.isEmpty || bri == null) return null;
  final trimmed = (name as String).trim();
  if (trimmed.length > maxSequenceName) return null;
  return {'id': id, 'name': trimmed, 'bri': bri, 'steps': steps};
}

List<Fields> _sequenceList(Object? raw) {
  if (raw is! List) return [];
  final result = <Fields>[];
  final ids = <Object?>{};
  final names = <String>{};
  for (final item in raw.whereType<Fields>()) {
    final scene = _sequence(item);
    if (scene == null) continue;
    final name = (scene['name'] as String).toLowerCase();
    if (ids.contains(scene['id']) || names.contains(name)) continue;
    ids.add(scene['id']);
    names.add(name);
    result.add(scene);
    if (result.length == maxSequences) break;
  }
  return result;
}

String? sequenceNameError(List<Fields> items, String? id, Object? name) {
  if (!_text(name)) return 'sequenceNameEmpty';
  final trimmed = (name as String).trim();
  if (trimmed.length > maxSequenceName) return 'sequenceNameTooLong';
  if (items.any((item) => item['id'] != id &&
      (item['name'] as String).trim().toLowerCase() == trimmed.toLowerCase())) {
    return 'sequenceNameDuplicate';
  }
  return null;
}

List<Fields> createSequence(List<Fields> items, {String Function(int)? nameFor}) {
  if (items.length >= maxSequences) return items;
  var id = 1;
  while (items.any((item) => item['id'] == '$id')) {
    id++;
  }
  for (var n = 1; n <= maxSequences; n++) {
    final name = nameFor?.call(n) ?? 'Secuencia $n';
    final error = sequenceNameError(items, null, name);
    if (error == 'sequenceNameDuplicate') continue;
    if (error != null) break;
    return [...items, {'id': '$id', 'name': name.trim(),
      'steps': colorSteps([[0, 255, 0], [255, 200, 0], [255, 0, 0]], 500), 'bri': 80}];
  }
  return items;
}

List<Fields> updateSequence(List<Fields> items, String id, Fields changes) {
  final index = items.indexWhere((item) => item['id'] == id);
  if (index < 0) return items;
  final item = {...items[index], ...changes, 'id': id};
  if (sequenceNameError(items, id, item['name']) != null) return items;
  final accepted = _sequence(item);
  return accepted == null ? items : _replace(items, index, accepted);
}

List<Fields> renameSequence(List<Fields> items, String id, String name) =>
    updateSequence(items, id, {'name': name});
List<Fields> removeSequence(List<Fields> items, String id) =>
    removeItem(items, items.indexWhere((item) => item['id'] == id));

List<List<int>> _sceneColors(Fields scene) => scene['colors'] as List<List<int>>;

Fields setColor(Fields scene, int index, List<int> rgb) {
  final colors = _sceneColors(scene);
  final color = _rgb(rgb);
  if (color == null || !_index(colors, index)) return scene;
  return {...scene, 'colors': _replace(colors, index, color)};
}

Fields addColor(Fields scene) {
  final colors = _sceneColors(scene);
  return colors.length >= maxColors ? scene :
      {...scene, 'colors': [...colors, [...colors.last]]};
}

Fields removeColor(Fields scene, int index) {
  final colors = _sceneColors(scene);
  return colors.length == 1 || !_index(colors, index) ? scene :
      {...scene, 'colors': removeItem(colors, index)};
}

Fields moveColor(Fields scene, int from, int to) {
  final colors = _sceneColors(scene);
  final moved = moveItem(colors, from, to);
  return identical(colors, moved) ? scene : {...scene, 'colors': moved};
}

final _hexPattern = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
String? _hex(Object? value) => value is String && value.length == 7 &&
    _hexPattern.hasMatch(value) ? value.toLowerCase() : null;

const _colorNames = {
  '#ffc880': 'warmWhite', '#ffffff': 'coolWhite', '#ff0000': 'red',
  '#ff6e00': 'orange', '#ffc800': 'yellow', '#00ff00': 'green',
  '#00ffff': 'cyan', '#0000ff': 'blue', '#ff0078': 'pink',
};
String colorName(String value) => _colorNames[_hex(value)] ?? 'solid';

List<String>? _palette(Object? value) {
  if (value is! List || value.length > paletteLimit) return null;
  final colors = <String>{};
  for (final item in value) {
    final hex = _hex(item);
    if (hex == null || !colors.add(hex)) return null;
  }
  return colors.toList();
}

List<String> addPaletteColor(List<String> colors, Object? value) {
  final hex = _hex(value);
  return hex == null || colors.contains(hex) || colors.length >= paletteLimit
      ? colors : [...colors, hex];
}

List<String> replacePaletteColor(List<String> colors, int index, Object? value) {
  final hex = _hex(value);
  return hex == null || colors.contains(hex) ? colors : _replace(colors, index, hex);
}
