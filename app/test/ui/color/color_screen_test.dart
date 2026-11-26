import 'package:deleluz/app_controller.dart';
import 'package:deleluz/model/effects.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:deleluz/ui/color/color_screen.dart';
import 'package:deleluz/ui/effect_list.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/color_disc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home_test.dart' show FakeBle, Store;

void main() {
  late AppController controller;
  late FakeBle ble;
  late double now;

  Future<void> start(WidgetTester tester, {bool connected = false,
      Size size = const Size(412, 915), double scale = 1, LocalStore? store}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ble = FakeBle();
    now = 0;
    controller = AppController(ble, store ?? Store(), checkAccess: (_) async => null,
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
      tester.widget<ColorDisc>(find.byType(ColorDisc)).onChanged(
        HSVColor.fromAHSV(1, value, 1, 1));

  testWidgets('Disc taps and vertical drags send white, pastels and saturated red', (tester) async {
    await start(tester, connected: true);
    final disc = keyed('color-disc');
    expect(disc, findsOneWidget);
    final center = tester.getCenter(disc);
    final radius = tester.getSize(disc).width / 2;
    final edge = center - Offset(0, radius - 0.1);
    await tester.tapAt(center);
    await flush(tester);
    expect(ble.writes.last, wire.color(255, 255, 255));
    final drag = await tester.startGesture(center);
    await drag.moveTo(center - Offset(0, radius / 3));
    await drag.moveTo(center - Offset(0, radius / 2));
    await flush(tester);
    expect(ble.writes.last, wire.color(255, 128, 128));
    await drag.moveTo(edge);
    await flush(tester);
    expect(ble.writes.last, wire.color(255, 0, 0));
    await drag.moveTo(center + Offset(radius / 2, 0));
    await flush(tester);
    expect(ble.writes.last, wire.color(191, 255, 128));
    await drag.moveTo(center);
    await drag.up();
    await flush(tester);
    expect(ble.writes.last, wire.color(255, 255, 255));
  });

  testWidgets('A drag from a blank disc corner scrolls without sending color', (tester) async {
    await start(tester, connected: true, size: const Size(320, 480));
    final disc = keyed('color-disc');
    final page = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(page).position;
    final corner = tester.getBottomLeft(disc) + const Offset(4, -4);
    await tester.dragFrom(corner, const Offset(0, -80));
    await flush(tester);
    expect(ble.writes, isEmpty);
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('White chips keep the swatch and fit one row at 411 dp after selection', (tester) async {
    await start(tester, connected: true, size: const Size(411, 834));
    for (final (label, rgb) in [
      ('Cálido', wire.color(255, 200, 128)),
      ('Neutro', wire.color(255, 228, 196)),
      ('Frío', wire.color(255, 255, 255)),
    ]) {
      final chip = find.widgetWithText(ChoiceChip, label);
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(chip).width, greaterThanOrEqualTo(48));
      await tester.tap(chip);
      await flush(tester);
      expect(ble.writes.last, rgb);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(find.descendant(of: chip, matching: find.byType(CircleAvatar)), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.byKey(GlowSelection.markerKey)), findsOneWidget);
      for (final tone in ['Cálido', 'Neutro', 'Frío']) {
        expect(tester.getTopLeft(find.widgetWithText(ChoiceChip, tone)).dy, tester.getTopLeft(chip).dy);
      }
    }
  });

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
    expect(find.text(controller.text('noCommand')), findsNothing);
  });

  testWidgets('F12 duplicate palette add explains why nothing was saved', (tester) async {
    await start(tester);
    await tap(tester, 'color-favorites');
    hue(tester, 120);
    await tester.pump();
    await tap(tester, 'favorite-plus');
    expect(find.text(controller.text('paletteDuplicate')), findsOneWidget);
    expect(controller.models.loadPalette(), defaultPalette);
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

  for (final width in [320.0, 412.0]) {
    testWidgets('app AUTO fits at $width dp with enlarged text', (tester) async {
      await start(tester, connected: true, size: Size(width, 760), scale: 1.5);
      await tap(tester, 'color-effects');
      expect(find.text('AUTO de la app'), findsOneWidget);
      expect(find.text('Solo funciona con la app abierta y la tira conectada.'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(keyed('app-auto-favorites')).onSelected, isNull);
      expect(find.text('Marca efectos con la estrella para usar Favoritos.'), findsOneWidget);
      final catalog = find.byType(EffectList);
      final list = find.descendant(of: catalog, matching: find.byType(ListView));
      final auto = tester.getRect(keyed('app-auto'));
      expect(tester.getRect(keyed('effect-auto')).bottom,
          lessThan(tester.getRect(catalog).top));
      expect(tester.getRect(keyed('effect-search')).bottom,
          lessThan(tester.getRect(list).top));
      expect(tester.getSize(list).height, 270);
      expect(keyed('effect-row-210'), findsNothing);
      expect(tester.getRect(catalog).bottom, lessThan(auto.top));
      expect(auto.bottom, lessThan(tester.getRect(keyed('color-brightness')).top));
      expect(tester.getRect(keyed('color-brightness')).bottom,
          lessThan(tester.getRect(keyed('color-speed')).top));
      await tester.ensureVisible(keyed('app-auto-toggle'));
      await tester.tap(keyed('app-auto-toggle'));
      await flush(tester);
      expect(tester.widget<Text>(keyed('app-auto-current')).data, '01 · ${effectNames.first}');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final duration = keyed('app-auto-${controller.appAutoSeconds}');
      final disabled = tester.widget<ChoiceChip>(duration);
      const disabledSelected = {WidgetState.disabled, WidgetState.selected};
      expect(disabled.selected, isTrue);
      expect(disabled.onSelected, isNull);
      expect(disabled.color!.resolve(disabledSelected), glowGlass);
      expect(disabled.labelStyle!.color, glowMuted);
      expect(WidgetStateProperty.resolveAs<BorderSide?>(disabled.side, disabledSelected),
          const BorderSide(color: glowLine));
      expect(find.descendant(of: duration, matching: find.byKey(GlowSelection.markerKey)), findsOneWidget);
      final mask = tester.widget<ShaderMask>(keyed('app-auto-gradient'));
      expect(mask.shaderCallback, glowProgressGradient.createShader);
      expect(glowProgressGradient.colors, [glowViolet, glowPink]);
      final other = keyed('app-auto-${Models.appAutoDurations.firstWhere((s) => s != controller.appAutoSeconds)}');
      final unselected = tester.widget<ChoiceChip>(other);
      expect(unselected.onSelected, isNull);
      expect(unselected.labelStyle!.color, glowMuted);
      expect(find.descendant(of: other, matching: find.byKey(GlowSelection.markerKey)), findsNothing);
      await tap(tester, 'app-auto-toggle');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final enabled = tester.widget<ChoiceChip>(duration);
      expect(enabled.onSelected, isNotNull);
      expect(enabled.labelStyle!.color, glowInk);
      expect(enabled.color!.resolve({WidgetState.selected}), GlowSelection.tint);
      final count = ble.writes.length;
      now += 30000;
      await tester.pump(const Duration(seconds: 30));
      expect(ble.writes, hasLength(count));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('effect search filters by name and ID; row and Auto send their frames', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'color-effects');
    final search = keyed('effect-search');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'FÓRWARD DREAMING');
    await tester.pumpAndSettle();
    expect(find.text('01 · ${effectNames.first}'), findsOneWidget);
    expect(find.text('02 · ${effectNames[1]}'), findsNothing);
    await tester.enterText(search, '210');
    await tester.pumpAndSettle();
    expect(find.text('210 · ${effectNames.last}'), findsOneWidget);
    expect(find.text('01 · ${effectNames.first}'), findsNothing);
    expect(ble.writes, isEmpty);
    await tap(tester, 'effect-auto');
    await flush(tester);
    expect(ble.writes.last, wire.effect(wire.autoEffect));
    expect(tester.widget<ChoiceChip>(keyed('effect-auto')).selected, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(keyed('strip-cycle-all'), findsOneWidget);
    expect(find.textContaining(controller.text('lastSent', {'command': ''})), findsNothing);
    await tap(tester, 'effect-row-210');
    await flush(tester);
    expect(ble.writes.last, [0x7b, 0xff, 3, 210, 255, 255, 255, 255, 0xbf]);
    expect(tester.widget<ListTile>(keyed('effect-row-210')).selected, isTrue);
    expect(keyed('strip-cycle-all'), findsNothing);
    ble.failWrite = (_) => true;
    await tap(tester, 'effect-auto');
    await flush(tester);
    expect(tester.widget<ChoiceChip>(keyed('effect-auto')).selected, isFalse);
    expect(tester.widget<ListTile>(keyed('effect-row-210')).selected, isTrue);
  });

  for (final (language, width, prefix) in [('es', 320.0, 'En la tira'), ('en', 412.0, 'On the strip')]) {
    testWidgets('Searching preserves the manual now-playing label and BLE writes ($language)', (tester) async {
      await start(tester, connected: true, size: Size(width, 915), scale: 1.5);
      controller.setLanguage(language);
      await tester.pump();
      await tap(tester, 'color-effects');
      final search = keyed('effect-search');
      final label = find.text('$prefix: 210 · ${effectNames.last}');
      expect(label, findsNothing);
      await tester.enterText(search, '210');
      await tester.pumpAndSettle();
      await tester.tap(keyed('effect-row-210'));
      await flush(tester);
      expect(ble.writes.last, wire.effect(210));
      final writes = ble.writes.map(wire.hex).toList();

      await tester.enterText(search, 'Forward Dreaming');
      await tester.pumpAndSettle();
      expect(keyed('effect-row-210'), findsNothing);
      expect(keyed('effect-row-1'), findsOneWidget);
      expect(ble.writes.map(wire.hex), writes);
      expect(label, findsOneWidget);
      expect(tester.getRect(label).bottom, lessThan(tester.getRect(find.byType(EffectList)).top));
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(tester.getRect(label).top, greaterThanOrEqualTo(viewport.top));
      expect(tester.getRect(label).bottom, lessThanOrEqualTo(viewport.bottom));
      expect(tester.takeException(), isNull);

      await tap(tester, 'effect-auto');
      await flush(tester);
      expect(label, findsNothing);
      expect(keyed('strip-cycle-all'), findsOneWidget);
    });
  }

  testWidgets('effect favorites move, reload, and unstar without sending', (tester) async {
    final store = Store();
    await start(tester, store: store);
    await tap(tester, 'color-effects');
    final star = find.byTooltip('Favorito: ${effectNames[1]}');
    await tester.ensureVisible(keyed('effect-search'));
    await tester.pumpAndSettle();
    expect(tester.getSize(star), const Size(48, 48));
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(controller.effectFavorites, {2});
    final favorites = find.descendant(of: find.byType(EffectList), matching: find.text('Favoritos'));
    final all = find.text('Todos los efectos');
    expect(tester.getTopLeft(favorites).dy, lessThan(tester.getTopLeft(star).dy));
    expect(tester.getTopLeft(star).dy, lessThan(tester.getTopLeft(all).dy));
    expect(ble.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await start(tester, store: store);
    await tap(tester, 'color-effects');
    expect(tester.getTopLeft(star).dy, lessThan(tester.getTopLeft(all).dy));
    await tester.ensureVisible(keyed('effect-search'));
    await tester.pumpAndSettle();
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(controller.effectFavorites, isEmpty);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(tester.getTopLeft(star).dy, greaterThan(tester.getTopLeft(all).dy));
  });

  testWidgets('invalid stored effect favorites are ignored', (tester) async {
    final store = Store();
    store.values['deleluz.app.effectFavorites'] = '[0,2,2,211,255,1.5,"3",null]';
    await start(tester, store: store);
    await tap(tester, 'color-effects');
    expect(find.text('Favoritos'), findsNWidgets(2));
    final all = find.text('Todos los efectos');
    expect(tester.getTopLeft(keyed('effect-row-2')).dy, lessThan(tester.getTopLeft(all).dy));
    expect(tester.getTopLeft(keyed('effect-row-1')).dy, greaterThan(tester.getTopLeft(all).dy));
    expect(tester.getTopLeft(keyed('effect-row-3')).dy, greaterThan(tester.getTopLeft(all).dy));
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
      final segment = find.ancestor(of: keyed('color-effects'), matching: find.byType(GlowSelectionTarget));
      expect(find.descendant(of: segment, matching: find.byKey(GlowSelection.markerKey)), findsOneWidget);
      await tap(tester, 'effect-auto');
      await flush(tester);
      expect(tester.widget<ChoiceChip>(keyed('effect-auto')).selected, isTrue);
      await tester.enterText(keyed('effect-search'), 'backward dreaming');
      await tester.pumpAndSettle();
      await tester.ensureVisible(keyed('effect-star-2'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(keyed('color-speed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
