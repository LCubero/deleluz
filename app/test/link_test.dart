import 'dart:async';
import 'dart:typed_data';

import 'package:deleluz/link.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBle implements BleApi {
  int failConnects = 0;
  int connectCalls = 0;
  bool writable = true;
  final written = <String>[];
  final disconnected = <String>[];
  final connection = StreamController<(String, bool)>.broadcast();

  @override
  Future<void> connect(String id) async {
    connectCalls++;
    if (failConnects-- > 0) throw Exception('Connection attempt failed');
    open.add(id);
  }

  Completer<void>? discoveryGate;
  Completer<void>? disconnectGate;
  Object? discoveryError;
  bool failDisconnect = false;
  final open = <String>{};

  @override
  Future<bool> hasWriteWithoutResponse(String id) async {
    await discoveryGate?.future;
    if (discoveryError != null) throw discoveryError!;
    return writable;
  }

  @override
  Future<void> write(String id, Uint8List bytes) async => written.add('$id:${bytes.first}');

  @override
  Future<void> disconnect(String id) async {
    await disconnectGate?.future;
    if (failDisconnect) throw StateError('Release failed');
    disconnected.add(id);
    open.remove(id);
  }

  @override
  Stream<(String, bool)> get connectionChanges => connection.stream;

  @override
  Stream<Strip> scan() => Stream.fromIterable([const Strip('A', 'LEDDMX-03-TEST')]);

  @override
  Future<void> stopScan() async {}
}

void main() {
  late FakeBle ble;
  late Link link;
  late List<String?> saved;

  setUp(() {
    ble = FakeBle();
    saved = [];
    link = Link(ble, retryDelay: Duration.zero, onRemember: saved.add);
  });

  test('connects after up to 4 tries and remembers the strip', () async {
    ble.failConnects = 3;
    await link.connect(const Strip('A', 'LEDDMX-03-TEST'));
    expect(ble.connectCalls, 4);
    expect(link.status, LinkStatus.connected);
    expect(link.strip?.id, 'A');
    expect(saved, ['A']);
  });

  test('gives up after 4 failed tries and stays idle', () async {
    ble.failConnects = 4;
    await expectLater(link.connect(const Strip('A', 'x')), throwsException);
    expect(ble.connectCalls, 4);
    expect(link.status, LinkStatus.idle);
    expect(saved, isEmpty);
  });

  test('rejects a controller without write-without-response and releases it', () async {
    ble.writable = false;
    await expectLater(link.connect(const Strip('A', 'x')), throwsA(isA<UnsupportedController>()));
    expect(ble.disconnected, ['A']);
    expect(link.status, LinkStatus.idle);
  });

  test('write fails when not connected', () async {
    await expectLater(link.write(Uint8List.fromList([1])), throwsStateError);
    expect(ble.written, isEmpty);
  });

  test('a dropped link becomes lost; reconnect uses the same strip', () async {
    await link.connect(const Strip('A', 'x'));
    ble.connection.add(('A', false));
    await Future<void>.delayed(Duration.zero);
    expect(link.status, LinkStatus.lost);
    await link.reconnect();
    expect(link.status, LinkStatus.connected);
    await link.write(Uint8List.fromList([7]));
    expect(ble.written, ['A:7']);
  });

  test('switching strips releases the previous one first', () async {
    await link.connect(const Strip('A', 'x'));
    await link.connect(const Strip('B', 'y'));
    expect(ble.disconnected, ['A']);
    expect(link.strip?.id, 'B');
  });

  for (final switching in [true, false]) {
    test('${switching ? 'switch' : 'manual disconnect'} failure keeps the old strip and allows retry', () async {
      const a = Strip('A', 'x');
      const b = Strip('B', 'y');
      await link.connect(a);
      ble.failDisconnect = true;
      await expectLater(switching ? link.connect(b) : link.disconnect(), throwsStateError);
      expect(link.status, LinkStatus.connected);
      expect(link.strip, a);
      expect(ble.open, {'A'});
      expect(ble.connectCalls, 1);
      ble.failDisconnect = false;
      await link.connect(b);
      expect(link.status, LinkStatus.connected);
      expect(link.strip, b);
      expect(ble.open, {'B'});
    });
  }

  test('disconnect is deliberate (idle, not lost) and forget clears memory', () async {
    await link.connect(const Strip('A', 'x'));
    await link.disconnect();
    expect(link.status, LinkStatus.idle);
    await link.forget();
    expect(link.strip, isNull);
    expect(saved, ['A', null]);
  });

  test('forget during discovery releases the strip and does not remember it again', () async {
    ble.discoveryGate = Completer();
    final pending = link.connect(const Strip('A', 'x'));
    await Future<void>.delayed(Duration.zero);
    await link.forget();
    ble.discoveryGate!.complete();
    await pending;
    expect(ble.open, isEmpty);
    expect(link.strip, isNull);
    expect(link.ready, isFalse);
    expect(saved, [null]);
  });

  test('overlapping switches leave at most one strip open', () async {
    await link.connect(const Strip('A', 'x'));
    ble.disconnectGate = Completer();
    final toB = link.connect(const Strip('B', 'y'));
    final toC = link.connect(const Strip('C', 'z'));
    ble.disconnectGate!.complete();
    await Future.wait([toB, toC]);
    expect(ble.open, {'B'});
    expect(link.strip?.id, 'B');
  });

  test('a discovery error releases the connected strip', () async {
    ble.discoveryError = Exception('discovery failed');
    await expectLater(link.connect(const Strip('A', 'x')), throwsException);
    expect(ble.disconnected, ['A']);
    expect(ble.open, isEmpty);
    expect(link.status, LinkStatus.idle);
  });

  test('a failed recovery keeps the link lost', () async {
    await link.connect(const Strip('A', 'x'));
    ble.connection.add(('A', false));
    await Future<void>.delayed(Duration.zero);
    ble.failConnects = 4;
    await expectLater(link.reconnect(), throwsException);
    expect(link.status, LinkStatus.lost);
  });
}
