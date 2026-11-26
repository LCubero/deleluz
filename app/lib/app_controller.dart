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
    Future<AvailabilityState> Function()? readBluetooth,
    Stream<AvailabilityState>? bluetoothChanges,
    Future<void> Function()? requestBluetooth,
    double Function()? now,
    DateTime Function()? wallClock,
  }) : models = Models(store, presetIds: homePresets.keys.toSet()),
       _requestBluetooth = requestBluetooth ?? (_ble is AppBleApi ? _enableSystemBluetooth : null),
       _now = now ?? _monotonicClock(),
       _wallClock = wallClock ?? DateTime.now {
    _lastTimerDuration = _savedTimerDuration = loadTimerDuration(store);
    _selection = models.loadState();
    language = models.loadLanguage();
    shortcuts = models.loadShortcuts();
    _effectFavorites = models.loadEffectFavorites();
    _appAuto = models.loadAppAuto();
    _rememberedStrips = models.loadRememberedStrips();
    stripsExpanded = models.loadStripsExpanded();
    link = Link(_ble, onChange: _linkChanged, onRemember: _remember);
    _sender = Sender(write: link.write, now: _now);
    final saved = remembered;
    _setupMigration = _save(models.migrateStripSettings(saved?.id));
    if (saved != null) link.restore(saved);
    final production = _ble is AppBleApi;
    final changes = bluetoothChanges ?? (production ? UniversalBle.availabilityStream : null);
    final read = readBluetooth ?? (production ? UniversalBle.getBluetoothAvailabilityState : null);
    var receivedChange = false;
    _bluetoothChanges = changes?.listen((state) {
      if (!_isBluetoothPowerState(state)) return;
      receivedChange = true;
      _updateBluetooth(state);
    }, onError: (Object _) {});
    if (read != null) {
      unawaited(_readBluetooth(read, () => !receivedChange));
    }
  }

  final Future<void> Function()? _requestBluetooth;
  StreamSubscription<AvailabilityState>? _bluetoothChanges;
  bool _bluetoothOff = false;
  bool get bluetoothOff => _bluetoothOff;
  bool requestingBluetooth = false;

  static Future<void> _enableSystemBluetooth() async {
    if (!await UniversalBle.hasPermissions()) {
      await UniversalBle.requestPermissions();
      if (!await UniversalBle.hasPermissions()) throw StateError('Bluetooth permission denied');
    }
    await UniversalBle.enableBluetooth();
  }

  Future<void> _readBluetooth(Future<AvailabilityState> Function() read, bool Function() current) async {
    try {
      final state = await read();
      if (current()) _updateBluetooth(state);
    } catch (_) {
      // Availability is unknown if the platform cannot be queried.
    }
  }

  static bool _isBluetoothPowerState(AvailabilityState state) =>
      state == AvailabilityState.poweredOff || state == AvailabilityState.poweredOn;

  void _updateBluetooth(AvailabilityState state) {
    if (_disposed || !_isBluetoothPowerState(state)) return;
    final off = state == AvailabilityState.poweredOff;
    if (_bluetoothOff == off) return;
    _bluetoothOff = off;
    if (off) {
      _foregroundGeneration++;
      _recoverPending = false;
      unawaited(stopScan(silent: true));
      link.radioOff();
    } else {
      _refresh();
    }
  }

  Future<void> requestEnableBluetooth() async {
    final request = _requestBluetooth;
    if (request == null || requestingBluetooth || !_bluetoothOff || _disposed) return;
    requestingBluetooth = true;
    _notice(null);
    try {
      await request();
    } catch (_) {
      if (_bluetoothOff) _notice('bluetoothEnableFailed');
    } finally {
      requestingBluetooth = false;
      _refresh();
    }
  }

  final BleApi _ble;
  final Models models;
  bool get sessionOnlyStorage => models.storage is SessionOnlyStore;
  final Future<String?> Function(bool request) checkAccess;
  late final Link link;
  late final Sender _sender;
  late Fields _selection;
  late String language;
  late List<Fields> shortcuts;
  late final Set<int> _effectFavorites;
  Set<int> get effectFavorites => Set.unmodifiable(_effectFavorites);

  void toggleEffectFavorite(int id) {
    if (id < 1 || id > 210) return;
    if (!_effectFavorites.remove(id)) _effectFavorites.add(id);
    unawaited(_save(models.saveEffectFavorites(_effectFavorites)));
    if (_appAuto.favorites && _effectFavorites.isEmpty && appAutoPlaying) _stopPlayback();
    notifyListeners();
  }

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
  bool _timerFade = false;
  double _timerDeadline = 0;
  final DateTime Function() _wallClock;
  DateTime? _timerEndTime;
  DateTime? get timerEndTime => _timerEndTime;
  late int _lastTimerDuration;
  late int _savedTimerDuration;
  Future<void> _timerDurationSave = Future<void>.value();
  int get lastTimerDuration => _lastTimerDuration;
  int _timerSpan = 1;
  double get timerFraction => (remaining ?? 0) / _timerSpan;
  int _generation = 0;
  int _playback = 0;
  bool _playing = false;
  String? _playingSequence;
  late ({int seconds, bool favorites}) _appAuto;
  int get appAutoSeconds => _appAuto.seconds;
  bool get appAutoFavorites => _appAuto.favorites;
  bool _appAutoPlaying = false;
  bool get appAutoPlaying => _appAutoPlaying;
  int? _appAutoEffect;
  int? get appAutoEffect => _appAutoEffect;
  int _appAutoStep = 0;
  int get appAutoStep => _appAutoStep;
  double _appAutoStartedAt = 0;
  double get appAutoProgress => _appAutoEffect == null ? 0 :
      ((_now() - _appAutoStartedAt) / (appAutoSeconds * 1000)).clamp(0.0, 1.0);

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
  bool get ready => link.ready && !busy && !bluetoothOff;
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
    if (key != null && message == key) return;
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
      _interruptTimer();
      sentPower = null;
      sentBrightness = null;
      sentColor = null;
      _sentEffect = null;
    } else {
      if (_sentDeviceId != link.strip?.id) lastCommand = null;
      _restoreInterruptedFade();
    }
    _refresh();
    if (!_bluetoothOff && link.status == LinkStatus.lost && _previousStatus == LinkStatus.connected) {
      _recoverPending = true;
    } else if (link.status != LinkStatus.lost) {
      _recoverPending = false;
    }
    _previousStatus = link.status;
    _maybeRecover();
  }

  static const _recoveryCooldownMs = 5000;
  double _nextRecoveryAt = double.negativeInfinity;
  bool _recovering = false;

  void _maybeRecover() {
    if (_recoverPending && _foreground && !busy && !_disposed) {
      _recoverPending = false;
      if (_bluetoothOff || _recovering || _now() < _nextRecoveryAt) return;
      _recovering = true;
      unawaited(_reconnect(request: false).whenComplete(() {
        _nextRecoveryAt = _now() + _recoveryCooldownMs;
        _recovering = false;
      }));
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
    _restoreInterruptedFade();
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
    bool active() => _foreground && !_disposed && !_bluetoothOff && generation == _deviceGeneration &&
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

  int _shortcutEdit = 0;

  Future<void> updateShortcuts(List<Fields> items) async {
    final edit = ++_shortcutEdit;
    final next = models.filterShortcuts(items);
    if (!await models.saveShortcuts(next)) {
      if (edit == _shortcutEdit) _notice('appStorageFailed');
      return;
    }
    if (_disposed || edit != _shortcutEdit) return;
    shortcuts = next;
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
    bool reportFailure = true,
  }) async {
    if (!canSend) return false;
    final generation = _generation;
    try {
      if (await _sender.send(frame, key: key) != 'sent' ||
          generation != _generation || _disposed) {
        return false;
      }
      onSent?.call();
      if (message == 'commandFailed') message = null;
      _sentDeviceId = link.strip?.id;
      lastCommand = label;
      lastValues = values;
      _refresh();
      return true;
    } catch (_) {
      if (generation == _generation) {
        if (reportFailure) _notice('commandFailed');
        onWriteError?.call();
      }
      return false;
    }
  }

  Future<bool> _sendPower(bool value, {bool fromTimer = false}) => _send(wire.power(value),
      value ? 'power' : 'off', reportFailure: !fromTimer, onSent: () {
        sentPower = value;
        if (!value) {
          _sentEffect = null;
          _clearTimerOffFailure();
        }
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

  Future<void> _powerOff({bool fromTimer = false}) async {
    final generation = _timerOffGeneration;
    if (await _sendPower(false, fromTimer: fromTimer)) {
      _select({'on': false});
    } else if (fromTimer && !_disposed && generation == _timerOffGeneration) {
      // Link loss does not dismiss the warning, but a newer timer or a successful OFF does.
      _timerOffFailed = true;
      _refresh();
    }
  }

  int _timerOffGeneration = 0;
  bool _timerOffFailed = false;
  bool _retryingTimerOff = false;
  bool get timerOffFailed => _timerOffFailed;
  bool get canRetryTimerOff => timerOffFailed && canSend && !_retryingTimerOff;

  void _clearTimerOffFailure() {
    _timerOffGeneration++;
    _timerOffFailed = false;
  }

  Future<void> retryTimerOff() async {
    if (!canRetryTimerOff) return;
    _retryingTimerOff = true;
    _refresh();
    try {
      _stopPlayback();
      await _powerOff(fromTimer: true);
    } finally {
      _retryingTimerOff = false;
      _refresh();
    }
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
    if (!appAutoPlaying) stopPlayback();
    _select({'speed': value}, save: false);
    unawaited(_send(wire.speed(value), 'speed',
        key: 'speed', values: {'value': value}));
  }

  Future<bool> _prepare(int run, int intensity) async {
    if (sentPower != true && !await _preparePower()) return false;
    if (run != _playback) return false;
    if (sentBrightness != intensity && !await _sendBrightness(intensity)) return false;
    return run == _playback && canSend;
  }

  void setAppAutoOptions({int? seconds, bool? favorites}) {
    if (appAutoPlaying || (seconds != null && !Models.appAutoDurations.contains(seconds)) ||
        (favorites == true && _effectFavorites.isEmpty)) {
      return;
    }
    final options = (seconds: seconds ?? appAutoSeconds, favorites: favorites ?? appAutoFavorites);
    if (options == _appAuto) return;
    _appAuto = options;
    unawaited(_save(models.saveAppAuto(options.seconds, options.favorites)));
    _refresh();
  }

  ({int generation, Future<bool> result})? _pendingPowerOn;

  Future<bool> _preparePower() async {
    final pending = _pendingPowerOn;
    if (pending != null && pending.generation == _generation) return pending.result;
    final result = _sendPower(true);
    _pendingPowerOn = (generation: _generation, result: result);
    try {
      return await result;
    } finally {
      if (identical(_pendingPowerOn?.result, result)) _pendingPowerOn = null;
    }
  }

  Future<void> startAppAuto() async {
    if (!canSend || appAutoPlaying) return;
    final favoritesOnly = appAutoFavorites;
    if (favoritesOnly && _effectFavorites.isEmpty) return;
    final catalog = List.generate(effectNames.length, (index) => index + 1);
    _beginPlayback(playing: true);
    final run = _playback;
    _appAutoPlaying = true;
    _refresh();
    if (!await _prepare(run, brightness)) return _stopCurrentPlayback(run);
    final duration = Duration(seconds: appAutoSeconds);
    var last = 0;
    Future<void> next() async {
      if (run != _playback || !canSend) return _stopCurrentPlayback(run);
      final ids = favoritesOnly ? (_effectFavorites.toList()..sort()) : catalog;
      if (ids.isEmpty) return _stopCurrentPlayback(run);
      final id = ids.where((id) => id > last).firstOrNull ?? ids.first;
      if (!await _sendEffect(id, 'effectNamed') || run != _playback) return _stopCurrentPlayback(run);
      _appAutoEffect = id;
      _appAutoStartedAt = _now();
      _appAutoStep++;
      last = id;
      _player = Timer(duration, () => unawaited(next()));
      _refresh();
    }
    await next();
  }

  void stopAppAuto() {
    if (appAutoPlaying) stopPlayback();
  }

  Future<bool> setEffect(int id, {bool preview = false}) async {
    if (!canSend || (id != wire.autoEffect && (id < 1 || id > 210))) return false;
    _beginPlayback(preview: preview);
    final run = _playback;
    if (!await _prepare(run, brightness)) return false;
    final label = id == wire.autoEffect ? 'autoCycle' : 'effectNamed';
    if (!await _sendEffect(id, label) || run != _playback) return false;
    if (!preview) {
      final fx = id == wire.autoEffect ? 'AUTO' : id;
      _select({'on': true, 'fx': fx, 'scene': null,
        'label': [label, {'id': id, 'name': effectName(id) ?? 'AUTO'}],
        'mode': {'effect': fx}});
    }
    return true;
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
    'effect' => effectName(item['effect'] as int) ?? text('effect'),
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

  Future<bool> _sendEffect(int id, String label) => _send(wire.effect(id), label,
      key: 'effect', values: {'id': id, 'name': effectName(id)}, onSent: () {
        _sentEffect = id;
        sentColor = null;
      });

  Future<bool> _sendStep(Fields step) {
    final effect = step['effect'] as int?;
    return effect == null ? _sendColor(step['rgb'] as List<int>) : _sendEffect(effect, 'effectNamed');
  }

  Future<void> applyShortcut(Fields item) async {
    if (!canSend) return;
    if (item['kind'] == 'effect') {
      final id = item['effect'];
      if (id is int && id >= 1 && id <= 210) await setEffect(id);
      return;
    }
    final preset = homePresets[item['preset']];
    final sequence = _sequence(item['id']);
    final rgb = item['rgb'] as List<int>?;
    final interval = preset == null ? null
        : (item['interval'] as int?)?.clamp(150, 2000) ?? preset.interval;
    final steps = preset != null ? colorSteps(preset.colors, interval!)
        : sequence?['steps'] as List<Fields>?;
    if (rgb == null && steps == null) return;
    _beginPlayback(sequence: sequence?['id'] as String?, playing: steps != null);
    final run = _playback;
    final intensity = preset != null ? 50 : sequence?['bri'] as int? ?? brightness;
    if (!await _prepare(run, intensity)) return _stopCurrentPlayback(run);
    if (rgb != null && await _sendColor(rgb) && run == _playback) {
      _select({...solidSelection(rgb), 'rgb': rgb, 'on': true});
    } else if (steps != null) {
      var index = 0;
      Future<void> next() async {
        if (run != _playback || !_foreground) return;
        final step = steps[index];
        final sent = await _sendStep(step);
        if (!sent || run != _playback) return _stopCurrentPlayback(run);
        index = (index + 1) % steps.length;
        _player = Timer(Duration(milliseconds: step['durationMs'] as int), () => unawaited(next()));
      }
      await next();
      if (_player != null && run == _playback) {
        _select({
          'on': true,
          'scene': preset != null ? item['preset'] : 'sequence:${item['id']}',
          'label': preset != null ? [item['preset']] : sequence!['name'],
          'mode': preset != null ? {'preset': item['preset'], 'interval': interval}
              : {'steps': steps},
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
      ({List<List<int>> colors, int interval, int intensity}) Function()? draft}) =>
    playSteps(colorSteps(colors, interval), intensity, preview: preview,
      draft: draft == null ? null : () {
        final live = draft();
        return (steps: colorSteps(live.colors, live.interval), intensity: live.intensity);
      });

  Future<void> playSteps(List<Fields> steps, int intensity, {bool preview = true,
      ({List<Fields> steps, int intensity}) Function()? draft}) async {
    if (!canSend || steps.isEmpty) return;
    _beginPlayback(preview: preview, playing: true);
    final run = _playback;
    final liveDraft = preview && draft != null;
    if (liveDraft) {
      if (sentPower != true && !await _preparePower()) return _stopCurrentPlayback(run);
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
      final live = draft?.call() ?? (steps: steps, intensity: intensity);
      if (live.steps.isEmpty || (!liveDraft && !await _prepare(run, live.intensity))) return _stopCurrentPlayback(run);
      final step = live.steps[index % live.steps.length];
      if (!await _sendStep(step) || run != _playback) return _stopCurrentPlayback(run);
      index++;
      _player = Timer(Duration(milliseconds: step['durationMs'] as int), () => unawaited(next()));
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
    if (_selection['scene'] == 'sequence:$id') {
      _select(solidSelection(_selection['rgb'] as List<int>));
    }
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
    final wasAppAuto = appAutoPlaying;
    _stopPlayback();
    previewing = preview;
    _playing = playing;
    _playingSequence = sequence;
    if (preview || wasAppAuto) _refresh();
  }

  void _stopPlayback() {
    _playback++;
    if (_playing || previewing) _sender.cancel();
    _playing = false;
    _playingSequence = null;
    _appAutoPlaying = false;
    _appAutoEffect = null;
    previewing = false;
    _player?.cancel();
    _player = null;
  }

  void startTimer(int seconds, {required bool fade}) {
    if (!ready || !_foreground || seconds <= 0 || seconds > maxTimerDuration) return;
    cancelTimer(restoreBrightness: true);
    _clearTimerOffFailure();
    remaining = _timerSpan = seconds;
    _timerFade = fade;
    _timerDeadline = _now() + seconds * 1000;
    _timerEndTime = _wallClock().toLocal().add(Duration(seconds: seconds));
    _lastTimerDuration = seconds;
    // Compare after earlier writes settle so a failed save can be retried.
    _timerDurationSave = _timerDurationSave.then((_) async {
      if (seconds == _savedTimerDuration) return;
      if (await saveTimerDuration(models.storage, seconds)) {
        _savedTimerDuration = seconds;
      } else {
        _notice('appStorageFailed');
      }
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tickTimer());
    _tickTimer();
    _refresh();
  }

  bool canExtendTimer(int seconds) =>
      remaining != null && seconds > 0 && seconds <= maxTimerDuration - _timerSpan;

  void extendTimer(int seconds) {
    final end = _timerEndTime;
    if (end == null || !canExtendTimer(seconds)) return;
    if (_timerDeadline <= _now()) {
      _tickTimer();
      return;
    }
    _timerDeadline += seconds * 1000;
    _timerEndTime = end.add(Duration(seconds: seconds));
    _timerSpan += seconds;
    _tickTimer();
  }

  void _tickTimer() {
    final left = (_timerDeadline - _now()) / 1000;
    if (left <= 0) {
      cancelTimer();
      _stopPlayback();
      unawaited(_powerOff(fromTimer: true));
      return;
    }
    // If an extension backs out of the fade window, restore the selected
    // brightness now; the same timer will fade again at its new deadline.
    final step = fadeBrightness(brightness, left, _timerFade);
    if (step != _fadeLevel) {
      _fadeLevel = step;
      unawaited(_sendBrightness(step ?? brightness));
    }
    if (remaining != left.ceil()) {
      remaining = left.ceil();
      _refresh();
    }
  }

  void cancelTimer({bool restoreBrightness = false}) {
    _timer?.cancel();
    if (remaining == null) return;
    remaining = null;
    _timerEndTime = null;
    final faded = _fadeLevel != null;
    _fadeLevel = null;
    if (faded && restoreBrightness) unawaited(_sendBrightness(brightness));
    _refresh();
  }

  String? _interruptedFadeDevice;

  void _interruptTimer() {
    if (_fadeLevel != null) _interruptedFadeDevice = link.strip?.id;
    cancelTimer();
  }

  void _restoreInterruptedFade() {
    if (!canSend || _disposed || _interruptedFadeDevice == null ||
        _interruptedFadeDevice != link.strip?.id) {
      return;
    }
    _interruptedFadeDevice = null;
    unawaited(_sendBrightness(brightness));
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _foregroundGeneration++;
      _generation++;
      if (!_disposed) link.cancelConnect();
      _interruptTimer();
      _stopPlayback();
      _sender.cancel();
      unawaited(stopScan());
    } else {
      _maybeRecover();
      _restoreInterruptedFade();
    }
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    setForeground(false);
    unawaited(_bluetoothChanges?.cancel());
    unawaited(link.dispose());
    super.dispose();
  }
}
