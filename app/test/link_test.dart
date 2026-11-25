import 'dart:async';
import 'dart:typed_data';

import 'package:deleluz/link.dart';
import 'package:deleluz/sender.dart';
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
    await connectGate?.future;
    open.add(id);
  }

  Completer<void>? connectGate;
  Completer<void>? writeGate;
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
  Future<void> write(String id, Uint8List bytes) async {
    await writeGate?.future;
    written.add('$id:${bytes.first}');
  }

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

class ThrowingCancelBle extends FakeBle {
  final throwingChanges = StreamController<(String, bool)>(
      onCancel: () => throw StateError('Subscription cancellation failed'));

  @override
  Stream<(String, bool)> get connectionChanges => throwingChanges.stream;
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

  testWidgets('F2 stalled open times out and a different strip can connect', (tester) async {
    final gate = ble.connectGate = Completer<void>();
    Object? failure;
    final opening = link.connect(const Strip('A', 'x')).catchError((Object error) {
      failure = error;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(failure, isA<TimeoutException>());
    await opening;
    ble.connectGate = null;
    await link.connect(const Strip('B', 'x'));
    gate.complete();
    await tester.pump();
    expect(ble.open, {'B'});
    expect(saved, ['B']);
  });

  testWidgets('G1 stalled write drops the queued frame before late completion', (tester) async {
    late Sender sender;
    link = Link(ble, onChange: () {
      if (!link.ready) sender.cancel();
    });
    var now = 0.0;
    sender = Sender(write: link.write, now: () => now);
    await link.connect(const Strip('A', 'x'));
    final gate = ble.writeGate = Completer<void>();
    Object? failure;
    final writing = sender.send(Uint8List.fromList([1])).catchError((Object error) {
      failure = error;
      return 'failed';
    });
    final next = sender.send(Uint8List.fromList([2]));
    ble.writeGate = null;
    now = 2000;
    await tester.pump(const Duration(seconds: 2));
    expect(failure, isA<TimeoutException>());
    expect(await writing, 'failed');
    final beforeLateWrite = List.of(ble.written);
    gate.complete();
    await tester.pump();
    expect(ble.written, ['A:1']);
    expect(beforeLateWrite, isEmpty);
    expect(await next, 'canceled');
    expect(link.status, LinkStatus.lost);
    expect(ble.open, isEmpty);
  });

  testWidgets('F2 stalled discovery releases the link without remembering it', (tester) async {
    final gate = ble.discoveryGate = Completer<void>();
    Object? failure;
    final opening = link.connect(const Strip('A', 'x')).catchError((Object error) {
      failure = error;
    });
    await tester.pump();
    expect(ble.open, {'A'});
    await tester.pump(const Duration(seconds: 10));
    expect(failure, isA<TimeoutException>());
    await opening;
    expect(saved, isEmpty);
    expect(ble.open, isEmpty);
    gate.complete();
  });

  test('F1 disposing releases an owned connection', () async {
    await link.connect(const Strip('A', 'x'));
    await link.dispose();
    expect(ble.open, isEmpty);
  });

  test('G3 disposal retries a timed-out deliberate release', () async {
    await link.connect(const Strip('A', 'x'));
    final gate = ble.disconnectGate = Completer<void>();
    final releasing = expectLater(link.disconnect(), throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    final disposing = link.dispose();
    ble.disconnectGate = null;
    try {
      await releasing;
      await disposing;
      expect(ble.open, isEmpty);
      expect(ble.disconnected, ['A']);
    } finally {
      gate.complete();
    }
  });

  test('dispose releases the owned link even when subscription cancellation throws', () async {
    final transport = ThrowingCancelBle();
    final owned = Link(transport);
    await owned.connect(const Strip('A', 'x'));
    await owned.dispose();
    expect(transport.open, isEmpty);
    expect(transport.disconnected, ['A']);
  });

  test('F1 disposing during discovery releases the late open', () async {
    final gate = ble.discoveryGate = Completer<void>();
    final opening = link.connect(const Strip('A', 'x'));
    await Future<void>.delayed(Duration.zero);
    final disposing = link.dispose();
    gate.complete();
    await opening;
    await disposing;
    expect(ble.open, isEmpty);
    expect(saved, isEmpty);
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
      expect(link.status, LinkStatus.idle);
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
