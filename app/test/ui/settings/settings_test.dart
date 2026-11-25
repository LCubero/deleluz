import 'package:deleluz/app_controller.dart';
import 'package:deleluz/link.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/settings/settings_screen.dart';
import 'package:flutter/services.dart';
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

  for (final (language, title, description, version, author, license, repository, copied) in [
    ('es', 'Acerca de', 'Control de tiras LED LEDDMX-03 por Bluetooth',
      'Versión', 'Autor', 'Licencia', 'Repositorio', 'Enlace copiado'),
    ('en', 'About', 'LEDDMX-03 LED strip control over Bluetooth',
      'Version', 'Author', 'License', 'Repository', 'Link copied'),
  ]) {
    testWidgets('About shows localized details and copies the repository in $language', (tester) async {
      final clipboard = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await start(tester);
      controller.setLanguage(language);
      await tester.pumpAndSettle();
      expect(find.text('LCubero'), findsNothing);
      await tap(tester, find.text(title));
      for (final text in [description, '$version 1.1.0', author, 'LCubero',
        license, 'MIT', repository, 'github.com/LCubero/deleluz', '¡Dele, enciéndala, mae!']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tap(tester, find.text(repository));
      expect(clipboard, [{'text': 'https://github.com/LCubero/deleluz'}]);
      expect(find.text(copied), findsOneWidget);
    });
  }

  testWidgets('About disclosure turns down when open and back right when closed', (tester) async {
    await start(tester);
    final title = find.text('Acerca de');
    final chevron = find.descendant(of: find.ancestor(of: title,
      matching: find.byType(GlowDisclosure)), matching: find.byIcon(Icons.chevron_right));
    Offset direction() {
      final box = tester.renderObject<RenderBox>(chevron);
      return box.localToGlobal(const Offset(1, 0)) - box.localToGlobal(Offset.zero);
    }
    expect(direction(), const Offset(1, 0));
    await tap(tester, title);
    expect(direction().dx, closeTo(0, .01));
    expect(direction().dy, closeTo(1, .01));
    await tap(tester, title);
    expect(direction(), const Offset(1, 0));
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('expanded About fits $size at enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await start(tester, scale: 2);
      await tap(tester, find.text('Acerca de'));
      final tagline = find.text('¡Dele, enciéndala, mae!');
      await tester.ensureVisible(tagline);
      await tester.pumpAndSettle();
      expect(tagline.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline edits persist without writes or permission requests', (tester) async {
    final saved = Store();
    await Models(saved, presetIds: {}).saveRememberedStrips([
      RememberedStrip(FakeBle.strip.id, FakeBle.strip.name),
    ]);
    await start(tester, savedStore: saved);
    expect(find.byType(ConnectionChip), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    await tap(tester, find.text('Configuración del dispositivo'));
    expect(enabled(tester), isFalse);
    await tester.enterText(field('stripTotal'), '200');
    await tester.pumpAndSettle();
    expect(controller.models.loadStripSettings(deviceId: FakeBle.strip.id).pixels, 200);
    expect(ble.writes, isEmpty);
    expect(access, isEmpty);
  });

  testWidgets('device setup follows the connected or last remembered device', (tester) async {
    await start(tester, connected: true);
    const second = Strip('second', 'Second device');
    controller.renameStrip(FakeBle.strip.id, 'Five meters');
    await tester.pumpAndSettle();
    await tap(tester, field('settings-stripSettings'));
    Finder subtitle(String label) => find.descendant(
      of: find.ancestor(of: field('settings-stripSettings'), matching: find.byType(ListTile)),
      matching: find.text(label),
    );
    String total() => tester.widget<TextField>(field('stripTotal')).controller!.text;
    expect(subtitle('Five meters'), findsOneWidget);
    await tester.enterText(field('stripTotal'), '150');
    await controller.connect(second);
    await tester.pumpAndSettle();
    expect(subtitle(second.name), findsOneWidget);
    await tap(tester, find.text('Por metro'));
    await tester.enterText(field('stripMeters'), '10');
    await tap(tester, field('stripOrder'));
    await tester.tap(find.text('GBR').last);
    await tester.pumpAndSettle();
    expect(total(), '300');
    await controller.connect(FakeBle.strip);
    await tester.pumpAndSettle();
    expect(total(), '150');
    expect(tester.widget<DropdownButton<String>>(field('stripOrder')).value, 'GRB');
    await controller.connect(second);
    await controller.disconnect();
    await tester.pumpAndSettle();
    expect(total(), '300');
    expect(subtitle(second.name), findsOneWidget);
    expect(enabled(tester), isFalse);
    await controller.connect(second);
    await tester.pumpAndSettle();
    expect(ble.writes, isEmpty);
    expect(tester.widget<TextField>(field('stripMeters')).controller!.text, '10');
    await tap(tester, send);
    expect(ble.writes, isEmpty);
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(ble.writes.single, chipConfig('GBR', 300));
    await controller.forgetStrip(second.id);
    await controller.connect(second);
    await tester.pumpAndSettle();
    expect(total(), '150');
    expect(tester.widget<DropdownButton<String>>(field('stripOrder')).value, 'GRB');
  });

  testWidgets('migration snapshots the legacy setup for the remembered device', (tester) async {
    final saved = Store();
    final models = Models(saved, presetIds: {});
    await models.saveRememberedStrips([RememberedStrip(FakeBle.strip.id, FakeBle.strip.name)]);
    await models.saveStripSettings(order: 'RGBW', density: 40, meters: 5);
    await start(tester, savedStore: saved);
    await models.saveStripSettings(order: 'GRB', pixels: 150);
    await tester.pumpAndSettle();
    await tap(tester, field('settings-stripSettings'));
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '200');
    await controller.connect(const Strip('new', 'New device'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '150');
    await controller.connect(FakeBle.strip);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '200');
    expect(tester.widget<TextField>(field('stripMeters')).controller!.text, '5');
    expect(ble.writes, isEmpty);
  });

  testWidgets('chip orders, integer bounds, cancel, and confirmed frame', (tester) async {
    await start(tester, connected: true);
    await tap(tester, field('settings-stripSettings'));
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
    await tap(tester, field('settings-stripSettings'));
    await tap(tester, find.text('Por metro'));
    expect(controller.models.loadStripSettings(deviceId: FakeBle.strip.id).density, 30);
    for (final (text, pixels) in [('0', null), ('0.01', null), ('35', null), ('34.149', 1024), ('1,25', 38)]) {
      await tester.enterText(field('stripMeters'), text);
      await tester.pump();
      expect(enabled(tester), pixels != null, reason: text);
      if (pixels != null) expect(controller.models.loadStripSettings(deviceId: FakeBle.strip.id).pixels, pixels);
    }
    expect(tester.widget<TextField>(field('stripTotal')).readOnly, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Total de LEDs').first);
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '38');
    expect(controller.models.loadStripSettings(deviceId: FakeBle.strip.id).density, isNull);
    expect(ble.writes, isEmpty);
  });

  testWidgets('saved meter settings restore and invalid drafts never overwrite them', (tester) async {
    final saved = Store();
    final models = Models(saved, presetIds: {});
    await models.saveRememberedStrips([RememberedStrip(FakeBle.strip.id, FakeBle.strip.name)]);
    await models.saveStripSettings(deviceId: FakeBle.strip.id, order: 'RGBW', density: 40, meters: 1.25);
    await start(tester, savedStore: saved);
    await tap(tester, field('settings-stripSettings'));
    expect(tester.widget<DropdownButton<String>>(field('stripOrder')).value, 'RGBW');
    expect(tester.widget<TextField>(field('stripTotal')).controller!.text, '50');
    await tester.enterText(field('stripDensity'), '-1');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 a 1024'), findsOneWidget);
    expect(controller.models.loadStripSettings(deviceId: FakeBle.strip.id).density, 40);
    expect(ble.writes, isEmpty);
  });

  testWidgets('reconnecting during confirmation invalidates the pending send', (tester) async {
    await start(tester, connected: true);
    await tap(tester, field('settings-stripSettings'));
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
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Device setup'), findsOneWidget);
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
      await tap(tester, find.text('Configuración del dispositivo'));
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
