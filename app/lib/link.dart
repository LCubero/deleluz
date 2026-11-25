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
      if (up || id != strip?.id) return;
      if (status == LinkStatus.connected) _set(LinkStatus.lost);
      if (status == LinkStatus.connecting || _releasing != null) _droppedWhileOpening = true;
    });
  }

  final BleApi _ble;
  final Duration retryDelay;
  final void Function(String? id)? onRemember;
  final void Function()? onChange;
  late final StreamSubscription<(String, bool)> _sub;

  static const maxTries = 4;

  // Bumped by every connect/cancel/forget; a pending open that finds it changed is stale and
  // releases whatever it opened, so only one strip is ever held.
  int _generation = 0;
  bool _droppedWhileOpening = false;
  Future<void>? _releasing;
  Future<void>? _opening;
  LinkStatus? _cancelFallback;

  LinkStatus status = LinkStatus.idle;
  Strip? strip;

  bool get ready => status == LinkStatus.connected;

  void _set(LinkStatus next) {
    status = next;
    onChange?.call();
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
    if (status == LinkStatus.connecting || (ready && strip?.id == target.id)) return;
    final generation = ++_generation;
    final previous = _opening;
    final drained = Completer<void>();
    _opening = drained.future;
    _cancelFallback = fallback;
    final wasReady = ready;
    _set(LinkStatus.connecting);
    try {
      // A canceled native open still owns the transport until its late result is cleaned up.
      if (previous != null) await previous;
      if (generation != _generation) return;
      if (wasReady || ready) {
        if (strip?.id == target.id) {
          _set(LinkStatus.connected);
          return;
        }
        await _release();
      }
      if (generation != _generation) return;
      strip = target;
      await _open(generation, fallback);
    } catch (_) {
      if (generation == _generation) rethrow;
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
          await _ble.connect(id);
          opened = true;
          break;
        } catch (_) {
          if (generation != _generation) return;
          if (attempt >= maxTries) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
      if (!opened) return;
      if (generation != _generation) return;
      if (!await _ble.hasWriteWithoutResponse(id)) throw UnsupportedController();
      if (generation != _generation) return;
      if (_droppedWhileOpening) throw StateError('Link dropped while opening');
      _set(LinkStatus.connected);
      onRemember?.call(id);
    } catch (_) {
      if (generation == _generation) rethrow;
    } finally {
      if (opened && !(generation == _generation && ready)) {
        try {
          await _ble.disconnect(id);
        } catch (_) {/* Preserve the original error, or silently finish canceling. */}
      }
      if (generation == _generation && !ready) _set(fallback);
    }
  }

  Future<void> write(Uint8List bytes) async {
    if (!ready) throw StateError('Not connected');
    await _ble.write(strip!.id, bytes);
  }

  Future<void> _release() async {
    final id = strip!.id;
    _droppedWhileOpening = false;
    final release = Future<void>.microtask(() => _ble.disconnect(id));
    _releasing = release;
    _set(LinkStatus.connecting);
    try {
      await release;
    } catch (_) {
      _set(_droppedWhileOpening ? LinkStatus.lost : LinkStatus.connected);
      rethrow;
    } finally {
      _releasing = null;
    }
  }

  /// Releases the strip on purpose, so another phone or app can connect.
  Future<void> disconnect() async {
    if (!ready) return;
    await _release();
    _set(LinkStatus.idle);
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

  Future<void> dispose() => _sub.cancel();
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
