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
      if (!up && id == strip?.id && status == LinkStatus.connected) _set(LinkStatus.lost);
    });
  }

  final BleApi _ble;
  final Duration retryDelay;
  final void Function(String? id)? onRemember;
  final void Function()? onChange;
  late final StreamSubscription<(String, bool)> _sub;

  static const maxTries = 4;

  LinkStatus status = LinkStatus.idle;
  Strip? strip;

  bool get ready => status == LinkStatus.connected;

  void _set(LinkStatus next) {
    status = next;
    onChange?.call();
  }

  /// Restores a remembered strip without connecting.
  void restore(Strip remembered) => strip = remembered;

  Future<void> connect(Strip target) async {
    if (status == LinkStatus.connecting) return;
    final previous = strip;
    if (previous != null && previous.id != target.id && status == LinkStatus.connected) {
      await _ble.disconnect(previous.id);
    }
    strip = target;
    await _open();
  }

  Future<void> reconnect() async {
    if (strip == null || status == LinkStatus.connecting || status == LinkStatus.connected) return;
    await _open();
  }

  Future<void> _open() async {
    final id = strip!.id;
    _set(LinkStatus.connecting);
    try {
      for (var attempt = 1;; attempt++) {
        try {
          await _ble.connect(id);
          break;
        } catch (_) {
          if (attempt >= maxTries) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
      if (!await _ble.hasWriteWithoutResponse(id)) {
        await _ble.disconnect(id);
        throw UnsupportedController();
      }
      _set(LinkStatus.connected);
      onRemember?.call(id);
    } catch (_) {
      _set(LinkStatus.idle);
      rethrow;
    }
  }

  Future<void> write(Uint8List bytes) async {
    if (!ready) throw StateError('Not connected');
    await _ble.write(strip!.id, bytes);
  }

  /// Releases the strip on purpose, so another phone or app can connect.
  Future<void> disconnect() async {
    if (status != LinkStatus.connected) return;
    _set(LinkStatus.idle);
    await _ble.disconnect(strip!.id);
  }

  Future<void> forget() async {
    await disconnect();
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
