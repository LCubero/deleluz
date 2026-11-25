import 'dart:async';
import 'dart:typed_data';

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/link.dart';
import 'package:deleluz/main.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/color_disc.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  Future<void>? opening;
  Stream<Strip>? scanResults;
  var scans = 0;
  var scanStops = 0;
  final writes = <Uint8List>[];
  final changes = StreamController<(String, bool)>.broadcast();
  @override
  Future<void> connect(String id) async {
    connections.add(id);
    if (opening != null) await opening;
    if (unreachable.contains(id)) throw StateError('Fake connection failure');
  }

  final unreachable = <String>{};
  @override
  Future<void> disconnect(String id) async => disconnects.add(id);
  @override
  Future<bool> hasWriteWithoutResponse(String id) async => true;
  @override
  Stream<Strip> scan() {
    scans++;
    return scanResults ?? Stream.fromIterable(results);
  }
  @override
  Future<void> stopScan() async { scanStops++; }
  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (failWrite?.call(bytes) == true) throw StateError('Fake write failure');
    writes.add(bytes);
  }
  bool Function(Uint8List)? failWrite;
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
    }, now: () => now, wallClock: () => DateTime(2026, 1, 1, 23, 55, 1));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MainApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final (state, connect) in [
    (AppLifecycleState.inactive, false),
    (AppLifecycleState.hidden, false),
    (AppLifecycleState.inactive, true),
    (AppLifecycleState.hidden, true),
  ]) {
    testWidgets('pending ${connect ? 'connect' : 'scan'} permission across ${state.name} and resumed', (tester) async {
      final permission = Completer<String?>();
      final controller = AppController(ble, store, checkAccess: (request) {
        expect(request, isTrue);
        return permission.future;
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(MainApp(controller: controller));
      final action = connect ? controller.connect(FakeBle.strip) : controller.startScan();
      tester.binding.handleAppLifecycleStateChanged(state);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      permission.complete(null);
      await action;
      await tester.pump();
      final expected = state == AppLifecycleState.inactive;
      if (connect) {
        expect(ble.connections, expected ? [FakeBle.strip.id] : isEmpty);
      } else {
        expect(controller.devices, expected ? [FakeBle.strip] : isEmpty);
      }
    });
  }

  for (final recovery in [false, true]) {
    testWidgets('cancel ${recovery ? 'recovery' : 'selector connect'} releases a late open', (tester) async {
      final c = await start(tester);
      final lateOpen = Completer<void>();
      final row = find.byKey(ValueKey(FakeBle.strip.id));
      if (recovery) {
        await c.connect(FakeBle.strip);
        ble.opening = lateOpen.future;
        ble.changes.add((FakeBle.strip.id, false));
      } else {
        await tester.tap(find.text('Conectar'));
        await tester.pumpAndSettle();
        ble.opening = lateOpen.future;
        await tester.tap(find.descendant(of: row, matching: find.text('Conectar')));
      }
      await tester.pump();
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      final fallback = recovery ? LinkStatus.lost : LinkStatus.idle;
      expect(c.link.status, fallback);
      expect(c.busy, isFalse);
      lateOpen.complete();
      await tester.pump(const Duration(seconds: 2));
      expect(c.link.status, fallback);
      expect(ble.disconnects, [FakeBle.strip.id]);
      expect(ble.connections, List.filled(recovery ? 2 : 1, FakeBle.strip.id));
      expect(c.message, isNull);
      expect(find.text('No se pudo conectar.'), findsNothing);
    });
  }

  testWidgets('cancel during retry backoff prevents another attempt', (tester) async {
    final c = await start(tester);
    await c.connect(FakeBle.strip);
    await c.disconnect();
    ble.connections.clear();
    ble.unreachable.add(FakeBle.strip.id);
    await tester.pump();
    await tester.tap(find.text('Reconectar'));
    await tester.pump();
    expect(ble.connections, [FakeBle.strip.id]);
    // Cancelar is grey glass, never the Conectar gradient (L54).
    final cancelBox = tester.widget<DecoratedBox>(find.ancestor(of: find.text('Cancelar'),
      matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
    expect(cancelBox.gradient, isNull);
    expect(cancelBox.color, isNotNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(seconds: 2));
    expect(ble.connections, [FakeBle.strip.id]);
    expect(c.link.status, LinkStatus.idle);
    expect(c.message, isNull);
  });

  for (final scan in [false, true]) {
    testWidgets('cancel pending ${scan ? 'scan' : 'connect'} permission discards a late error', (tester) async {
      final permission = Completer<String?>();
      await Models(store, presetIds: {}).saveRememberedStrips([
        const RememberedStrip('fake', 'LEDDMX Test'),
      ]);
      final c = AppController(ble, store, checkAccess: (_) => permission.future);
      addTearDown(c.dispose);
      await tester.pumpWidget(MainApp(controller: c));
      await tester.tap(find.text(scan ? 'Cambiar' : 'Reconectar'));
      await tester.pumpAndSettle();
      expect(c.busy, isTrue);
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      expect(c.busy, isFalse);
      permission.completeError(StateError('Late permission error'));
      await tester.pumpAndSettle();
      expect(c.message, isNull);
      expect(ble.scans, 0);
      expect(ble.connections, isEmpty);
    });
  }

  testWidgets('cancel an active scan without marking it completed', (tester) async {
    final results = StreamController<Strip>();
    ble.scanResults = results.stream;
    final c = await start(tester);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(c.scanning, isTrue);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    unawaited(results.close());
    await tester.pump();
    expect(c.scanning, isFalse);
    expect(c.scanCompleted, isFalse);
    expect(c.message, isNull);
    expect(ble.scanStops, 1);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('device preview wraps both ways without changing tabs at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await start(tester);
      for (final id in ['C', 'B', 'A']) {
        await c.connect(Strip(id, 'LEDDMX $id'));
        c.renameStrip(id, 'Alias $id');
      }
      await tester.pumpAndSettle();
      ble.connections.clear();
      ble.disconnects.clear();
      Future<void> swipe(String from, String to, double dx, int dot) async {
        await tester.drag(find.text('Alias $from'), Offset(dx, 0));
        await tester.pumpAndSettle();
        expect(find.text('Alias $to'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          final indicator = tester.widget<DecoratedBox>(find.byKey(ValueKey('strip-dot-$i')));
          expect((indicator.decoration as BoxDecoration).color, i == dot ? glowViolet : glowFaint);
        }
        expect(tester.takeException(), isNull);
      }
      await swipe('A', 'B', -85, 1);
      await swipe('B', 'C', -85, 2);
      await swipe('C', 'A', -85, 0);
      await swipe('A', 'C', 85, 2);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(c.setupDevice?.id, 'A');
      expect(ble.connections, isEmpty);
      expect(ble.disconnects, isEmpty);
      expect(ble.writes, isEmpty);
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(ble.disconnects, ['A']);
      expect(ble.connections, ['C']);
      expect(c.setupDevice?.id, 'C');
      expect(find.text('Desconectar'), findsOneWidget);
    });
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

  testWidgets('selector shows the Bluetooth name once without an alias', (tester) async {
    await Models(store, presetIds: {}).saveRememberedStrips([
      RememberedStrip('1', 'LEDDMX 1'),
    ]);
    await start(tester);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(find.text('LEDDMX 1'), findsOneWidget);
  });

  void expectGlowDialog(WidgetTester tester, String action) {
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((dialog.shape as RoundedRectangleBorder?)?.side.color, glowLine);
    final primary = find.widgetWithText(FilledButton, action);
    expect(find.ancestor(of: primary, matching: find.byWidgetPredicate((widget) =>
      widget is Ink && (widget.decoration as ShapeDecoration?)?.gradient == glowStrongGradient)),
      findsOneWidget);
    final cancel = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'));
    expect(cancel.style?.foregroundColor?.resolve({}), Colors.grey);
  }

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
    expectGlowDialog(tester, 'Guardar');
    await tester.enterText(find.byType(TextFormField), '  Sala  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(within('1', find.text('Sala')), findsOneWidget);
    expect(within('1', find.text('LEDDMX 1')), findsOneWidget);
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
    expectGlowDialog(tester, 'Olvidar');
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

  Future<void> timerTap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('timer sheet counts down, extends and cancels', (tester) async {
    final c = await start(tester);
    await connect(tester);
    c.startTimer(3601, fade: false);
    await timerTap(tester, find.byTooltip(c.text('offTimer')));
    expect(find.text('1:00:01'), findsOneWidget);
    expect(find.text('Se apaga a las 00:55'), findsOneWidget);
    expect(find.text(c.text('startTimer')), findsNothing);
    now = 2000;
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('59:59'), findsOneWidget);
    await timerTap(tester, find.text('+5 min'));
    expect(find.text('1:04:59'), findsOneWidget);
    await timerTap(tester, find.text('+15 min'));
    expect(find.text('1:19:59'), findsOneWidget);
    expect(find.text('Se apaga a las 01:15'), findsOneWidget);
    await timerTap(tester, find.text(c.text('cancelTimer')));
    expect(c.remaining, isNull);
    expect(find.text(c.text('startTimer')), findsOneWidget);
    now = 6000000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes, isEmpty);
  });

  testWidgets('timer sheet validates custom seconds and remembers them on reload', (tester) async {
    final c = await start(tester);
    await timerTap(tester, find.byTooltip(c.text('offTimer')));
    expect(find.text(c.text('connectFirst')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, c.text('startTimer'))).onPressed, isNull);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, c.text('minutes15'))).selected, isTrue);
    await timerTap(tester, find.byTooltip(c.text('close')));
    await connect(tester);
    await timerTap(tester, find.byTooltip(c.text('offTimer')));
    await timerTap(tester, find.text(c.text('custom')));
    final minutes = find.widgetWithText(TextField, c.text('minutes'));
    final seconds = find.widgetWithText(TextField, c.text('seconds'));
    await tester.enterText(minutes, '0');
    await tester.enterText(seconds, '0');
    await timerTap(tester, find.text(c.text('startTimer')));
    expect(find.text(c.text('invalidTimer')), findsOneWidget);
    await tester.enterText(seconds, '1');
    await timerTap(tester, find.text(c.text('startTimer')));
    expect(c.remaining, 1);
    expect(find.text('0:01'), findsOneWidget);
    now = 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(ble.writes.single.sublist(2, 4), [4, 0]);
    await tester.pumpWidget(const SizedBox());
    final reloaded = await start(tester);
    await timerTap(tester, find.byTooltip(reloaded.text('offTimer')));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, c.text('custom'))).selected, isTrue);
    expect(tester.widget<TextField>(minutes).controller!.text, '0');
    expect(tester.widget<TextField>(seconds).controller!.text, '1');
  });

  testWidgets('extending an ongoing fade restores brightness until the new fade window', (tester) async {
    final c = await start(tester);
    await connect(tester);
    c.startTimer(10, fade: true);
    await tester.pump();
    expect(ble.writes.single[4], lessThan(c.brightness));
    now = 1000;
    c.extendTimer(300);
    await tester.pump(const Duration(seconds: 1));
    expect(c.remaining, 309);
    expect(ble.writes, hasLength(2));
    expect(ble.writes.last[4], c.brightness);
    now = 255000;
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.remaining, 55);
    expect(ble.writes, hasLength(3));
    expect(ble.writes.last[4], lessThan(c.brightness));
    now += 250;
    c.cancelTimer(restoreBrightness: true);
    await tester.pump(const Duration(milliseconds: 250));
    expect(ble.writes, hasLength(4));
    expect(ble.writes.last[4], c.brightness);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('timer sheet fits $size with enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await start(tester);
      await connect(tester);
      final title = find.text(c.text('offTimer'));
      void checkTitle() {
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.didExceedMaxLines, isFalse);
        if (size.width == 320) {
          final boxes = paragraph.getBoxesForSelection(TextSelection(
            baseOffset: 0, extentOffset: c.text('offTimer').length));
          expect(boxes.map((box) => box.top).toSet(), hasLength(greaterThan(1)));
        }
        expect(tester.takeException(), isNull);
      }
      await timerTap(tester, find.byTooltip(c.text('offTimer')));
      checkTitle();
      await timerTap(tester, find.text(c.text('custom')));
      expect(find.widgetWithText(TextField, c.text('seconds')), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.startTimer(43200, fade: false);
      await tester.pumpAndSettle();
      checkTitle();
      expect(find.text('12:00:00'), findsOneWidget);
    });
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String name) async {
    await tester.tap(find.descendant(of: find.byType(InkWell),
      matching: find.text(name)).hitTestable().last);
    await tester.pumpAndSettle();
  }

  Finder sliderLabel(AppController c, String key) => find.byWidgetPredicate(
    (widget) => widget is GlowValueLabel && widget.label == c.text(key));

  for (final (tab, panel, label, enabled) in [
    ('Inicio', null, 'speed', false),
    ('Inicio', null, 'speed', true),
    ('Inicio', null, 'brightness', true),
    ('Color', null, 'brightness', true),
    ('Color', 'color-effects', 'speed', true),
    ('Escenas', 'scenes-music', 'micSensitivity', true),
    ('Escenas', 'scenes-mine', 'brightness', true),
  ]) {
    testWidgets('$tab $panel $label ($enabled) label drag stays in place', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await start(tester);
      if (tab == 'Inicio' && label == 'speed' && enabled) {
        await connect(tester);
        await send(tester, () => c.setEffect(1));
      }
      if (tab != 'Inicio') await tapTab(tester, tab);
      if (panel != null) await tapKey(tester, panel);
      if (panel == 'scenes-mine') await tapKey(tester, 'scene-new');
      final target = sliderLabel(c, label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.dragFrom(tester.getCenter(target.hitTestable()), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
        ['Inicio', 'Color', 'Escenas'].indexOf(tab));
      if (panel == 'scenes-mine') {
        await tapKey(tester, 'scene-close');
        expect(find.byKey(const Key('scene-new')).hitTestable(), findsOneWidget);
      }
    });
  }

  testWidgets('included scene interval label drag keeps the preview open', (tester) async {
    final c = await start(tester);
    await tapTab(tester, 'Escenas');
    await tapKey(tester, 'scenes-included');
    await tester.longPress(find.byKey(const Key('included-police')));
    await tester.pumpAndSettle();
    final target = sliderLabel(c, 'stepInterval');
    final slider = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Slider));
    final value = tester.widget<Slider>(slider).value;
    await tester.dragFrom(tester.getCenter(target.hitTestable()), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, value);
    await tapKey(tester, 'scene-close');
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
  });

  testWidgets('track drag sends brightness and vertical drag on the label scrolls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await start(tester);
    await connect(tester);
    final track = find.byKey(const Key('brightness'));
    final label = sliderLabel(c, 'brightness');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).hitTestable());
    final beforeScroll = scroll.position.pixels;
    await tester.dragFrom(tester.getCenter(sliderLabel(c, 'speed').hitTestable()), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(beforeScroll));
    await tester.ensureVisible(track);
    await tester.pumpAndSettle();
    final beforeValue = c.brightness;
    now += 60;
    await tester.dragFrom(tester.getCenter(track.hitTestable()), const Offset(-100, 0));
    for (var i = 0; i < 4; i++) {
      now += 60;
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(c.brightness, lessThan(beforeValue));
    expect(ble.writes.last, orderedEquals(wire.brightness(c.brightness)));
    expect(label.hitTestable(), findsOneWidget);
  });

  testWidgets('Settings Devices shows the alias and opens the shared selector', (tester) async {
    await Models(store, presetIds: {}).saveRememberedStrips([
      const RememberedStrip('fake', 'LEDDMX Test', alias: 'Rincón'),
    ]);
    final c = await start(tester);
    await tapTab(tester, 'Ajustes');
    expect(find.descendant(
      of: find.ancestor(of: find.text('Dispositivos'), matching: find.byType(ListTile)),
      matching: find.text('Rincón'),
    ).hitTestable(), findsOneWidget);
    await tester.tap(find.text('Dispositivos'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir tira'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Dispositivos').hitTestable(), findsOneWidget);
    c.setLanguage('en');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a strip'), findsOneWidget);
  });

  for (final (tab, panel, alternate, defaultPanel, selection) in [
    ('Color', 'color-effects', 'color-speed', 'color-solid', false),
    ('Escenas', 'scenes-music', 'scene-sensitivity', 'scenes-mine', 'mine'),
  ]) {
    testWidgets('$tab resets its segment on tap and swipe entry without sending', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await start(tester);
      await connect(tester);
      await send(tester, () => c.setEffect(1));
      final writes = ble.writes.length;
      await tapTab(tester, tab);
      await tapKey(tester, panel);
      expect(find.byKey(Key(alternate)), findsOneWidget);
      await tapTab(tester, 'Inicio');
      await tapTab(tester, tab);
      expect(find.byKey(Key(alternate)), findsNothing);
      final segments = find.ancestor(of: find.byKey(Key(defaultPanel)),
        matching: find.byWidgetPredicate((widget) => widget is GlowSegments));
      expect(tester.widget<GlowSegments>(segments).selected, selection);
      await tapKey(tester, panel);
      if (tab == 'Color') await tester.enterText(find.byKey(const Key('effect-search')), '42');
      await tapTab(tester, tab == 'Color' ? 'Inicio' : 'Ajustes');
      final header = tester.getRect(find.byType(GlowHeader));
      final dx = tab == 'Color' ? -180.0 : 180.0;
      await tester.dragFrom(header.bottomCenter + const Offset(0, 5), Offset(dx, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<GlowSegments>(segments).selected, selection);
      expect(ble.writes, hasLength(writes));
      expect(c.hasActiveEffect, isTrue);
    });
  }

  testWidgets('disc and Favorites keep color gestures in the Color tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
    await tapTab(tester, 'Color');
    final disc = find.byKey(const Key('color-disc'));
    final picker = find.byType(ColorDisc);
    HSVColor selection() => HSVColor.fromColor(tester.widget<ColorDisc>(picker).color);
    await tester.tapAt(tester.getCenter(disc) + const Offset(80, 0));
    await tester.pumpAndSettle();
    final tappedHue = selection().hue;
    expect(tappedHue, closeTo(90, 1));
    await tester.dragFrom(tester.getCenter(disc) + const Offset(0, -70), const Offset(-170, 0));
    await tester.pumpAndSettle();
    expect(disc.hitTestable(), findsOneWidget);
    expect(selection().hue, isNot(closeTo(tappedHue, 1)));
    await tester.binding.setSurfaceSize(const Size(412, 600));
    await tester.pumpAndSettle();
    final page = tester.state<ScrollableState>(find.byType(Scrollable).hitTestable());
    final before = page.position.pixels;
    await tester.drag(disc, const Offset(0, -85));
    await tester.pumpAndSettle();
    expect(selection().hue, 0);
    expect(page.position.pixels, before);
    await tester.dragFrom(tester.getRect(disc).centerRight + const Offset(24, 0),
      const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(page.position.pixels, greaterThan(before));
    await tester.ensureVisible(find.byKey(const Key('color-favorites')));
    await tapKey(tester, 'color-favorites');
    final favorite = find.byKey(const Key('favorite-#00ff00'));
    await tester.ensureVisible(favorite);
    await tester.drag(favorite, const Offset(-170, 0));
    await tester.pumpAndSettle();
    expect(favorite.hitTestable(), findsOneWidget);
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(selection().hue, 120);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pumpAndSettle();
    final headerFinder = find.byType(GlowHeader);
    await tester.ensureVisible(headerFinder);
    await tester.pumpAndSettle();
    final header = tester.getRect(headerFinder);
    await tester.dragFrom(header.bottomCenter + const Offset(0, 5), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scenes-mine')), findsOneWidget);
  });

  testWidgets('editor step swipes stay in their zone and taps open the color picker', (tester) async {
    await start(tester);
    await tapTab(tester, 'Escenas');
    await tapKey(tester, 'scene-new');
    final frame = find.byKey(const Key('scene-frame-1'));
    expect(find.ancestor(of: frame, matching: find.byType(SliderZone)), findsOneWidget);
    await tester.drag(frame, const Offset(-170, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    await tester.tap(frame);
    await tester.pumpAndSettle();
    expect(tester.widget<ColorDisc>(find.byType(ColorDisc)).color, const Color(0xffffc800));
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
      final firstRow = find.byKey(const ValueKey('0'));
      for (final (tooltip, action) in [('Renombrar', 'Guardar'), ('Olvidar', 'Olvidar')]) {
        final icon = find.descendant(of: firstRow, matching: find.byTooltip(tooltip));
        await tester.ensureVisible(icon);
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, action).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await tester.pumpAndSettle();
      }
      final scanAgain = find.text('Buscar de nuevo');
      await tester.scrollUntilVisible(scanAgain, 160, scrollable: selectorScroll);
      await tester.ensureVisible(scanAgain);
      await tester.pumpAndSettle();
      expect(scanAgain.hitTestable(), findsOneWidget);
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
