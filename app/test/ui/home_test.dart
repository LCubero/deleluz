import 'dart:async';
import 'dart:typed_data';

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/link.dart';
import 'package:deleluz/main.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:deleluz/ui/glow_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class Store implements LocalStore {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  Future<bool> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    return true;
  }
}

class FakeBle implements BleApi {
  static const strip = Strip('fake', 'LEDDMX Test');
  final connections = <String>[];
  final writes = <Uint8List>[];
  final changes = StreamController<(String, bool)>.broadcast();
  @override
  Future<void> connect(String id) async => connections.add(id);
  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<bool> hasWriteWithoutResponse(String id) async => true;
  @override
  Stream<Strip> scan() {
    final results = StreamController<Strip>();
    results.add(strip);
    return results.stream;
  }
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> write(String id, Uint8List bytes) async => writes.add(bytes);
  @override
  Stream<(String, bool)> get connectionChanges => changes.stream;
}

void main() {
  late FakeBle ble;
  late Store store;
  late double now;
  late List<bool> accessChecks;
  String? accessProblem;
  setUp(() {
    ble = FakeBle();
    store = Store();
    now = 0;
    accessChecks = [];
    accessProblem = null;
  });

  Future<AppController> start(WidgetTester tester) async {
    final controller = AppController(ble, store, checkAccess: (request) async {
      accessChecks.add(request);
      return accessProblem;
    }, now: () => now);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MainApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, FakeBle.strip.name);
    expect(tester.widget<ListTile>(tile).enabled, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Buscando tiras…'), findsNothing);
    expect(find.text('No se pudo conectar.'), findsNothing);
  }

  Future<void> send(WidgetTester tester, Future<void> Function() command) async {
    final done = command();
    for (var i = 0; i < 4; i++) {
      now += 60;
      await tester.pump(const Duration(milliseconds: 60));
    }
    await done;
  }

  testWidgets('Home speed follows the last sent mode, not the last command', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await start(tester);
    await connect(tester);
    Slider speed() => tester.widget<Slider>(find.byKey(const Key('speed')));
    expect(speed().onChanged, isNull);
    expect(find.text('La velocidad aplica a efectos'), findsOneWidget);

    await send(tester, () => c.setEffect(210));
    expect(speed().onChanged, isNotNull);
    expect(find.text('La velocidad aplica a efectos'), findsNothing);
    speed().onChanged!(70);
    await tester.pump();
    expect(ble.writes.last, orderedEquals(wire.speed(70)));
    expect(speed().onChanged, isNotNull);

    await send(tester, () => c.applyShortcut({'kind': 'color', 'rgb': [1, 2, 3]}));
    expect(speed().onChanged, isNull);
    await send(tester, () => c.setEffect(wire.autoEffect));
    expect(speed().onChanged, isNotNull);
    await send(tester, () => c.setVoiceMode(2));
    expect(speed().onChanged, isNull);

    c.setLanguage('en');
    await tester.pump();
    expect(find.text('Speed applies to effects'), findsOneWidget);
    await send(tester, () => c.setEffect(1));
    await send(tester, () => c.playDraft([[10, 20, 30], [40, 50, 60]], 650, 50, preview: false));
    expect(speed().onChanged, isNull);
    await send(tester, () => c.setEffect(2));
    await send(tester, () async => c.setPower(false));
    expect(speed().onChanged, isNull);
  });

  testWidgets('Home strip preview distinguishes unknown, sent and disconnected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await start(tester);
    final preview = find.byType(GlowStrip).first;
    GlowStrip strip() => tester.widget<GlowStrip>(preview);
    BoxDecoration paint() => tester.widget<Container>(
      find.descendant(of: preview, matching: find.byType(Container)).first,
    ).decoration! as BoxDecoration;
    expect(strip().dotted, isTrue);
    expect(paint().color, const Color(0xff2a2540));

    await connect(tester);
    expect(ble.writes, isEmpty);
    final unknown = paint().gradient as LinearGradient;
    expect(unknown.colors.length, greaterThan(1));
    await send(tester, () => c.applyShortcut({'kind': 'color', 'rgb': [10, 20, 30]}));
    expect(paint().gradient, isNull);
    expect(paint().color, const Color(0xff0a141e));
    await send(tester, () => c.setEffect(2));
    expect(paint().gradient, isA<LinearGradient>());
    expect(paint().gradient, isNot(unknown));
    await send(tester, () async => c.setPower(false));
    expect(paint().gradient, isNull);
    expect(paint().color, const Color(0xff2a2540));
    await send(tester, () => c.setEffect(2));
    await c.disconnect();
    await tester.pumpAndSettle();
    expect(strip().dotted, isTrue);
    expect(paint().gradient, isNull);
    expect(paint().color, const Color(0xff2a2540));
    await c.reconnect();
    await tester.pumpAndSettle();
    expect(paint().gradient, unknown);
    expect(tester.widget<Slider>(find.byKey(const Key('speed'))).onChanged, isNull);
  });

  testWidgets('each tab renders the shared header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    final controller = await start(tester);
    final header = find.byType(GlowHeader);
    for (final (tab, title) in [('Inicio', 'DeleLuz'), ('Color', 'Color'),
      ('Escenas', 'Escenas'), ('Ajustes', 'Ajustes')]) {
      await tester.tap(find.descendant(of: find.byType(InkWell),
        matching: find.text(tab)).hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.descendant(of: header, matching: find.text(title)).hitTestable(), findsOneWidget);
      final chip = find.byType(ConnectionChip).hitTestable();
      expect(chip, findsOneWidget);
      final status = find.descendant(of: chip, matching: find.text('Sin conexión'));
      expect(tester.widget<Text>(status).maxLines, 1);
      expect(find.text(controller.text('noCommand')).hitTestable(),
        tab == 'Inicio' ? findsOneWidget : findsNothing);
      expect(find.descendant(of: header, matching: find.byType(ConnectionChip)).hitTestable(),
        tab == 'Inicio' ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Home shows an inactive strip preview and web slider order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
    expect(find.text('Apagado'), findsOneWidget);
    final header = find.byType(GlowHeader);
    final action = find.descendant(of: header, matching: find.byType(IconButton));
    expect(action, findsOneWidget);
    final size = tester.getSize(action);
    expect(size.width, size.height);
    final preview = find.byType(GlowStrip).first;
    expect(tester.getTopRight(find.byType(ConnectionChip)).dx, tester.getTopRight(preview).dx);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Vista previa de la tira'),
      findsOneWidget);
    expect(find.text('Todas las escenas'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('speed'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('brightness'))).dy));
  });

  testWidgets('disconnected power cannot send', (tester) async {
    await start(tester);
    final button = tester.widget<IconButton>(find.byKey(const Key('power')));
    expect(button.onPressed, isNull);
    expect(accessChecks, isEmpty);
    expect(ble.writes, isEmpty);
  });

  testWidgets('Connect scans and sends selection to the link', (tester) async {
    await start(tester);
    await connect(tester);
    expect(accessChecks, [true]);
    expect(ble.connections, ['fake']);
    expect(find.text('Conectado'), findsOneWidget);
    expect(store.read(Models.rememberedKey), contains(FakeBle.strip.name));
  });

  testWidgets('a drop recovers the remembered strip without requesting permissions', (tester) async {
    final controller = await start(tester);
    await connect(tester);
    controller.setForeground(false);
    ble.changes.add(('fake', false));
    await tester.pumpAndSettle();
    expect(find.text('Conexión perdida'), findsOneWidget);
    expect(ble.connections, ['fake']);
    controller.setForeground(true);
    await tester.pumpAndSettle();
    expect(find.text('Conectado'), findsOneWidget);
    expect(accessChecks, [true, false]);
    expect(ble.connections, ['fake', 'fake']);
  });

  testWidgets('brightness drag replaces queued frames without changing tab', (tester) async {
    final controller = await start(tester);
    await connect(tester);
    final slider = find.byKey(const Key('brightness'));
    await tester.scrollUntilVisible(slider, 120);
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(tester.getCenter(slider));
    for (var i = 0; i < 4; i++) {
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await drag.up();
    expect(ble.writes, hasLength(1));
    now = 60;
    await tester.pump(const Duration(milliseconds: 60));
    expect(ble.writes, hasLength(2));
    expect(ble.writes.last[4], controller.brightness);
    expect(slider, findsOneWidget);
  });

  for (final (problem, message) in [
    ('permissionDenied', 'Permite el acceso a dispositivos cercanos para conectar.'),
    ('bluetoothOff', 'Activa Bluetooth para conectar.'),
  ]) {
    testWidgets('Connect explains $problem without opening the link', (tester) async {
      accessProblem = problem;
      await start(tester);
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text(FakeBle.strip.name), findsNothing);
      expect(ble.connections, isEmpty);
    });
  }

  testWidgets('timer sends off in foreground and cancels when hidden', (tester) async {
    final controller = await start(tester);
    await connect(tester);
    controller.startTimer(1, fade: false);
    now = 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes.single.sublist(2, 4), [4, 0]);
    expect(controller.remaining, isNull);

    controller.startTimer(1, fade: false);
    controller.setForeground(false);
    now = 2000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes, hasLength(1));
    expect(controller.remaining, isNull);
  });

  testWidgets('right swipe from Inicio wraps to Ajustes', (tester) async {
    await start(tester);
    await tester.dragFrom(const Offset(250, 90), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-stripSettings')), findsOneWidget);
    await tester.dragFrom(const Offset(450, 90), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('power')), findsOneWidget);
  });

  testWidgets('Spanish default, English selection is persisted', (tester) async {
    await start(tester);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.byTooltip('Idioma'), findsNothing);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    final language = find.byKey(const Key('settings-settingsLanguage'));
    await tester.ensureVisible(language);
    await tester.tap(language);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(store.read(Models.languageKey), 'en');
  });

  testWidgets('restores remembered device without opening Bluetooth', (tester) async {
    await Models(store, presetIds: {}).saveRemembered(FakeBle.strip);
    await start(tester);
    expect(find.text(FakeBle.strip.name), findsOneWidget);
    expect(find.text('Reconectar'), findsOneWidget);
    expect(accessChecks, isEmpty);
    expect(ble.connections, isEmpty);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('Home fits $size with enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      await start(tester);
      final hint = find.text('La velocidad aplica a efectos');
      await tester.scrollUntilVisible(hint, 100);
      await tester.ensureVisible(hint);
      await tester.pumpAndSettle();
      expect(hint.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final quick = find.text('ESCENAS RÁPIDAS');
      await tester.scrollUntilVisible(quick, 100);
      await tester.ensureVisible(quick);
      await tester.pumpAndSettle();
      await tester.tap(quick.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Blanco cálido'), findsOneWidget);
      expect(find.byKey(const Key('speed')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
