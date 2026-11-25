import 'package:deleluz/app_controller.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../home_test.dart' show FakeBle, Store;

void main() {
  late AppController controller;
  late FakeBle ble;
  late Store store;
  late List<bool> access;
  final send = find.byKey(const Key('stripSend'));
  Finder field(String key) => find.byKey(Key(key));

  Future<void> start(WidgetTester tester, {
    bool connected = false,
    double scale = 1,
    Store? savedStore,
  }) async {
    ble = FakeBle();
    store = savedStore ?? Store();
    access = [];
    controller = AppController(ble, store, checkAccess: (request) async {
      access.add(request);
      return null;
    });
    addTearDown(() async {
      controller.dispose();
      await ble.changes.close();
    });
    if (connected) await controller.connect(FakeBle.strip);
    await tester.pumpWidget(MaterialApp(
      theme: glowTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: SettingsScreen(controller: controller)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) => tester.widget<FilledButton>(send).onPressed != null;

  testWidgets('offline edits persist without writes or permission requests', (tester) async {
    await start(tester);
    expect(find.byType(ConnectionChip), findsOneWidget);
    await tap(tester, find.text('Tira'));
    expect(enabled(tester), isFalse);
    await tester.enterText(field('stripTotal'), '200');
    await tester.pumpAndSettle();
    expect(controller.models.loadStripSettings().pixels, 200);
    expect(ble.writes, isEmpty);
    expect(access, isEmpty);
  });

  testWidgets('chip orders, integer bounds, cancel, and confirmed frame', (tester) async {
    await start(tester, connected: true);
    await tap(tester, find.text('Tira'));
    expect(tester.widget<DropdownButton<String>>(field('stripOrder')).items!.map((item) => item.value), chipOrders);
    await tap(tester, field('stripOrder'));
    await tester.tap(find.text('GBR').last);
    await tester.pumpAndSettle();
    for (final (text, valid) in [('0', false), ('1', true), ('1.5', false), ('1025', false), ('1024', true)]) {
      await tester.enterText(field('stripTotal'), text);
      await tester.pump();
      expect(enabled(tester), valid, reason: text);
    }
    await tap(tester, send);
    expect(ble.writes, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(ble.writes, isEmpty);
    await tap(tester, send);
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(ble.writes.single, chipConfig('GBR', 1024));
    expect(find.textContaining('GBR · 1024'), findsOneWidget);
    await tester.enterText(field('stripTotal'), '150');
    await tester.pumpAndSettle();
    expect(find.textContaining('GBR · 1024'), findsOneWidget);
    expect(ble.writes, hasLength(1));
  });

  testWidgets('per-meter rounds and rejects invalid products; total inherits the calculation', (tester) async {
    await start(tester, connected: true);
    await tap(tester, find.text('Tira'));
    await tap(tester, find.text('Por metro'));
    expect(controller.models.loadStripSettings().density, 30);
    for (final (text, pixels) in [('0', null), ('0.01', null), ('35', null), ('34.149', 1024), ('1,25', 38)]) {
      await tester.enterText(field('stripMeters'), text);
      await tester.pump();
      expect(enabled(tester), pixels != null, reason: text);
      if (pixels != null) expect(controller.models.loadStripSettings().pixels, pixels);
    }
    expect(tester.widget<TextField>(field('stripTotal')).readOnly, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Total de LEDs').first);
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '38');
    expect(controller.models.loadStripSettings().density, isNull);
    expect(ble.writes, isEmpty);
  });

  testWidgets('saved meter settings restore and invalid drafts never overwrite them', (tester) async {
    final saved = Store();
    await Models(saved, presetIds: {}).saveStripSettings(order: 'RGBW', density: 40, meters: 1.25);
    await start(tester, savedStore: saved);
    await tap(tester, find.text('Tira'));
    expect(tester.widget<DropdownButton<String>>(field('stripOrder')).value, 'RGBW');
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '50');
    await tester.enterText(field('stripDensity'), '-1');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 a 1024'), findsOneWidget);
    expect(controller.models.loadStripSettings().density, 40);
    expect(ble.writes, isEmpty);
  });

  testWidgets('reconnecting during confirmation invalidates the pending send', (tester) async {
    await start(tester, connected: true);
    await tap(tester, find.text('Tira'));
    await tap(tester, send);
    await controller.disconnect();
    await controller.connect(FakeBle.strip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(ble.writes, isEmpty);
    expect(enabled(tester), isTrue);
  });

  testWidgets('language, symptom help, and Android privacy', (tester) async {
    await start(tester);
    await tap(tester, find.text('Idioma'));
    await tap(tester, find.text('English'));
    expect(store.read(Models.languageKey), 'en');
    expect(find.text('Settings'), findsOneWidget);
    await tap(tester, find.text('Help'));
    for (final (symptom, detail) in [
      ('The strip is not in the list', 'Close the LED LAMP app'),
      ('It disconnects often', 'steady power'),
      ("Connected, but lights don't respond", "can't read"),
      ('Scene stopped when I left the app', 'foreground'),
    ]) {
      await tap(tester, find.text(symptom));
      expect(find.textContaining(detail), findsOneWidget);
      await tap(tester, find.text(symptom));
    }
    await tap(tester, find.text('Privacy and permissions'));
    expect(find.textContaining('Android 12'), findsOneWidget);
    expect(find.textContaining('no network requests'), findsOneWidget);
    expect(access, isEmpty);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('expanded settings and dialog fit $size with large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await start(tester, connected: true, scale: 2);
      await tap(tester, find.text('Tira'));
      await tap(tester, find.text('Por metro'));
      await tap(tester, send);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Idioma'));
      await tap(tester, find.text('Ayuda'));
      await tap(tester, find.text('Hay conexión, pero las luces no responden'));
      await tap(tester, find.text('Privacidad y permisos'));
      expect(tester.takeException(), isNull);
    });
  }
}
