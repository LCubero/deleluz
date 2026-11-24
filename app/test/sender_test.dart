import 'dart:typed_data';

import 'package:deleluz/sender.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List b(int v) => Uint8List.fromList([v]);

void main() {
  late List<int> written;
  late double clock;
  late List<double> sleeps;
  late Sender sender;

  setUp(() {
    written = [];
    clock = 0;
    sleeps = [];
    sender = Sender(
      write: (bytes) async => written.add(bytes.first),
      interval: 50,
      now: () => clock,
      sleep: (ms) async {
        sleeps.add(ms);
        clock += ms;
      },
    );
  });

  test('spaces writes by the interval and sends in order', () async {
    final results = await Future.wait([sender.send(b(1)), sender.send(b(2)), sender.send(b(3))]);
    expect(written, [1, 2, 3]);
    expect(results, ['sent', 'sent', 'sent']);
    expect(sleeps, [50, 50]);
  });

  test('a keyed frame replaces the unsent frame with the same key', () async {
    final first = sender.send(b(1));
    final a = sender.send(b(2), key: 'brightness');
    final c = sender.send(b(3), key: 'brightness');
    expect(await Future.wait([first, a, c]), ['sent', 'replaced', 'sent']);
    expect(written, [1, 3]);
  });

  test('cancel drops pending frames as canceled', () async {
    final first = sender.send(b(1));
    final second = sender.send(b(2));
    sender.cancel();
    expect(await Future.wait([first, second]), ['sent', 'canceled']);
    expect(written, [1]);
    expect(sender.size, 0);
  });

  test('a write error rejects only that frame', () async {
    var calls = 0;
    sender = Sender(
      write: (bytes) async {
        if (calls++ == 0) throw StateError('Not connected');
        written.add(bytes.first);
      },
      interval: 50,
      now: () => clock,
      sleep: (ms) async => clock += ms,
    );
    final failed = sender.send(b(1));
    final ok = sender.send(b(2));
    await expectLater(failed, throwsStateError);
    expect(await ok, 'sent');
    expect(written, [2]);
  });
}
