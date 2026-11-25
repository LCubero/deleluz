// Throttled BLE write queue, same behavior as webapp/sender.js: writes are spaced by
// `interval`; a frame with a key replaces the unsent frame with the same key (latest
// wins), so dragging a slider never builds a backlog.
import 'dart:async';
import 'dart:typed_data';

class _Item {
  _Item(this.bytes, this.key);
  Uint8List bytes;
  final String? key;
  Completer<String> done = Completer<String>();
}

class Sender {
  Sender({
    required this.write,
    this.interval = 50,
    double Function()? now,
    Future<void> Function(double ms)? sleep,
  })  : _now = now ?? _clock,
        _sleep = sleep ??
            ((ms) => Future.delayed(Duration(microseconds: (ms * 1000).round())));

  final Future<void> Function(Uint8List bytes) write;
  final double interval;
  final double Function() _now;
  final Future<void> Function(double ms) _sleep;

  static final _watch = Stopwatch()..start();
  static double _clock() => _watch.elapsedMicroseconds / 1000;

  List<_Item> _pending = [];
  bool _running = false;
  double _nextAt = double.negativeInfinity;

  int get size => _pending.length;

  Future<String> send(Uint8List bytes, {String? key}) {
    if (key != null) {
      final index = _pending.indexWhere((item) => item.key == key);
      if (index >= 0) {
        final old = _pending[index];
        old.done.complete('replaced');
        final item = _Item(bytes, key);
        _pending[index] = item;
        return item.done.future;
      }
    }
    final item = _Item(bytes, key);
    _pending.add(item);
    if (!_running) _drain();
    return item.done.future;
  }

  void cancel() {
    final dropped = _pending;
    _pending = [];
    for (final item in dropped) {
      item.done.complete('canceled');
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        // Timers may wake early; recheck the deadline before writing.
        for (var wait = _nextAt - _now(); wait > 0; wait = _nextAt - _now()) {
          await _sleep(wait);
        }
        if (_pending.isEmpty) break;
        final item = _pending.removeAt(0);
        _nextAt = _now() + interval;
        try {
          await write(item.bytes);
          item.done.complete('sent');
        } catch (error, stack) {
          item.done.completeError(error, stack);
        }
      }
    } finally {
      _running = false;
    }
  }
}
