// BLE link to one LEDDMX controller at a time (GATT FFE0/FFE1, write without response).
// Same rules as webapp/ble.js: up to 4 connect tries 300 ms apart (lab: about half of
// first connects fail), a deliberate disconnect is not a lost link, and the app only
// knows what it sent: the controller reports no state back (docs/CAPABILITIES.md).
import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

const serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const writeUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
const namePrefix = 'LEDDMX';

class Strip {
  const Strip(this.id, this.name);
  final String id;
  final String name;
}

enum LinkStatus { idle, connecting, connected, lost }

class UnsupportedController implements Exception {
  @override
  String toString() => 'This controller does not accept commands (FFE1).';
}

/// The few BLE operations the link needs; faked in tests.
abstract class BleApi {
  Stream<Strip> scan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<bool> hasWriteWithoutResponse(String id);
  Future<void> write(String id, Uint8List bytes);
  Future<void> disconnect(String id);
  Stream<(String, bool)> get connectionChanges;
}

class Link {
  Link(this._ble, {this.retryDelay = const Duration(milliseconds: 300), this.onRemember, this.onChange}) {
    _sub = _ble.connectionChanges.listen((change) {
      final (id, up) = change;
      if (up) return;
      if (id == _ownedId) _ownedId = null;
      if (id != strip?.id || _releasing != null) return;
      if (status == LinkStatus.connected) _set(LinkStatus.lost);
      if (status == LinkStatus.connecting) _droppedWhileOpening = true;
    });
  }

  final BleApi _ble;
  final Duration retryDelay;
  final void Function(String? id)? onRemember;
  final void Function()? onChange;
  late final StreamSubscription<(String, bool)> _sub;

  static const maxTries = 4;
  static const _openDeadline = Duration(seconds: 10);
  static const _ioDeadline = Duration(seconds: 2);

  // Bumped by every connect/cancel/forget; a pending open that finds it changed is stale and
  // releases whatever it opened, so only one strip is ever held.
  int _generation = 0;
  bool _disposed = false;
  bool _droppedWhileOpening = false;
  // Keep native ownership until a release succeeds or the transport reports loss.
  String? _ownedId;
  Future<void>? _releasing;
  Future<void>? _opening;
  LinkStatus? _cancelFallback;

  LinkStatus status = LinkStatus.idle;
  Strip? strip;

  bool get ready => status == LinkStatus.connected;

  void _set(LinkStatus next) {
    status = next;
    if (!_disposed) onChange?.call();
  }

  /// Restores a remembered strip without connecting.
  void restore(Strip remembered) => strip = remembered;

  Future<void> connect(Strip target) => _connect(target, LinkStatus.idle);

  Future<void> reconnect() async {
    final target = strip;
    if (target == null || ready) return;
    await _connect(target, status);
  }

  void cancelConnect() {
    final fallback = _cancelFallback;
    if (fallback == null) return;
    _cancelFallback = null;
    _generation++;
    _set(fallback);
  }

  Future<void> _connect(Strip target, LinkStatus fallback) async {
    if (_disposed || status == LinkStatus.connecting || (ready && strip?.id == target.id)) return;
    final generation = ++_generation;
    final previous = _opening;
    final drained = Completer<void>();
    _opening = drained.future;
    _cancelFallback = fallback;
    _set(LinkStatus.connecting);
    try {
      // A canceled native open still owns the transport until its late result is cleaned up.
      if (previous != null) await previous;
      if (_releasing != null) await _waitForRelease();
      if (generation != _generation) return;
      if (_ownedId != null) await _release();
      if (generation != _generation) return;
      strip = target;
      await _open(generation, fallback);
    } catch (_) {
      if (generation == _generation) {
        if (status == LinkStatus.connecting) _set(fallback);
        rethrow;
      }
    } finally {
      if (generation == _generation) _cancelFallback = null;
      if (identical(_opening, drained.future)) _opening = null;
      drained.complete();
    }
  }

  /// [fallback] is the status after a failed open: a failed recovery stays `lost`.
  Future<void> _open(int generation, LinkStatus fallback) async {
    final id = strip!.id;
    _droppedWhileOpening = false;
    var opened = false;
    try {
      for (var attempt = 1; generation == _generation; attempt++) {
        try {
          await _connectNative(id);
          opened = true;
          break;
        } catch (error) {
          if (generation != _generation) return;
          if (error is TimeoutException || attempt >= maxTries) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
      if (!opened) return;
      if (generation != _generation) return;
      if (!await _ble.hasWriteWithoutResponse(id).timeout(_openDeadline)) throw UnsupportedController();
      if (generation != _generation) return;
      if (_droppedWhileOpening) throw StateError('Link dropped while opening');
      _ownedId = id;
      _set(LinkStatus.connected);
      onRemember?.call(id);
    } catch (_) {
      if (generation == _generation) rethrow;
    } finally {
      if (opened && !(generation == _generation && ready)) {
        await _releaseQuietly(id);
      }
      if (generation == _generation && !ready) _set(fallback);
    }
  }

  Future<void> _connectNative(String id) async {
    final native = _ble.connect(id);
    await native.timeout(_openDeadline, onTimeout: () {
      // A timeout cannot cancel the platform operation. A late connection
      // must not disconnect a newer session using the same device.
      unawaited(native.then((_) async {
        if (strip?.id == id && status == LinkStatus.connecting) await _opening;
        if (!ready || strip?.id != id) await _releaseQuietly(id);
      }, onError: (Object _) {}));
      throw TimeoutException('BLE connect timed out', _openDeadline);
    });
  }

  Future<void> _releaseQuietly(String id) async {
    try {
      await _ble.disconnect(id).timeout(_ioDeadline);
    } catch (_) {
      // Preserve the original failure; cleanup is best effort.
    }
  }

  Future<void> write(Uint8List bytes) async {
    if (!ready) throw StateError('Not connected');
    final generation = _generation;
    await _ble.write(strip!.id, bytes).timeout(_ioDeadline, onTimeout: () {
      if (generation == _generation && ready) {
        // Publish loss before the sender can drain another frame. Recovery
        // waits for the bounded disconnect before opening a fresh session.
        unawaited(_release(lost: true).catchError((Object _) {}));
      }
      throw TimeoutException('BLE write timed out', _ioDeadline);
    });
  }

  Future<void> _release({bool lost = false}) async {
    final id = _ownedId!;
    final release = Future<void>.microtask(() => _ble.disconnect(id)).timeout(_ioDeadline);
    _releasing = release;
    _set(lost ? LinkStatus.lost : LinkStatus.connecting);
    try {
      await release;
      if (_ownedId == id) _ownedId = null;
    } finally {
      _releasing = null;
    }
  }

  Future<void> _waitForRelease() async {
    try {
      await _releasing;
    } catch (_) {
      // Keep the owned id so the caller can retry cleanup.
    }
  }

  /// Releases the strip on purpose, so another phone or app can connect.
  Future<void> disconnect() async {
    if (status == LinkStatus.connecting || _ownedId == null) return;
    final generation = _generation;
    try {
      if (_releasing != null) await _waitForRelease();
      if (generation == _generation && _ownedId != null) await _release();
    } finally {
      if (generation == _generation) _set(LinkStatus.idle);
    }
  }

  Future<void> forget() async {
    final releasing = _releasing;
    if (releasing != null) await releasing;
    if (ready) await disconnect();
    _generation++; // Invalidates a pending open; it releases the strip itself.
    _cancelFallback = null;
    strip = null;
    _set(LinkStatus.idle);
    onRemember?.call(null);
  }

  void radioOff() {
    _generation++;
    _cancelFallback = null;
    _ownedId = null;
    _set(strip == null ? LinkStatus.idle : LinkStatus.lost);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final opening = _opening;
    _generation++;
    _cancelFallback = null;
    _set(LinkStatus.idle);
    try {
      await _sub.cancel();
    } catch (_) {
      // Subscription cleanup must not prevent releasing the owned link.
    }
    await _waitForRelease();
    if (opening != null) await opening;
    final owned = _ownedId;
    _ownedId = null;
    if (owned != null) await _releaseQuietly(owned);
  }
}

/// Production adapter over universal_ble (BSD 3-Clause).
class UniversalBleApi implements BleApi {
  @override
  Stream<Strip> scan() {
    UniversalBle.startScan(scanFilter: ScanFilter(withNamePrefix: [namePrefix]));
    return UniversalBle.scanStream
        .where((d) => (d.name ?? '').startsWith(namePrefix))
        .map((d) => Strip(d.deviceId, d.name!));
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String id) => UniversalBle.connect(id, timeout: const Duration(seconds: 10));

  @override
  Future<bool> hasWriteWithoutResponse(String id) async {
    final services = await UniversalBle.discoverServices(id);
    for (final service in services) {
      if (service.uuid.toLowerCase() != serviceUuid) continue;
      for (final c in service.characteristics) {
        if (c.uuid.toLowerCase() == writeUuid) {
          return c.properties.contains(CharacteristicProperty.writeWithoutResponse);
        }
      }
    }
    return false;
  }

  @override
  Future<void> write(String id, Uint8List bytes) =>
      UniversalBle.write(id, serviceUuid, writeUuid, bytes, withoutResponse: true);

  @override
  Future<void> disconnect(String id) => UniversalBle.disconnect(id);

  @override
  Stream<(String, bool)> get connectionChanges {
    final controller = StreamController<(String, bool)>.broadcast();
    UniversalBle.onConnectionChange = (change) => controller.add((change.deviceId, change.isConnected));
    return controller.stream;
  }
}
