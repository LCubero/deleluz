import 'package:deleluz/app_controller.dart';
import 'package:deleluz/model/effects.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:deleluz/ui/color/color_screen.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/hue_wheel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home_test.dart' show FakeBle, Store;

void main() {
  late AppController controller;
  late FakeBle ble;
  late double now;

  Future<void> start(WidgetTester tester, {bool connected = false,
      Size size = const Size(412, 915), double scale = 1}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ble = FakeBle();
    now = 0;
    controller = AppController(ble, Store(), checkAccess: (_) async => null,
        now: () => now);
    addTearDown(ble.changes.close);
    addTearDown(controller.dispose);
    if (connected) await controller.connect(FakeBle.strip);
    await tester.pumpWidget(MaterialApp(theme: glowTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: ColorScreen(controller: controller)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      now += 50;
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder keyed(String key) => find.byKey(Key(key));

  Future<void> tap(WidgetTester tester, String key) async {
    final target = keyed(key);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void hue(WidgetTester tester, double value) =>
      tester.widget<HueWheel>(find.byType(HueWheel)).onChanged(value);

  testWidgets('Favorites start closed; offline choices add and replace with no writes', (tester) async {
    await start(tester);
    expect(find.byType(ConnectionChip), findsOneWidget);
    expect(keyed('favorite-#00ff00'), findsNothing);
    await tap(tester, 'color-favorites');
    expect(controller.models.loadPalette(), defaultPalette);
    hue(tester, 240);
    await tester.pump();
    await tap(tester, 'favorite-plus');
    expect(controller.models.loadPalette(), [...defaultPalette, '#0000ff']);
    await tap(tester, 'favorite-plus');
    expect(controller.models.loadPalette(), hasLength(4));
    await tap(tester, 'favorite-#00ff00');
    hue(tester, 180);
    await tester.pump();
    await tap(tester, 'favorite-plus');
    expect(controller.models.loadPalette(), ['#00ffff', ...defaultPalette.skip(1), '#0000ff']);
    expect(ble.writes, isEmpty);
    expect(find.text(controller.text('noCommand')), findsOneWidget);
  });

  testWidgets('Favorites at 15 can replace; long drag reorders and deletes', (tester) async {
    await start(tester);
    final full = List.generate(15, (i) => '#0102${i.toRadixString(16).padLeft(2, '0')}');
    await controller.models.savePalette(full);
    await tap(tester, 'color-favorites');
    hue(tester, 240);
    await tester.pump();
    await tap(tester, 'favorite-plus');
    expect(find.text(controller.text('paletteFull')), findsOneWidget);
    expect(controller.models.loadPalette(), full);
    await tap(tester, 'favorite-${full.last}');
    hue(tester, 240);
    await tester.pump();
    await tap(tester, 'favorite-plus');
    full[14] = '#0000ff';
    expect(controller.models.loadPalette(), full);

    Future<void> drag(String from, String to) async {
      await tester.ensureVisible(keyed(from));
      final gesture = await tester.startGesture(tester.getCenter(keyed(from)));
      await tester.pump(const Duration(milliseconds: 550));
      await gesture.moveTo(tester.getCenter(keyed(to)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag('favorite-${full[0]}', 'favorite-${full[1]}');
    expect(controller.models.loadPalette().take(2), [full[1], full[0]]);
    await drag('favorite-${full.last}', 'favorite-plus');
    expect(controller.models.loadPalette(), hasLength(14));
    expect(controller.models.loadPalette(), isNot(contains(full.last)));
  });

  testWidgets('effect arrows wrap, entry clamps and Auto sends its frame', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'color-effects');
    expect(find.text(effectNames.first), findsOneWidget);
    await tap(tester, 'effect-previous');
    await flush(tester);
    expect(ble.writes.last, wire.effect(210));
    expect(find.text(effectNames.last), findsOneWidget);
    await tap(tester, 'effect-next');
    await flush(tester);
    expect(ble.writes.last, wire.effect(1));
    for (final (input, expected) in [('999', 210), ('0', 1)]) {
      await tester.enterText(keyed('effect-number'), input);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      expect(ble.writes.last, wire.effect(expected));
    }
    await tap(tester, 'effect-auto');
    await flush(tester);
    expect(ble.writes.last, wire.effect(wire.autoEffect));
    expect(find.text(controller.text('allEffects')), findsOneWidget);
    expect(find.textContaining(controller.text('lastSent', {'command': ''})), findsOneWidget);
  });

  testWidgets('brightness, speed and color keep only the latest queued value per key', (tester) async {
    await start(tester, connected: true);
    hue(tester, 0);
    await flush(tester);
    ble.writes.clear();
    hue(tester, 60);
    hue(tester, 120);
    hue(tester, 240);
    await tap(tester, 'color-effects');
    final brightness = tester.widget<Slider>(keyed('color-brightness'));
    final speed = tester.widget<Slider>(keyed('color-speed'));
    expect(brightness.min, 1);
    expect(speed.min, 1);
    expect(speed.max, 100);
    expect(tester.getTopLeft(keyed('color-brightness')).dy,
        lessThan(tester.getTopLeft(keyed('color-speed')).dy));
    brightness.onChanged!(1);
    brightness.onChanged!(100);
    speed.onChanged!(100);
    speed.onChanged!(1);
    await flush(tester);
    final writes = ble.writes.map(wire.hex).toList();
    expect(writes, containsAll([wire.color(0, 0, 255), wire.brightness(100), wire.speed(1)].map(wire.hex)));
    expect(writes, isNot(contains(wire.hex(wire.color(0, 255, 0)))));
    expect(writes, isNot(contains(wire.hex(wire.brightness(1)))));
    expect(writes, isNot(contains(wire.hex(wire.speed(100)))));
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('both modes fit ${size.width.toInt()} dp at enlarged text', (tester) async {
      await start(tester, size: size, scale: 2, connected: true);
      await tap(tester, 'color-favorites');
      await tester.ensureVisible(keyed('color-brightness'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.setLanguage('en');
      await tester.pump();
      await tap(tester, 'color-effects');
      await tester.ensureVisible(keyed('color-speed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
