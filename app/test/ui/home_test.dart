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
  final disconnects = <String>[];
  List<Strip> results = [strip];
  final writes = <Uint8List>[];
  final changes = StreamController<(String, bool)>.broadcast();
  @override
  Future<void> connect(String id) async {
    connections.add(id);
    if (unreachable.contains(id)) throw StateError('Fake connection failure');
  }

  final unreachable = <String>{};
  @override
  Future<void> disconnect(String id) async => disconnects.add(id);
  @override
  Future<bool> hasWriteWithoutResponse(String id) async => true;
  @override
  Stream<Strip> scan() {
    return Stream.fromIterable(results);
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
    final row = find.byKey(ValueKey(FakeBle.strip.id));
    await tester.tap(find.descendant(of: row, matching: find.text('Conectar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver a Inicio'));
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
    // On with a colorless mode (music): color unknown again, so the calm gradient returns.
    await send(tester, () => c.setVoiceMode(1));
    expect(paint().gradient, unknown);
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

  testWidgets('Home connection card stays compact and Cambiar opens the selector', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
    final card = find.byType(GlassCard).first;
    // Measured at 412×915 on the previous disconnected Inicio card.
    expect(tester.getSize(card).height, lessThanOrEqualTo(181));
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir tira'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a Inicio'));
    await tester.pumpAndSettle();
  });

  final selectorScroll = find.descendant(of: find.byKey(const Key('strip-selector-list')),
    matching: find.byType(Scrollable), matchRoot: false).first;

  testWidgets('selector states, management actions and expansion persist', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = [
      for (var i = 1; i <= 4; i++) RememberedStrip('$i', 'LEDDMX $i', alias: 'Tira $i'),
    ];
    final models = Models(store, presetIds: {});
    await models.saveRememberedStrips(saved);
    ble.results = [saved[1], saved[2], FakeBle.strip];
    final c = await start(tester);
    await c.reconnect();
    await tester.pumpAndSettle();
    expect(find.text('Desconectar'), findsOneWidget);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(find.text('MIS TIRAS · 4'), findsOneWidget);
    Finder row(String id) => find.byKey(ValueKey(id));
    Finder within(String id, Finder child) => find.descendant(of: row(id), matching: child);
    expect(within('1', find.text('Conectado')), findsOneWidget);
    expect(within('2', find.text('Recordada')), findsOneWidget);
    expect(within('3', find.text('Recordada')), findsOneWidget);
    expect(within('4', find.text('Fuera de alcance')), findsOneWidget);
    final firstCard = tester.getRect(within('1', find.byType(Material)).first);
    final secondCard = tester.getRect(within('2', find.byType(Material)).first);
    expect(secondCard.top - firstCard.bottom, greaterThanOrEqualTo(10));
    expect(firstCard.left, greaterThanOrEqualTo(18));
    expect(412 - firstCard.right, greaterThanOrEqualTo(18));
    await tester.scrollUntilVisible(row('fake'), 140, scrollable: selectorScroll);
    expect(within('fake', find.text('Conectar')), findsOneWidget);
    await tester.scrollUntilVisible(row('1'), -140, scrollable: selectorScroll);
    await tester.ensureVisible(within('1', find.byTooltip('Renombrar')));
    await tester.tap(within('1', find.byTooltip('Renombrar')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Sala  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(within('1', find.text('Sala')), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Sala'), findsOneWidget);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();

    Future<void> menu(String name) async {
      await tester.longPress(find.text(name));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SimpleDialogOption, 'Renombrar'), findsOneWidget);
      expect(find.widgetWithText(SimpleDialogOption, 'Olvidar'), findsOneWidget);
    }
    await menu('Sala');
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Renombrar'));
    await tester.pumpAndSettle();
    expect(find.text('Renombrar tira'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await menu('Sala');
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Olvidar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Olvidar Sala en este teléfono?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await menu('Sala');
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Desconectar'));
    await tester.pumpAndSettle();
    expect(within('1', find.text('Conectar')), findsOneWidget);
    await menu('Sala');
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Conectar'));
    await tester.pumpAndSettle();
    expect(within('1', find.text('Desconectar')), findsOneWidget);
    await tester.tap(within('2', find.text('Conectar')));
    await tester.pumpAndSettle();
    expect(ble.disconnects, ['1', '1']);
    expect(c.remembered?.id, '2');
    expect(within('2', find.text('Desconectar')), findsOneWidget);

    await tester.tap(within('1', find.byTooltip('Olvidar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(row('1'), findsOneWidget);
    await tester.tap(within('1', find.byTooltip('Olvidar')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Olvidar'));
    await tester.pumpAndSettle();
    expect(row('1'), findsNothing);
    expect(c.link.strip?.id, '2');
    expect(c.link.ready, isTrue);
    expect(models.loadRememberedStrips().map((strip) => strip.id), ['2', '3', '4']);

    final section = find.text('MIS TIRAS · 3');
    await tester.tap(section);
    await tester.pumpAndSettle();
    expect(row('2'), findsNothing);
    await tester.tap(find.byTooltip('Volver a Inicio'));
    await tester.pumpAndSettle();
    await start(tester);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(row('2'), findsNothing);
    await tester.tap(section);
    await tester.pumpAndSettle();
    expect(row('2'), findsOneWidget);
    expect(models.loadStripsExpanded(), isTrue);
    await tester.tap(find.byTooltip('Volver a Inicio'));
    await tester.pumpAndSettle();
  });

  for (final id in ['saved', 'fake']) {
    testWidgets('selector keeps connection failure and retry on row $id', (tester) async {
      await Models(store, presetIds: {}).saveRememberedStrips([
        const RememberedStrip('saved', 'LEDDMX Saved'),
      ]);
      await start(tester);
      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      Finder within(Finder child) => find.descendant(of: find.byKey(ValueKey(id)), matching: child);
      final error = find.text('No se pudo conectar.');
      final retry = find.text('Reintentar');
      expect(find.byType(TextField), findsNothing);
      ble.unreachable.add(id);
      await tester.tap(within(find.text('Conectar')));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();
      expect(error, findsOneWidget);
      expect(within(error), findsOneWidget);
      expect(within(retry), findsOneWidget);
      ble.unreachable.remove(id);
      await tester.tap(within(retry));
      await tester.pumpAndSettle();
      expect(error, findsNothing);
      expect(retry, findsNothing);
      expect(within(find.text('Desconectar')), findsOneWidget);
    });
  }

  testWidgets('selector compact actions and normalized search', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await Models(store, presetIds: {}).saveRememberedStrips([
      const RememberedStrip('one', 'LEDDMX Ático', alias: 'Rincón'),
      const RememberedStrip('two', 'LEDDMX Cocina'),
    ]);
    ble.results = [const Strip('one', 'LEDDMX Ático'), const Strip('three', 'LEDDMX Ñandú'), FakeBle.strip];
    await start(tester);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('one'));
    Finder within(Finder child) => find.descendant(of: row, matching: child);
    expect(tester.getSize(within(find.byType(Material)).first).height, lessThanOrEqualTo(104)); // Larger icons and pill (L34) with 48 dp targets; first version was 141 dp.
    final actionY = tester.getCenter(within(find.text('Conectar'))).dy;
    for (final label in ['Renombrar', 'Olvidar']) {
      final icon = within(find.byTooltip(label));
      expect(tester.getSize(icon), const Size(48, 48));
      expect(tester.getCenter(icon).dy, lessThan(actionY));
    }
    final search = find.byType(TextField);
    expect(find.text('Buscar tira'), findsOneWidget);
    for (final query in ['RINCON', 'atico']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.text('LEDDMX Cocina'), findsNothing);
      expect(find.text('LEDDMX Ñandú'), findsNothing);
    }
    await tester.enterText(search, 'nandu');
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(find.text('LEDDMX Ñandú'), findsOneWidget);
    await tester.enterText(search, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron tiras.'), findsOneWidget);
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
    expect(store.read(Models.rememberedStripsKey), contains(FakeBle.strip.name));
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

  testWidgets('a drag on the disabled speed slider does not change tab', (tester) async {
    await start(tester);
    final slider = find.byKey(const Key('speed'));
    await tester.scrollUntilVisible(slider, 120);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final selected = find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true);
    expect(find.ancestor(of: find.text('Inicio'), matching: selected), findsOneWidget);
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
    // Without an alias the name shows once, with a short description below.
    expect(find.text(FakeBle.strip.name), findsOneWidget);
    expect(find.text('Controlador de tira LED'), findsOneWidget);
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
      final models = Models(store, presetIds: {});
      await models.saveRememberedStrips([
        for (var i = 0; i < 4; i++) RememberedStrip('$i', 'LEDDMX-03-LONG-NAME-$i', alias: 'Alias largo de la tira $i'),
      ]);
      await start(tester);
      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Buscar de nuevo'), 160, scrollable: selectorScroll);
      expect(find.text('Buscar de nuevo').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Volver a Inicio'));
      await tester.pumpAndSettle();
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
