import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'link.dart';
import 'model/effects.dart';
import 'model/models.dart';
import 'model/timer.dart';
import 'protocol.dart' as wire;
import 'sender.dart';
import 'strings.dart';
import 'ui/home_presets.dart';

/// Production scan awaits startup so platform errors reach the controller.
class AppBleApi extends UniversalBleApi {
  Future<void>? _starting;

  @override
  Stream<Strip> scan() async* {
    final starting = UniversalBle.startScan(scanFilter: ScanFilter(withNamePrefix: [namePrefix]));
    _starting = starting;
    try {
      await starting;
    } finally {
      _starting = null;
    }
    yield* UniversalBle.scanStream
        .where((device) => (device.name ?? '').startsWith(namePrefix))
        .map((device) => Strip(device.deviceId, device.name!));
  }

  @override
  Future<void> stopScan() async {
    try {
      await _starting;
    } finally {
      await super.stopScan();
    }
  }
}

Future<String?> bluetoothAccess(bool request) async {
  if (await UniversalBle.getBluetoothAvailabilityState() == AvailabilityState.poweredOff) {
    return 'bluetoothOff';
  }
  if (!await UniversalBle.hasPermissions()) {
    if (request) await UniversalBle.requestPermissions();
    if (!await UniversalBle.hasPermissions()) return 'permissionDenied';
  }
  return await UniversalBle.getBluetoothAvailabilityState() == AvailabilityState.poweredOn
      ? null : 'bluetoothOff';
}

class AppController extends ChangeNotifier {
  AppController(this._ble, LocalStore store, {
    required this.checkAccess,
    double Function()? now,
  }) : models = Models(store, presetIds: homePresets.keys.toSet()),
       _now = now ?? _monotonicClock() {
    _selection = models.loadState();
    language = models.loadLanguage();
    shortcuts = models.loadShortcuts();
    _rememberedStrips = models.loadRememberedStrips();
    stripsExpanded = models.loadStripsExpanded();
    link = Link(_ble, onChange: _linkChanged, onRemember: _remember);
    _sender = Sender(write: link.write, now: _now);
    final saved = remembered;
    _setupMigration = _save(models.migrateStripSettings(saved?.id));
    if (saved != null) link.restore(saved);
  }

  final BleApi _ble;
  final Models models;
  final Future<String?> Function(bool request) checkAccess;
  late final Link link;
  late final Sender _sender;
  late Fields _selection;
  late String language;
  late List<Fields> shortcuts;
  late List<RememberedStrip> _rememberedStrips;
  List<RememberedStrip> get rememberedStrips => List.unmodifiable(_rememberedStrips);
  RememberedStrip? get remembered => _rememberedStrips.firstOrNull;
  late final Future<void> _setupMigration;
  RememberedStrip? get setupDevice {
    final connected = link.ready ? link.strip : null;
    if (connected == null) return remembered;
    return _rememberedStrips.where((strip) => strip.id == connected.id).firstOrNull ??
        RememberedStrip(connected.id, connected.name);
  }
  late bool stripsExpanded;
  bool scanCompleted = false;
  int _scanGeneration = 0;
  String? message;
  bool busy = false;
  bool scanning = false;
  int _deviceGeneration = 0;
  String? connectingId;
  bool _scanRequested = false;
  bool get canCancelScan => _scanRequested || scanning;
  Future<void>? _stoppingScan;
  bool _foreground = true;
  int _foregroundGeneration = 0;
  bool _disposed = false;
  final _devices = <String, Strip>{};
  List<Strip> get devices => List.unmodifiable(_devices.values);
  StreamSubscription<Strip>? _scan;
  Timer? _scanTimeout;
  Timer? _timer;
  Timer? _player;
  final double Function() _now;
  LinkStatus _previousStatus = LinkStatus.idle;
  bool _recoverPending = false;

  static double Function() _monotonicClock() {
    final elapsed = Stopwatch()..start();
    return () => elapsed.elapsedMicroseconds / 1000;
  }
  int? remaining;
  int? _fadeLevel;
  int _generation = 0;
  int _playback = 0;
  bool _playing = false;
  String? _playingSequence;
  bool previewing = false;
  bool _powerBeforePreview = false;

  bool? sentPower;
  int? sentBrightness;
  List<int>? sentColor;
  int? _sentEffect;
  String? lastCommand;
  String? _sentDeviceId;
  Map<String, Object?> lastValues = const {};
  int get brightness => _selection['bri'] as int;
  int get speed => _selection['speed'] as int;
  int get effect => _selection['fx'] == 'AUTO' ? wire.autoEffect : _selection['fx'] as int;
  int get sensitivity => _selection['micSens'] as int;
  bool get ready => link.ready && !busy;
  bool get canSend => ready && _foreground && !_disposed;
  bool get hasActiveEffect => link.ready && sentPower == true && _sentEffect != null;
  String? get lastSentLabel => switch (lastCommand) {
    null => null,
    'brightness' || 'speed' || 'micSensitivity' =>
        '${text(lastCommand!)} · ${text('percent', lastValues)}',
    'color' => '${text('color')} · ${lastValues['hex']}',
    'chipConfig' => '${lastValues['order']} · ${lastValues['pixels']} LEDs',
    final key => text(key, lastValues),
  };
  String text(String key, [Map<String, Object?> values = const {}]) =>
      translate(language, key, values);

  void _refresh() {
    if (!_disposed) notifyListeners();
  }

  void _notice(String? key) {
    message = key;
    _refresh();
  }

  Future<void> _save(Future<bool> operation) async {
    if (!await operation) _notice('appStorageFailed');
  }

  void _remember(String? id) {
    final strip = link.strip;
    if (id == null || strip == null) return;
    _setRemembered(RememberedStrip.remember(_rememberedStrips, strip));
  }

  void _setRemembered(List<RememberedStrip> strips) {
    _rememberedStrips = strips;
    unawaited(_save(models.saveRememberedStrips(strips)));
    _refresh();
  }

  void renameStrip(String id, String alias) => _setRemembered([
    for (final strip in _rememberedStrips) strip.id == id ? strip.renamed(alias) : strip,
  ]);

  void toggleStripsExpanded() {
    stripsExpanded = !stripsExpanded;
    unawaited(_save(models.saveStripsExpanded(stripsExpanded)));
    _refresh();
  }

  void _linkChanged() {
    if (!link.ready) {
      _generation++;
      _sender.cancel();
      _stopPlayback();
      cancelTimer();
      sentPower = null;
      sentBrightness = null;
      sentColor = null;
      _sentEffect = null;
    } else if (_sentDeviceId != link.strip?.id) {
      lastCommand = null;
    }
    _refresh();
    if (link.status == LinkStatus.lost && _previousStatus == LinkStatus.connected) {
      _recoverPending = true;
    } else if (link.status != LinkStatus.lost) {
      _recoverPending = false;
    }
    _previousStatus = link.status;
    _maybeRecover();
  }

  void _maybeRecover() {
    if (_recoverPending && _foreground && !busy && !_disposed) {
      _recoverPending = false;
      unawaited(_reconnect(request: false));
    }
  }

  Future<void> _deviceAction(Future<void> Function() action, String failure,
      {void Function(String)? onFailure, String? targetId, bool scan = false}) async {
    final report = onFailure ?? _notice;
    if (busy || _disposed) return;
    final generation = ++_deviceGeneration;
    connectingId = targetId;
    _scanRequested = scan;
    busy = true;
    _notice(null);
    try {
      await action();
    } on UnsupportedController {
      if (generation == _deviceGeneration) report('controllerUnsupported');
    } catch (_) {
      if (generation == _deviceGeneration) report(failure);
    } finally {
      if (generation == _deviceGeneration) _finishDeviceAction();
    }
  }

  void _finishDeviceAction() {
    connectingId = null;
    _scanRequested = false;
    busy = false;
    _refresh();
    _maybeRecover();
  }

  void cancelConnection() {
    if (connectingId == null) return;
    _deviceGeneration++;
    link.cancelConnect();
    _finishDeviceAction();
  }

  void cancelScan() {
    if (!canCancelScan) return;
    final pending = _scanRequested;
    if (pending) _deviceGeneration++;
    unawaited(stopScan(silent: true));
    if (pending) _finishDeviceAction();
  }

  Future<void> startScan() async {
    if (scanning) return;
    await _deviceAction(() async {
      final generation = ++_scanGeneration;
      _devices.clear();
      scanCompleted = false;
      final problem = await checkAccess(true);
      await _stoppingScan;
      if (!_foreground || _disposed || generation != _scanGeneration) return;
      if (problem != null) return _notice(problem);
      scanning = true;
      _scan = _ble.scan().listen((strip) {
        if (generation == _scanGeneration && strip.name.startsWith(namePrefix)) {
          _devices[strip.id] = strip;
          _refresh();
        }
      }, onError: (Object _) {
        if (generation != _scanGeneration) return;
        _notice('scanFailed');
        unawaited(stopScan());
      }, onDone: () => _finishScan(generation));
      _scanTimeout = Timer(const Duration(seconds: 10), () => _finishScan(generation));
    }, 'scanFailed', scan: true);
  }

  void _finishScan(int generation) {
    if (generation != _scanGeneration) return;
    scanCompleted = true;
    unawaited(stopScan());
  }

  Future<void> stopScan({bool silent = false}) async {
    final generation = ++_scanGeneration;
    if (!scanning) {
      await _stoppingScan;
      return;
    }
    scanning = false;
    _scanTimeout?.cancel();
    final scan = _scan;
    _scan = null;
    void failed(Object _) {
      if (!silent && generation == _scanGeneration && connectingId == null) _notice('scanFailed');
    }
    final stopping = Future<void>.microtask(_ble.stopScan).catchError(failed);
    _stoppingScan = stopping;
    unawaited(scan?.cancel().catchError(failed));
    _refresh();
    await stopping;
    if (identical(_stoppingScan, stopping)) _stoppingScan = null;
  }

  Future<void> connect(Strip target, {void Function(String)? onFailure}) =>
      _connect(target, request: true, onFailure: onFailure);

  Future<void> reconnect() => _reconnect(request: true);

  Future<void> _reconnect({required bool request}) async {
    final target = remembered;
    if (target == null || link.ready) return;
    await _connect(target, request: request, recovery: true);
  }

  Future<void> _connect(Strip target, {required bool request, bool recovery = false,
      void Function(String)? onFailure}) => _deviceAction(() async {
    final generation = _deviceGeneration;
    final foreground = _foregroundGeneration;
    bool active() => _foreground && !_disposed && generation == _deviceGeneration &&
        foreground == _foregroundGeneration;
    if (recovery || !_devices.containsKey(target.id)) {
      final problem = await checkAccess(request);
      if (!active()) return;
      if (problem != null) return (onFailure ?? _notice)(problem);
    }
    await stopScan(silent: true);
    if (!active()) return;
    if (recovery) link.restore(target);
    try {
      await (recovery ? link.reconnect() : link.connect(target));
    } finally {
      if (generation == _deviceGeneration && !link.ready && remembered != null) {
        link.restore(remembered!);
      }
    }
  }, 'connectFailed', onFailure: onFailure, targetId: target.id);

  Future<void> disconnect() => _deviceAction(link.disconnect, 'disconnectFailed');
  Future<void> forgetStrip(String id) => _deviceAction(() async {
    if (link.strip?.id == id) {
      await link.disconnect();
      await link.forget();
      lastCommand = null;
      _sentDeviceId = null;
    }
    _setRemembered(_rememberedStrips.where((strip) => strip.id != id).toList());
    await _setupMigration;
    await _save(models.removeDeviceSetup(id));
    final next = remembered;
    if (link.strip == null && next != null) link.restore(next);
  }, 'disconnectFailed');

  void setLanguage(String value) {
    language = value;
    unawaited(_save(models.saveLanguage(value)));
    _refresh();
  }

  void updateShortcuts(List<Fields> items) {
    shortcuts = models.filterShortcuts(items);
    unawaited(_save(models.saveShortcuts(shortcuts)));
    _refresh();
  }

  void _select(Fields changes, {bool save = true}) {
    _selection = {..._selection, ...changes};
    if (save) unawaited(_save(models.saveState(_selection)));
    _refresh();
  }

  Future<bool> _send(Uint8List frame, String label, {
    String? key, Map<String, Object?> values = const {},
    void Function()? onSent, void Function()? onWriteError,
  }) async {
    if (!canSend) return false;
    final generation = _generation;
    try {
      if (await _sender.send(frame, key: key) != 'sent' ||
          generation != _generation || _disposed) {
        return false;
      }
      onSent?.call();
      _sentDeviceId = link.strip?.id;
      lastCommand = label;
      lastValues = values;
      _refresh();
      return true;
    } catch (_) {
      if (generation == _generation) {
        _notice('commandFailed');
        onWriteError?.call();
      }
      return false;
    }
  }

  Future<bool> _sendPower(bool value) => _send(wire.power(value),
      value ? 'power' : 'off', onSent: () {
        sentPower = value;
        if (!value) _sentEffect = null;
      });

  void setPower(bool value) {
    if (!ready) return;
    if (value) {
      final scene = _selection['scene'];
      final mode = _selection['mode'];
      if (mode is Fields) {
        if (mode['effect'] == 'AUTO') {
          unawaited(setEffect(wire.autoEffect));
          return;
        }
        if (mode['effect'] case final int id) {
          unawaited(setEffect(id));
          return;
        }
        if (mode['voice'] case final int id) {
          unawaited(setVoiceMode(id));
          return;
        }
      }
      final item = switch (mode) {
        {'preset': final String preset, 'interval': final int interval}
            when homePresets.containsKey(preset) =>
          <String, Object?>{'kind': 'scene', 'preset': preset, 'interval': interval},
        _ when scene is String && scene.startsWith('sequence:') =>
          <String, Object?>{'kind': 'sequence', 'id': scene.substring(9)},
        _ => <String, Object?>{'kind': 'color', 'rgb': _selection['rgb']},
      };
      unawaited(applyShortcut(item));
      return;
    }
    _stopPlayback();
    cancelTimer();
    unawaited(_powerOff());
  }

  Future<void> _powerOff() async {
    if (await _sendPower(false)) _select({'on': false});
  }

  Future<bool> _sendBrightness(int value, {void Function()? onWriteError}) => _send(wire.brightness(value),
      'brightness', key: 'brightness', values: {'value': value},
      onSent: () => sentBrightness = value, onWriteError: onWriteError);

  void setBrightness(int value) {
    if (value == brightness) return;
    if (!canSend) {
      _select({'bri': value});
      return;
    }
    stopPlayback();
    _select({'bri': value}, save: false);
    unawaited(_sendBrightness(value));
  }

  void saveSelection() => unawaited(_save(models.saveState(_selection)));

  void setSpeed(int value) {
    if (value == speed || value < 1 || value > 100) return;
    if (!canSend) {
      _select({'speed': value});
      return;
    }
    stopPlayback();
    _select({'speed': value}, save: false);
    unawaited(_send(wire.speed(value), 'speed',
        key: 'speed', values: {'value': value}));
  }

  Future<bool> _prepare(int run, int intensity) async {
    if (sentPower != true && !await _sendPower(true)) return false;
    if (run != _playback) return false;
    if (sentBrightness != intensity && !await _sendBrightness(intensity)) return false;
    return run == _playback && canSend;
  }

  Future<void> setEffect(int id, {bool preview = false}) async {
    if (!canSend || (id != wire.autoEffect && (id < 1 || id > 210))) return;
    _beginPlayback(preview: preview);
    final run = _playback;
    if (!await _prepare(run, brightness)) return;
    final label = id == wire.autoEffect ? 'autoCycle' : 'effectNamed';
    if (await _send(wire.effect(id), label, key: 'effect',
        values: {'id': id, 'name': effectName(id)}, onSent: () {
          _sentEffect = id;
          sentColor = null;
        }) && run == _playback && !preview) {
      final fx = id == wire.autoEffect ? 'AUTO' : id;
      _select({'on': true, 'fx': fx, 'scene': null,
        'label': [label, {'id': id, 'name': effectName(id) ?? 'AUTO'}],
        'mode': {'effect': fx}});
    }
  }

  Future<void> setVoiceMode(int id) async {
    if (!canSend || id < 1 || id > 4) return;
    _beginPlayback();
    final run = _playback;
    if (!await _prepare(run, brightness)) return;
    if (!await _send(wire.voiceMode(id), 'musicMode', key: 'voice', values: {'id': id},
        onSent: () {
          _sentEffect = null;
          sentColor = null;
        }) || run != _playback) {
      return;
    }
    _select({'on': true, 'scene': null, 'label': ['musicMode'], 'mode': {'voice': id}});
    await _sendSensitivity(sensitivity);
  }

  Future<bool> _sendSensitivity(int value) => _send(wire.micSensitivity(value),
      'micSensitivity', key: 'micSensitivity', values: {'value': value});

  void setMicSensitivity(int value) {
    if (value < 0 || value > 100 || value == sensitivity) return;
    if (!canSend) {
      _select({'micSens': value});
      return;
    }
    stopPlayback();
    _select({'micSens': value}, save: false);
    unawaited(_sendSensitivity(value));
  }

  Future<bool> setChipConfig(String order, int pixels, {num? density, num? meters}) async {
    final id = link.strip?.id;
    if (!canSend || id == null || !wire.chipOrders.contains(order) || validPixels(pixels) == null) return false;
    _beginPlayback();
    final sent = await _send(wire.chipConfig(order, pixels), 'chipConfig',
        values: {'order': order, 'pixels': pixels});
    if (sent) {
      await _save(models.saveStripSettings(deviceId: id, order: order, pixels: pixels,
          density: density, meters: meters));
    }
    return sent;
  }

  String shortcutLabel(Fields item) => switch (item['kind']) {
    'scene' => text(item['preset'] as String),
    'sequence' => _sequence(item['id'])?['name'] as String? ?? text('myScenes'),
    _ => item['name'] == null
        ? rgbHex(item['rgb'] as List<int>) : text(item['name'] as String),
  };

  Fields? _sequence(Object? id) => models.loadSequences()
      .where((item) => item['id'] == id).firstOrNull;

  Future<bool> _sendColor(List<int> rgb) => _send(wire.color(rgb[0], rgb[1], rgb[2]),
      'color', key: 'color', values: {'hex': rgbHex(rgb)}, onSent: () {
        _sentEffect = null;
        sentColor = rgb;
      });

  Future<void> applyShortcut(Fields item) async {
    if (!canSend) return;
    final preset = homePresets[item['preset']];
    final sequence = _sequence(item['id']);
    final rgb = item['rgb'] as List<int>?;
    final colors = preset?.colors ?? sequence?['colors'] as List<List<int>>?;
    if (rgb == null && colors == null) return;
    _beginPlayback(sequence: sequence?['id'] as String?, playing: colors != null);
    final run = _playback;
    final intensity = preset != null ? 50 : sequence?['bri'] as int? ?? brightness;
    if (!await _prepare(run, intensity)) return _stopCurrentPlayback(run);
    if (rgb != null && await _sendColor(rgb) && run == _playback) {
      _select({...solidSelection(rgb), 'rgb': rgb, 'on': true});
    } else if (colors != null) {
      final interval = preset != null
          ? (item['interval'] as int?)?.clamp(150, 2000) ?? preset.interval
          : sequence!['interval'] as int;
      var index = 0;
      Future<void> next() async {
        if (run != _playback || !_foreground) return;
        final sent = await _sendColor(colors[index]);
        if (!sent || run != _playback) return _stopCurrentPlayback(run);
        index = (index + 1) % colors.length;
        _player = Timer(Duration(milliseconds: interval), () => unawaited(next()));
      }
      await next();
      if (_player != null && run == _playback) {
        _select({
          'on': true,
          'scene': preset != null ? item['preset'] : 'sequence:${item['id']}',
          'label': preset != null ? [item['preset']] : sequence!['name'],
          'mode': preset != null ? {'preset': item['preset'], 'interval': interval}
              : {'colors': colors, 'interval': interval},
        });
      }
    }
  }

  void setDraftPreviewBrightness(int value) {
    if (!canSend || !previewing || !_playing || sentPower != true || value < 1 || value > 100) return;
    unawaited(_sendBrightness(value));
  }

  Future<void> playDraft(List<List<int>> colors, int interval, int intensity,
      {bool preview = true,
      ({List<List<int>> colors, int interval, int intensity}) Function()? draft}) async {
    if (!canSend || colors.isEmpty) return;
    _beginPlayback(preview: preview, playing: true);
    final run = _playback;
    final liveDraft = preview && draft != null;
    if (liveDraft) {
      if (sentPower != true && !await _sendPower(true)) return _stopCurrentPlayback(run);
      if (run != _playback || !canSend) return _stopCurrentPlayback(run);
      // Queue ahead of the first color, but don't await a frame that a drag can replace.
      final initialBrightness = draft().intensity;
      if (sentBrightness != initialBrightness && initialBrightness >= 1 && initialBrightness <= 100) {
        unawaited(_sendBrightness(initialBrightness, onWriteError: () => _stopCurrentPlayback(run)));
      }
    } else if (!await _prepare(run, intensity)) {
      return _stopCurrentPlayback(run);
    }
    var index = 0;
    Future<void> next() async {
      if (run != _playback || !canSend) return _stopCurrentPlayback(run);
      final step = draft?.call() ?? (colors: colors, interval: interval, intensity: intensity);
      if (step.colors.isEmpty || (!liveDraft && !await _prepare(run, step.intensity))) return _stopCurrentPlayback(run);
      if (!await _sendColor(step.colors[index % step.colors.length]) || run != _playback) return _stopCurrentPlayback(run);
      index++;
      _player = Timer(Duration(milliseconds: step.interval), () => unawaited(next()));
    }
    await next();
  }

  void stopDraftPreview({bool restore = true}) {
    if (!previewing) return;
    final wasOn = _powerBeforePreview;
    stopPlayback();
    if (restore) setPower(wasOn);
  }

  void stopSequence(String id) {
    if (_playingSequence == id) stopPlayback();
  }

  void _stopCurrentPlayback(int run) {
    if (run == _playback) stopPlayback();
  }

  void stopPlayback() {
    final wasPlaying = _playing || previewing;
    if (!wasPlaying) return;
    _stopPlayback();
    _refresh();
  }

  void _beginPlayback({bool preview = false, bool playing = false, String? sequence}) {
    if (preview && !previewing) _powerBeforePreview = sentPower == true;
    _stopPlayback();
    previewing = preview;
    _playing = playing;
    _playingSequence = sequence;
    if (preview) _refresh();
  }

  void _stopPlayback() {
    _playback++;
    if (_playing || previewing) _sender.cancel();
    _playing = false;
    _playingSequence = null;
    previewing = false;
    _player?.cancel();
    _player = null;
  }

  void startTimer(int seconds, {required bool fade}) {
    if (!ready || !_foreground || seconds <= 0) return;
    cancelTimer(restoreBrightness: true);
    remaining = seconds;
    final deadline = _now() + seconds * 1000;
    void tick() {
      final left = (deadline - _now()) / 1000;
      if (left <= 0) {
        cancelTimer();
        setPower(false);
        return;
      }
      final step = fadeBrightness(brightness, left, fade);
      if (step != null && step != _fadeLevel) {
        _fadeLevel = step;
        unawaited(_sendBrightness(step));
      }
      if (remaining != left.ceil()) {
        remaining = left.ceil();
        _refresh();
      }
    }
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    tick();
    _refresh();
  }

  void cancelTimer({bool restoreBrightness = false}) {
    _timer?.cancel();
    if (remaining == null) return;
    remaining = null;
    final faded = _fadeLevel != null;
    _fadeLevel = null;
    if (faded && restoreBrightness) unawaited(_sendBrightness(brightness));
    _refresh();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _foregroundGeneration++;
      cancelTimer();
      _stopPlayback();
      _sender.cancel();
      unawaited(stopScan());
    } else {
      _maybeRecover();
    }
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    setForeground(false);
    unawaited(link.dispose());
    super.dispose();
  }
}
