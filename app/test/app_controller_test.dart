import 'dart:async';

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:flutter_test/flutter_test.dart';

import 'ui/home_test.dart' show FakeBle, Store;

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
    final count = ble.writes.length;
    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes, hasLength(count));
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
