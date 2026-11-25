import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'link.dart';
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
    remembered = models.loadRemembered();
    link = Link(_ble, onChange: _linkChanged, onRemember: _remember);
    sender = Sender(write: link.write, now: _now);
    final saved = remembered;
    if (saved != null) link.restore(saved);
  }

  final BleApi _ble;
  final Models models;
  final Future<String?> Function(bool request) checkAccess;
  late final Link link;
  late final Sender sender;
  late Fields _selection;
  late String language;
  late List<Fields> shortcuts;
  Strip? remembered;
  String? message;
  bool busy = false;
  bool scanning = false;
  bool _foreground = true;
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

  bool? sentPower;
  int? sentBrightness;
  List<int>? sentColor;
  String? lastCommand;
  String? _sentDeviceId;
  Map<String, Object?> lastValues = const {};
  int get brightness => _selection['bri'] as int;
  int get speed => _selection['speed'] as int;
  bool get ready => link.ready && !busy;
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
    remembered = id == null ? null : link.strip;
    unawaited(_save(models.saveRemembered(remembered)));
    _refresh();
  }

  void _linkChanged() {
    if (!link.ready) {
      _generation++;
      sender.cancel();
      _stopPlayback();
      cancelTimer();
      sentPower = null;
      sentBrightness = null;
      sentColor = null;
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

  Future<void> _deviceAction(Future<void> Function() action, String failure) async {
    if (busy || _disposed) return;
    busy = true;
    _notice(null);
    try {
      await action();
    } on UnsupportedController {
      _notice('controllerUnsupported');
    } catch (_) {
      _notice(failure);
    } finally {
      busy = false;
      _refresh();
      _maybeRecover();
    }
  }

  Future<void> startScan() => _deviceAction(() async {
    if (scanning) return;
    _devices.clear();
    final problem = await checkAccess(true);
    if (problem != null) return _notice(problem);
    if (!_foreground || _disposed) return;
    scanning = true;
    _scan = _ble.scan().listen((strip) {
      if (strip.name.startsWith(namePrefix)) {
        _devices[strip.id] = strip;
        _refresh();
      }
    }, onError: (Object _) {
      _notice('scanFailed');
      unawaited(stopScan());
    });
    _scanTimeout = Timer(const Duration(seconds: 10), () => unawaited(stopScan()));
  }, 'scanFailed');

  Future<void> stopScan() async {
    if (!scanning) return;
    scanning = false;
    _scanTimeout?.cancel();
    final scan = _scan;
    _scan = null;
    try {
      unawaited(scan?.cancel().catchError((Object _) => _notice('scanFailed')));
      await _ble.stopScan();
    } catch (_) {
      _notice('scanFailed');
    }
    _refresh();
  }

  Future<void> connect(Strip target) => _deviceAction(() async {
    await stopScan();
    if (!_foreground || _disposed) return;
    try {
      await link.connect(target);
    } finally {
      if (!link.ready && remembered != null) link.restore(remembered!);
    }
  }, 'connectFailed');

  Future<void> reconnect() => _reconnect(request: true);

  Future<void> _reconnect({required bool request}) => _deviceAction(() async {
    final target = remembered;
    if (target == null || link.ready) return;
    final problem = await checkAccess(request);
    if (problem != null) return _notice(problem);
    if (!_foreground || _disposed) return;
    await stopScan();
    link.restore(target);
    await link.reconnect();
  }, 'connectFailed');

  Future<void> disconnect() => _deviceAction(link.disconnect, 'disconnectFailed');
  Future<void> forget() => _deviceAction(() async {
    await link.forget();
    lastCommand = null;
    _sentDeviceId = null;
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
    void Function()? onSent,
  }) async {
    if (!ready || !_foreground) return false;
    final generation = _generation;
    try {
      if (await sender.send(frame, key: key) != 'sent' ||
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
      if (generation == _generation) _notice('commandFailed');
      return false;
    }
  }

  Future<bool> _sendPower(bool value) => _send(wire.power(value),
      value ? 'power' : 'off', onSent: () => sentPower = value);

  void setPower(bool value) {
    if (!ready) return;
    if (value) {
      final scene = _selection['scene'];
      final mode = _selection['mode'];
      final item = switch (mode) {
        {'preset': final String preset} when homePresets.containsKey(preset) =>
          <String, Object?>{'kind': 'scene', 'preset': preset},
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

  Future<bool> _sendBrightness(int value) => _send(wire.brightness(value),
      'brightness', key: 'brightness', values: {'value': value},
      onSent: () => sentBrightness = value);

  void setBrightness(int value) {
    if (!ready || value == brightness) return;
    _select({'bri': value}, save: false);
    unawaited(_sendBrightness(value));
  }

  void saveSelection() => unawaited(_save(models.saveState(_selection)));

  void setSpeed(int value) {
    if (!ready || value == speed || value < 1) return;
    _select({'speed': value}, save: false);
    unawaited(_send(wire.speed(value), 'speed',
        key: 'speed', values: {'value': value}));
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
      'color', key: 'color', values: {'hex': rgbHex(rgb)}, onSent: () => sentColor = rgb);

  Future<void> applyShortcut(Fields item) async {
    if (!ready) return;
    _stopPlayback();
    final run = _playback;
    final preset = homePresets[item['preset']];
    final sequence = _sequence(item['id']);
    final rgb = item['rgb'] as List<int>?;
    final colors = preset?.colors ?? sequence?['colors'] as List<List<int>>?;
    if (rgb == null && colors == null) return;
    final intensity = preset != null ? 50 : sequence?['bri'] as int? ?? brightness;
    if (sentPower != true && !await _sendPower(true)) return;
    if (run != _playback) return;
    if (sentBrightness != intensity && !await _sendBrightness(intensity)) return;
    if (run != _playback) return;
    if (rgb != null && await _sendColor(rgb) && run == _playback) {
      _select({...solidSelection(rgb), 'rgb': rgb, 'on': true});
    } else if (colors != null) {
      final interval = preset?.interval ?? sequence!['interval'] as int;
      var index = 0;
      Future<void> next() async {
        if (run != _playback || !_foreground) return;
        final sent = await _sendColor(colors[index]);
        if (!sent || run != _playback) return;
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

  void _stopPlayback() {
    _playback++;
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
    _foreground = value;
    if (!value) {
      cancelTimer();
      _stopPlayback();
      sender.cancel();
      unawaited(stopScan());
    } else {
      _maybeRecover();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    setForeground(false);
    unawaited(link.dispose());
    super.dispose();
  }
}
