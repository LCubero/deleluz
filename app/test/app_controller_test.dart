import 'dart:async';
import 'dart:typed_data';

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/link.dart' show LinkStatus;
import 'package:deleluz/model/models.dart' show Models;
import 'package:deleluz/protocol.dart' as wire;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' show AvailabilityState;

import 'ui/home_test.dart' show FakeBle, Store;

class DroppingReleaseBle extends FakeBle {
  @override
  Future<void> disconnect(String id) async {
    changes.add((id, false));
    await Future<void>.value();
    throw StateError('Release failed after loss');
  }
}

class StalledReleaseBle extends FakeBle {
  final release = Completer<void>();

  @override
  Future<void> disconnect(String id) => release.future;
}

class StalledTimerOffBle extends FakeBle {
  final stalled = Completer<void>();
  int offAttempts = 0;

  @override
  Future<void> write(String id, Uint8List bytes) {
    if (bytes.toString() == wire.power(false).toString() && ++offAttempts == 1) {
      return stalled.future;
    }
    return super.write(id, bytes);
  }
}

class RefusingShortcutStore extends Store {
  @override
  Future<bool> write(String key, String? value) async {
    if (key == Models.shortcutsKey) return false;
    return super.write(key, value);
  }
}

void main() {
  late FakeBle ble;
  late AppController c;
  late double now;
  const colors = [[255, 0, 0], [0, 255, 0]];

  setUp(() {
    ble = FakeBle();
    now = 0;
    c = AppController(ble, Store(), checkAccess: (_) async => null, now: () => now);
    addTearDown(ble.changes.close);
    addTearDown(c.dispose);
  });

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      now += 50;
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<int> effectFrame(int id) => [0x7b, 0xff, 3, id, 255, 255, 255, 255, 0xbf];

  testWidgets('effect shortcut sends the selected built-in effect frame', (tester) async {
    await c.connect(FakeBle.strip);
    final sending = c.applyShortcut({'kind': 'effect', 'effect': 210});
    await drain(tester);
    await sending;
    expect(ble.writes.lastOrNull, effectFrame(210));
    expect(c.hasActiveEffect, isTrue);
  });

  Future<void> advance(WidgetTester tester, int ms) async {
    now += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  Future<void> startAuto(WidgetTester tester) async {
    final start = c.startAppAuto();
    await drain(tester);
    await start;
  }

  testWidgets('F1 background invalidates a pending open', (tester) async {
    final gate = Completer<void>();
    ble.opening = gate.future;
    final opening = c.connect(FakeBle.strip);
    await tester.pump();
    expect(ble.connections, [FakeBle.strip.id]);
    c.setForeground(false);
    gate.complete();
    await opening;
    expect(c.ready, isFalse);
    expect(ble.disconnects, [FakeBle.strip.id]);
  });

  testWidgets('F1 controller disposal invalidates a pending native open', (tester) async {
    final controller = AppController(ble, Store(), checkAccess: (_) async => null);
    final gate = Completer<void>();
    ble.opening = gate.future;
    final opening = controller.connect(FakeBle.strip);
    await tester.pump();
    expect(ble.connections, [FakeBle.strip.id]);
    controller.dispose();
    gate.complete();
    await opening;
    expect(ble.disconnects, [FakeBle.strip.id]);
    expect(controller.remembered, isNull);
  });

  testWidgets('F3 failed deliberate release does not queue recovery', (tester) async {
    final releasing = DroppingReleaseBle();
    final controller = AppController(releasing, Store(), checkAccess: (_) async => null);
    addTearDown(releasing.changes.close);
    addTearDown(controller.dispose);
    await controller.connect(FakeBle.strip);
    await controller.disconnect();
    await tester.pump();
    expect(controller.link.status, LinkStatus.idle);
    expect(releasing.connections, [FakeBle.strip.id]);
  });

  for (final forget in [false, true]) {
    testWidgets('G2 late loss after ${forget ? 'forget' : 'disconnect'} timeout does not recover', (tester) async {
      final stalled = StalledReleaseBle();
      final controller = AppController(stalled, Store(), checkAccess: (_) async => null);
      addTearDown(stalled.changes.close);
      addTearDown(controller.dispose);
      await controller.connect(FakeBle.strip);
      final release = forget ? controller.forgetStrip(FakeBle.strip.id) : controller.disconnect();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await release;
      stalled.release.complete();
      stalled.changes.add((FakeBle.strip.id, false));
      await tester.pump();
      expect(stalled.connections, [FakeBle.strip.id]);
      expect(controller.link.status, LinkStatus.idle);
    });
  }

  testWidgets('F3 rapid repeated link loss needs manual recovery', (tester) async {
    final controller = AppController(ble, Store(), checkAccess: (_) async => null,
        now: () => now);
    addTearDown(controller.dispose);
    await controller.connect(FakeBle.strip);
    ble.changes.add((FakeBle.strip.id, false));
    await tester.pump();
    expect(ble.connections, hasLength(2));
    expect(controller.ready, isTrue);
    ble.changes.add((FakeBle.strip.id, false));
    await tester.pump();
    expect(ble.connections, hasLength(2));
    expect(controller.ready, isFalse);
    await controller.reconnect();
    expect(controller.ready, isTrue);
  });

  testWidgets('F4 radio off tears down without a link-loss event', (tester) async {
    final radio = StreamController<AvailabilityState>();
    final controller = AppController(ble, Store(), checkAccess: (_) async => null,
        bluetoothChanges: radio.stream, now: () => now);
    addTearDown(radio.close);
    addTearDown(controller.dispose);
    await controller.connect(FakeBle.strip);
    controller.startTimer(60, fade: false);
    radio.add(AvailabilityState.poweredOff);
    await tester.pump();
    expect(controller.ready, isFalse);
    expect(controller.link.status, LinkStatus.lost);
    expect(controller.remaining, isNull);
    radio.add(AvailabilityState.poweredOff);
    await tester.pump();
    expect(ble.connections, [FakeBle.strip.id]);
  });

  testWidgets('F5 interrupted fade restores brightness after foreground returns', (tester) async {
    await c.connect(FakeBle.strip);
    c.startTimer(30, fade: true);
    await drain(tester);
    expect(c.sentBrightness, isNot(c.brightness));
    c.setForeground(false);
    c.setForeground(true);
    await drain(tester);
    expect(c.sentBrightness, c.brightness);
  });

  testWidgets('F5 failed timer OFF can be retried without starting another timer', (tester) async {
    await c.connect(FakeBle.strip);
    ble.failWrite = (bytes) => bytes.toString() == wire.power(false).toString();
    c.startTimer(1, fade: false);
    await advance(tester, 1000);
    expect(c.message, 'timerOffFailed');
    expect(c.remaining, isNull);
    ble.failWrite = null;
    final retry = c.retryTimerOff();
    await drain(tester);
    await retry;
    expect(ble.writes.last, wire.power(false));
    expect(c.message, isNull);
    expect(c.remaining, isNull);
  });

  for (final dropBeforeTimeout in [false, true]) {
    testWidgets('final timer OFF ${dropBeforeTimeout ? 'loses link' : 'times out'}; retry after reconnect sends OFF once', (tester) async {
      final transport = StalledTimerOffBle();
      final automaticAccess = Completer<String?>();
      final controller = AppController(transport, Store(),
          checkAccess: (request) async => request ? null : automaticAccess.future,
          now: () => now);
      addTearDown(transport.changes.close);
      addTearDown(controller.dispose);
      await controller.connect(FakeBle.strip);
      var warnings = 0;
      String? previous;
      controller.addListener(() {
        if (controller.message == 'timerOffFailed' && previous != controller.message) warnings++;
        previous = controller.message;
      });
      controller.startTimer(1, fade: false);
      await advance(tester, 1000);
      expect(transport.offAttempts, 1);
      if (dropBeforeTimeout) {
        transport.changes.add((FakeBle.strip.id, false));
        await tester.pump();
        transport.stalled.complete();
        await tester.pump();
      } else {
        await advance(tester, 2000);
        transport.stalled.complete();
      }
      expect(controller.message, 'timerOffFailed');
      expect(controller.remaining, isNull);
      expect(controller.canRetryTimerOff, isFalse);
      await controller.retryTimerOff();
      expect(transport.offAttempts, 1);
      automaticAccess.complete('connectFailed');
      await tester.pump();
      await controller.reconnect();
      expect(controller.canRetryTimerOff, isTrue);
      final retry = controller.retryTimerOff();
      expect(controller.canRetryTimerOff, isFalse);
      await controller.retryTimerOff();
      await drain(tester);
      await retry;
      expect(transport.offAttempts, 2);
      expect(transport.writes, [wire.power(false)]);
      expect(controller.message, isNull);
      expect(warnings, 1);
    });
  }

  testWidgets('F6 rapid colors share power preparation and send the latest color', (tester) async {
    await c.connect(FakeBle.strip);
    final sends = [for (final rgb in colors) c.applyShortcut({'kind': 'color', 'rgb': rgb})];
    await drain(tester);
    await Future.wait(sends);
    expect(ble.writes.where((bytes) => bytes.toString() == wire.power(true).toString()), hasLength(1));
    expect(ble.writes.last, wire.color(0, 255, 0));
    expect(ble.writes, isNot(contains(wire.color(255, 0, 0))));
  });

  testWidgets('G4 live draft and concurrent color share one ON', (tester) async {
    await c.connect(FakeBle.strip);
    final preview = c.playDraft([colors.first], 1000, c.brightness,
        draft: () => (colors: [colors.first], interval: 1000, intensity: c.brightness));
    final update = c.applyShortcut({'kind': 'color', 'rgb': colors.last});
    await drain(tester);
    await Future.wait([preview, update]);
    expect(ble.writes.where((bytes) => bytes.toString() == wire.power(true).toString()), hasLength(1));
    expect(ble.writes.last, wire.color(0, 255, 0));
  });

  testWidgets('F7 command error notifies once and clears after a good send', (tester) async {
    await c.connect(FakeBle.strip);
    var notices = 0;
    c.addListener(() { if (c.message == 'commandFailed') notices++; });
    ble.failWrite = (_) => true;
    c.setPower(false);
    await drain(tester);
    c.setPower(false);
    await drain(tester);
    expect(notices, 1);
    ble.failWrite = null;
    c.setPower(false);
    await drain(tester);
    expect(c.message, isNull);
  });

  testWidgets('F8 rejected shortcut edit is not presented as saved', (tester) async {
    final controller = AppController(ble, RefusingShortcutStore(), checkAccess: (_) async => null);
    addTearDown(controller.dispose);
    final before = controller.shortcuts;
    controller.updateShortcuts([]);
    await tester.pump();
    expect(controller.shortcuts, before);
    expect(controller.message, 'appStorageFailed');
  });

  testWidgets('F10 favorite AUTO skips a removed next effect', (tester) async {
    for (final id in [1, 2, 3]) {
      c.toggleEffectFavorite(id);
    }
    c.setAppAutoOptions(seconds: 10, favorites: true);
    await c.connect(FakeBle.strip);
    await startAuto(tester);
    expect(c.appAutoEffect, 1);
    c.toggleEffectFavorite(2);
    await advance(tester, 10000);
    expect(c.appAutoEffect, 3);
    await advance(tester, 10000);
    expect(c.appAutoEffect, 1);
    c.stopAppAuto();
  });

  testWidgets('F13 timer rejects starts and extensions over twelve hours', (tester) async {
    await c.connect(FakeBle.strip);
    c.startTimer(43201, fade: false);
    expect(c.remaining, isNull);
    c.startTimer(42900, fade: false);
    c.extendTimer(300);
    expect(c.remaining, 43200);
    c.extendTimer(1);
    expect(c.remaining, 43200);
    c.cancelTimer();
  });

  for (final seconds in [10, 30, 60, 300]) {
    testWidgets('app AUTO loops sorted favorites every $seconds seconds', (tester) async {
      expect(c.appAutoSeconds, 30);
      c.toggleEffectFavorite(210);
      c.toggleEffectFavorite(2);
      c.setAppAutoOptions(seconds: seconds, favorites: true);
      await c.connect(FakeBle.strip);
      final preload = c.setEffect(1);
      await drain(tester);
      await preload;
      await c.startAppAuto();
      final frames = [effectFrame(2)];
      final first = ble.writes.indexOf(ble.writes.last);
      expect(ble.writes.last, frames.last);
      expect(c.appAutoEffect, 2);
      await advance(tester, seconds * 500);
      expect(c.appAutoProgress, closeTo(0.5, 0.01));
      await advance(tester, seconds * 500 - 1);
      expect(ble.writes.skip(first), frames);
      await advance(tester, 1);
      frames.add(effectFrame(210));
      expect(ble.writes.skip(first), frames);
      await advance(tester, seconds * 1000 - 1);
      expect(ble.writes.skip(first), frames);
      await advance(tester, 1);
      frames.add(effectFrame(2));
      expect(ble.writes.skip(first), frames);
      c.stopAppAuto();
    });
  }

  testWidgets('app AUTO plays the full catalog in order and wraps', (tester) async {
    await c.connect(FakeBle.strip);
    await startAuto(tester);
    expect(ble.writes.last, effectFrame(1));
    ble.writes.clear();
    for (var id = 2; id <= 211; id++) {
      await advance(tester, 30000);
      expect(ble.writes.last, effectFrame(id == 211 ? 1 : id));
    }
    expect(ble.writes, hasLength(210));
    c.stopAppAuto();
  });

  for (final exit in ['stop', 'background', 'link drop']) {
    testWidgets('app AUTO stops on $exit without more writes', (tester) async {
      await c.connect(FakeBle.strip);
      await startAuto(tester);
      final count = ble.writes.length;
      switch (exit) {
        case 'stop': c.stopAppAuto();
        case 'background': c.setForeground(false);
        case 'link drop': ble.changes.add((FakeBle.strip.id, false));
      }
      await tester.pump();
      expect(c.appAutoPlaying, isFalse);
      expect(c.appAutoEffect, isNull);
      if (exit == 'background') c.setForeground(true);
      await advance(tester, 60000);
      expect(ble.writes, hasLength(count));
    });
  }

  testWidgets('app AUTO supersedes scene playback and vice versa; speed is independent', (tester) async {
    await c.connect(FakeBle.strip);
    unawaited(c.playDraft(colors, 500, c.brightness, preview: false));
    await drain(tester);
    expect(ble.writes.last, wire.color(255, 0, 0));
    await startAuto(tester);
    expect(ble.writes.last, effectFrame(1));
    await advance(tester, 1000);
    expect(ble.writes.last, effectFrame(1));
    c.setSpeed(73);
    await drain(tester);
    expect(c.appAutoPlaying, isTrue);
    expect(ble.writes.last, wire.speed(73));
    unawaited(c.playDraft(colors, 500, c.brightness, preview: false));
    await drain(tester);
    expect(c.appAutoPlaying, isFalse);
    expect(ble.writes.last, wire.color(255, 0, 0));
    await advance(tester, 31000);
    expect(ble.writes.where((bytes) => bytes[2] == 3), [effectFrame(1)]);
    c.stopPlayback();
    await drain(tester);
  });

  test('app AUTO reloads duration and list without resuming', () {
    final store = Store();
    final initial = AppController(ble, store, checkAccess: (_) async => null);
    initial.toggleEffectFavorite(4);
    initial.setAppAutoOptions(seconds: 300, favorites: true);
    final reloaded = AppController(ble, store, checkAccess: (_) async => null);
    expect(reloaded.appAutoSeconds, 300);
    expect(reloaded.appAutoFavorites, isTrue);
    expect(reloaded.appAutoPlaying, isFalse);
    initial.dispose();
    reloaded.dispose();
  });

  test('offline sliders persist selection without sending', () {
    c.setBrightness(32);
    c.setSpeed(75);
    c.setMicSensitivity(88);
    expect([c.brightness, c.speed, c.sensitivity], [32, 75, 88]);
    final saved = c.models.loadState();
    expect([saved['bri'], saved['speed'], saved['micSens']], [32, 75, 88]);
    expect(ble.writes, isEmpty);
    expect(c.lastCommand, isNull);
  });

  for (final (label, frame, action) in <(String, List<int>, void Function(AppController))>[
    ('effectNamed', wire.effect(210), (c) => unawaited(c.setEffect(210))),
    ('autoCycle', wire.effect(wire.autoEffect), (c) => unawaited(c.setEffect(wire.autoEffect))),
    ('speed', wire.speed(75), (c) => c.setSpeed(75)),
    ('musicMode', wire.voiceMode(3), (c) => unawaited(c.setVoiceMode(3))),
    ('micSensitivity', wire.micSensitivity(88), (c) => c.setMicSensitivity(88)),
    ('chipConfig', wire.chipConfig('GRB', 200), (c) => unawaited(c.setChipConfig('GRB', 200))),
  ]) {
    testWidgets('$label is gated offline and supersedes scene playback', (tester) async {
      switch (label) {
        case 'speed': c.setSpeed(74);
        case 'micSensitivity': c.setMicSensitivity(87);
        default: action(c);
      }
      await drain(tester);
      expect(ble.writes, isEmpty);
      expect(c.lastCommand, isNull);
      await c.connect(FakeBle.strip);
      unawaited(c.playDraft(colors, 500, c.brightness, preview: false));
      await drain(tester);
      expect(ble.writes.last, wire.color(255, 0, 0));
      final commands = <String?>[];
      c.addListener(() => commands.add(c.lastCommand));
      // Use a different offline value so the connected action is a change.
      action(c);
      await drain(tester);
      expect(ble.writes, contains(equals(frame)));
      expect(commands, contains(label));
      final count = ble.writes.length;
      now += 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(ble.writes, hasLength(count));
      c.saveSelection();
      final saved = c.models.loadState();
      switch (label) {
        case 'effectNamed': expect(saved['mode'], {'effect': 210});
        case 'autoCycle': expect(saved['fx'], 'AUTO');
        case 'speed': expect(saved['speed'], 75);
        case 'musicMode': expect(saved['mode'], {'voice': 3});
        case 'micSensitivity': expect(saved['micSens'], 88);
        case 'chipConfig': expect(c.models.loadStripSettings(deviceId: FakeBle.strip.id).pixels, 200);
      }
      c.setForeground(false);
      await drain(tester);
    });
  }

  testWidgets('stopping a deleted saved scene only halts the matching player', (tester) async {
    await c.connect(FakeBle.strip);
    expect(await c.models.saveSequences([
      {'id': 'running', 'name': 'Running', 'colors': colors, 'interval': 500, 'bri': 80},
    ]), isTrue);
    unawaited(c.applyShortcut({'kind': 'sequence', 'id': 'running'}));
    await drain(tester);
    expect(ble.writes.last, wire.color(255, 0, 0));
    c.stopSequence('other');
    now += 500;
    await tester.pump(const Duration(milliseconds: 500));
    expect(ble.writes.last, wire.color(0, 255, 0));
    await c.models.saveSequences([]);
    c.stopSequence('running');
    expect(c.models.storage.read(Models.stateKey), isNot(contains('sequence:running')),
        reason: 'F9 persists the power-on fallback');
    final count = ble.writes.length;
    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes, hasLength(count));
  });

  for (final live in [true, false]) {
    testWidgets('failed first draft ${live ? 'power' : 'color'} clears preview', (tester) async {
      await c.connect(FakeBle.strip);
      ble.failWrite = (bytes) => bytes[2] == (live ? 4 : 7);
      final playback = c.playDraft(colors, 500, 25,
          draft: live ? () => (colors: colors, interval: 500, intensity: 25) : null);
      await drain(tester);
      await playback;
      expect(c.message, 'commandFailed');
      expect(c.previewing, isFalse);
    });
  }

  testWidgets('failed first saved scene send clears the active player', (tester) async {
    await c.connect(FakeBle.strip);
    await c.models.saveSequences([
      {'id': 'scene', 'name': 'Scene', 'colors': colors, 'interval': 500, 'bri': 80},
    ]);
    ble.failWrite = (_) => true;
    await c.applyShortcut({'kind': 'sequence', 'id': 'scene'});
    expect(c.message, 'commandFailed');
    var notified = false;
    c.addListener(() => notified = true);
    c.stopSequence('scene');
    expect(notified, isFalse);
  });

  testWidgets('draft preview is gated, does not persist, and can stop without sending', (tester) async {
    await c.playDraft(colors, 500, 25);
    expect(ble.writes, isEmpty);
    await c.connect(FakeBle.strip);
    final before = c.models.loadState();
    unawaited(c.playDraft(colors, 500, 25));
    await drain(tester);
    expect(c.previewing, isTrue);
    expect(ble.writes, [wire.power(true), wire.brightness(25), wire.color(255, 0, 0)]);
    expect(c.lastCommand, 'color');
    expect(c.models.loadState(), before);
    c.stopDraftPreview(restore: false);
    expect(c.previewing, isFalse);
    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes, hasLength(3));
    expect(c.lastCommand, 'color');
  });
}
