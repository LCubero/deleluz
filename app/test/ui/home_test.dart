import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, Tristate;

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/link.dart';
import 'package:deleluz/main.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/model/timer.dart';
import 'package:deleluz/protocol.dart' as wire;
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/notice.dart';
import 'package:deleluz/ui/color_disc.dart';
import 'package:deleluz/ui/timer_sheet.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universal_ble/universal_ble.dart' show AvailabilityState;

class Store implements LocalStore {
  final values = <String, String>{};
  String? refusedKey;
  @override
  String? read(String key) => values[key];
  @override
  Future<bool> write(String key, String? value) async {
    if (key == refusedKey) return false;
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

  Future<AppController> start(WidgetTester tester, {
    Future<AvailabilityState> Function()? readBluetooth,
    Stream<AvailabilityState>? bluetoothChanges,
    Future<void> Function()? requestBluetooth,
  }) async {
    final controller = AppController(ble, store, checkAccess: (request) async {
      accessChecks.add(request);
      return accessProblem;
    }, readBluetooth: readBluetooth, bluetoothChanges: bluetoothChanges, requestBluetooth: requestBluetooth,
      now: () => now, wallClock: () => DateTime(2026, 1, 1, 23, 55, 1));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MainApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  void useOwnerPhoneView(WidgetTester tester) {
    const density = 2.625;
    tester.view.devicePixelRatio = density;
    tester.view.physicalSize = const Size(1080, 2189);
    const statusBar = FakeViewPadding(top: 32 * density);
    tester.view.padding = statusBar;
    tester.view.viewPadding = statusBar;
    addTearDown(tester.view.reset);
  }

  void expectBrightnessAboveNavigation(WidgetTester tester, String key) {
    final slider = find.byKey(Key(key));
    final card = find.ancestor(of: slider, matching: find.byType(GlassCard));
    final viewport = find.ancestor(of: slider, matching: find.byType(SingleChildScrollView));
    expect(tester.getTopLeft(card).dy, greaterThanOrEqualTo(tester.getTopLeft(viewport).dy));
    final nav = tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar!;
    final navTop = tester.getTopLeft(find.byWidget(nav)).dy;
    final cardBottom = tester.getBottomLeft(card).dy;
    debugPrint('$key: Brillo bottom=$cardBottom dp; navigation top=$navTop dp');
    expect(cardBottom, lessThanOrEqualTo(navTop));
  }

  for (final width in [320.0, 412.0]) {
    for (final language in ['es', 'en']) {
      testWidgets('Inicio timer OFF retry at $width dp in $language with large text', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = await start(tester);
        c.setLanguage(language);
        await c.connect(FakeBle.strip);
        ble.failWrite = (_) => true;
        c.startTimer(1, fade: false);
        now += 1000;
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text(c.text('timerOffFailed')), findsOneWidget);
        final retry = find.widgetWithText(OutlinedButton, c.text('retryTimerOff'));
        expect(retry, findsOneWidget);
        c.setForeground(false);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);
        c.setForeground(true);
        ble.failWrite = null;
        await tester.pumpAndSettle();
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        expect(tester.getSize(retry).shortestSide, greaterThanOrEqualTo(48));
        expect(find.bySemanticsLabel(c.text('retryTimerOff')), findsOneWidget);
        now += 50; // Allow the next paced BLE write after the failed OFF.
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(ble.writes, [wire.power(false)]);
        expect(retry, findsNothing);
        expect(find.text(c.text('timerOffFailed')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Inicio fits the whole brightness card on the owner phone', (tester) async {
    useOwnerPhoneView(tester);
    final c = await start(tester);
    expect(c.shortcuts, hasLength(2));
    expect(find.byTooltip(c.text('addShortcut')), findsNothing);
    expectBrightnessAboveNavigation(tester, 'brightness');
    expect(find.byKey(const Key('speed')), findsNothing);
  });

  for (final (language, prefix) in [
    ('es', 'Último comando enviado:'), ('en', 'Last command sent:'),
  ]) {
    testWidgets('Inicio shows the full command status without moving brightness ($language)', (tester) async {
      useOwnerPhoneView(tester);
      final c = await start(tester);
      c.setLanguage(language);
      await c.connect(FakeBle.strip);
      await tester.pumpAndSettle();
      final card = find.ancestor(of: find.byKey(const Key('brightness')), matching: find.byType(GlassCard));
      final before = tester.getRect(card);
      final sent = c.setEffect(1);
      for (var i = 0; i < 4; i++) {
        now += 60;
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(await sent, isTrue);
      await tester.pumpAndSettle();
      expect(find.textContaining(prefix), findsOneWidget);
      expect(tester.getRect(card), before);
    });
  }

  testWidgets('Color fijo fits the whole brightness card on the owner phone', (tester) async {
    useOwnerPhoneView(tester);
    await store.write('deleluz.app.favoritesOpen.color', '0');
    await start(tester);
    await tester.tap(find.text('Color').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('favorite-plus')), findsNothing);
    final disc = tester.getSize(find.byKey(const Key('color-disc'))).width;
    debugPrint('Color fijo: disc=$disc dp');
    expectBrightnessAboveNavigation(tester, 'color-brightness');
    final tones = ['Cálido', 'Neutro', 'Frío'].map((label) =>
      tester.getRect(find.widgetWithText(ChoiceChip, label))).toList();
    for (final tone in tones) {
      expect(tone.top, tones.first.top);
      expect(tone.shortestSide, greaterThanOrEqualTo(48));
    }
    expect(disc, greaterThanOrEqualTo(216));
    expect(find.text('Blancos'), findsNothing);
    expect(find.bySemanticsLabel('Blancos'), findsOneWidget);
    for (var i = 1; i < tones.length; i++) {
      expect(tones[i].left - tones[i - 1].right, closeTo(8, .01));
    }
    await tester.tap(find.byKey(const Key('color-effects')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('color-speed'))).dy,
      greaterThan(tester.getBottomLeft(find.byKey(const Key('color-brightness'))).dy));
  });

  testWidgets('segmented check precedes the label on the same row', (tester) async {
    await start(tester);
    await tester.tap(find.text('Color').last);
    await tester.pumpAndSettle();
    final selected = find.byKey(const Key('color-solid'));
    final other = find.byKey(const Key('color-effects'));
    final check = find.descendant(of: find.byType(GlowSegments<bool>), matching: find.byIcon(Icons.check));
    expect(tester.getCenter(check).dx, lessThan(tester.getTopLeft(selected).dx));
    final labelTop = tester.getTopLeft(selected).dy;
    expect(tester.getTopLeft(check).dy, lessThan(tester.getBottomLeft(selected).dy));
    expect(tester.getBottomLeft(check).dy, greaterThan(labelTop));
    // Both labels use the same text metrics, so their first line tops align with their baselines.
    expect(labelTop, closeTo(tester.getTopLeft(other).dy, 1));
  });

  testWidgets('navigation shows a highlight without a check', (tester) async {
    await start(tester);
    final nav = tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar!;
    expect(find.descendant(of: find.byWidget(nav), matching: find.byIcon(Icons.check)), findsNothing);
    expect(find.ancestor(of: find.text('Inicio'), matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.selected == true)), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('Home Bluetooth warning and enable request at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final radio = StreamController<AvailabilityState>.broadcast();
      addTearDown(radio.close);
      var requests = 0;
      final c = await start(tester, readBluetooth: () async => AvailabilityState.poweredOff,
        bluetoothChanges: radio.stream, requestBluetooth: () async { requests++; });
      final title = find.text('Bluetooth apagado');
      expect(title.hitTestable(), findsOneWidget);
      expect(find.text('Actívalo para conectar con la tira.').hitTestable(), findsOneWidget);
      final warningSurface = tester.widget<Material>(find.ancestor(of: title, matching: find.byType(Material)).first).color!;
      for (final label in [title, find.text('Actívalo para conectar con la tira.')]) {
        final textColor = tester.widget<Text>(label).style!.color!;
        expect((textColor.computeLuminance() + .05) / (warningSurface.computeLuminance() + .05),
          greaterThanOrEqualTo(4.5));
      }
      final brightness = find.byKey(const Key('brightness'));
      final unavailable = find.text('Control no disponible');
      final power = find.byKey(const Key('power'));
      final change = find.widgetWithText(TextButton, 'Cambiar');
      Future<void> show(Finder target, double delta) async {
        await tester.scrollUntilVisible(target, delta);
        await tester.pumpAndSettle();
      }
      await show(change, 100);
      expect(tester.widget<TextButton>(change).onPressed, isNull);
      await show(power, 100);
      expect(tester.widget<IconButton>(power).onPressed, isNull);
      await show(unavailable, 100);
      expect(unavailable.hitTestable(), findsOneWidget);
      await show(brightness, 100);
      expect(tester.widget<Slider>(brightness).onChanged, isNull);
      final enable = find.text('Activar Bluetooth');
      await show(enable, -100);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(title, findsOneWidget); // Request completion alone does not mean Bluetooth is on.
      radio.add(AvailabilityState.poweredOn);
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      await show(change, 100);
      expect(tester.widget<TextButton>(change).onPressed, isNotNull);
      await show(brightness, 100);
      expect(tester.widget<Slider>(brightness).onChanged, isNotNull);
      await c.connect(FakeBle.strip);
      await tester.pumpAndSettle();
      await show(power, -100);
      expect(tester.widget<IconButton>(power).onPressed, isNotNull);
      c.setLanguage('en');
      radio.add(AvailabilityState.poweredOff);
      await tester.pumpAndSettle();
      await show(find.text('Turn on Bluetooth'), -100);
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Turn it on to connect to the strip.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
    testWidgets('connection card swipes change preview, not the tab or connection, at $size', (tester) async {
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
      for (final (from, to, dx) in [('A', 'B', -85.0), ('B', 'A', 85.0)]) {
        await tester.drag(find.text('Alias $from'), Offset(dx, 0));
        await tester.pumpAndSettle();
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
        expect(find.text('Alias $to').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Desconectar'), findsOneWidget);
      expect(c.setupDevice?.id, 'A');
      expect(ble.connections, isEmpty);
      expect(ble.disconnects, isEmpty);
      expect(ble.writes, isEmpty);
      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      final target = find.descendant(of: find.byKey(const ValueKey('C')), matching: find.text('Conectar'));
      await tester.scrollUntilVisible(target, 100, scrollable: find.descendant(
        of: find.byKey(const Key('strip-selector-list')), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
      expect(ble.disconnects, ['A']);
      expect(ble.connections, ['C']);
      expect(c.setupDevice?.id, 'C');
      await tester.tap(find.byTooltip('Volver a Inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Alias C').hitTestable(), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
    });
  }

  testWidgets('notices show the corresponding leading icon and wrapped text', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: glowTheme(), home: const Scaffold(body: Column(children: [
      Notice('Information'),
      Notice('Warning', kind: NoticeKind.warning),
      Notice('Error', kind: NoticeKind.error),
    ]))));
    for (final (text, icon) in [('Information', Icons.info_outline),
      ('Warning', Icons.warning_amber_rounded), ('Error', Icons.error_outline)]) {
      final notice = find.ancestor(of: find.text(text), matching: find.byType(Notice));
      expect(find.descendant(of: notice, matching: find.byIcon(icon)), findsOneWidget);
    }
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('command status reserves two lines and wraps long readouts at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await start(tester);
      await c.connect(FakeBle.strip);
      await tester.pumpAndSettle();
      final quick = find.text('Acciones rápidas');
      await tester.scrollUntilVisible(quick, 100);
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      final before = tester.getTopLeft(quick).dy + position.pixels;
      final idle = find.text(c.text('noCommand'));
      final reserved = tester.getSize(idle).height;
      expect(await c.setChipConfig('GRB', 1024), isTrue);
      await tester.pumpAndSettle();
      final readout = find.textContaining('Último comando enviado:');
      expect(readout, findsOneWidget);
      expect(tester.widget<Text>(readout).data, contains('GRB · 1024 LEDs'));
      expect(tester.renderObject<RenderParagraph>(readout).didExceedMaxLines, isFalse);
      final growth = tester.getSize(readout).height - reserved;
      expect(growth, greaterThanOrEqualTo(0));
      expect(tester.getTopLeft(quick).dy + position.pixels, closeTo(before + growth, .01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home chevron tracks remaining scroll extent and fitting content', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
    final hint = find.byIcon(Icons.keyboard_arrow_down);
    expect(hint, findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('brightness')), 100);
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
  });

  testWidgets('expanded quick actions do not bring back speed or its hint', (tester) async {
    final c = await start(tester);
    await tester.tap(find.text('Acciones rápidas'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('speed')), findsNothing);
    expect(find.text(c.text('speedEffectsHint')), findsNothing);
  });

  Future<void> connect(WidgetTester tester) async {
    final connectButton = find.text('Conectar');
    await tester.ensureVisible(connectButton);
    await tester.pumpAndSettle();
    await tester.tap(connectButton);
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

  testWidgets('active effect follows the last sent mode, not the last command', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await start(tester);
    await connect(tester);
    expect(c.hasActiveEffect, isFalse);
    await send(tester, () => c.setEffect(210));
    expect(c.hasActiveEffect, isTrue);
    c.setSpeed(70);
    await tester.pump();
    expect(ble.writes.last, orderedEquals(wire.speed(70)));
    expect(c.hasActiveEffect, isTrue);

    await send(tester, () => c.applyShortcut({'kind': 'color', 'rgb': [1, 2, 3]}));
    expect(c.hasActiveEffect, isFalse);
    await send(tester, () => c.setEffect(wire.autoEffect));
    expect(c.hasActiveEffect, isTrue);
    await send(tester, () => c.setVoiceMode(2));
    expect(c.hasActiveEffect, isFalse);
    await send(tester, () => c.setEffect(1));
    await send(tester, () => c.playDraft([[10, 20, 30], [40, 50, 60]], 650, 50, preview: false));
    expect(c.hasActiveEffect, isFalse);
    await send(tester, () => c.setEffect(2));
    await send(tester, () async => c.setPower(false));
    expect(c.hasActiveEffect, isFalse);
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
    expect(c.hasActiveEffect, isFalse);
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
      expect(tester.renderObject<RenderParagraph>(status).didExceedMaxLines, isFalse);
      expect(find.text(controller.text('noCommand')),
        tab == 'Inicio' ? findsOneWidget : findsNothing);
      expect(find.descendant(of: header, matching: find.byType(ConnectionChip)).hitTestable(),
        tab == 'Inicio' ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Home shows an inactive strip preview and brightness', (tester) async {
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
    expect(find.text('Todas las escenas'), findsNothing);
    expect(find.byKey(const Key('brightness')).hitTestable(), findsOneWidget);
  });

  testWidgets('Home connection card stays compact and Cambiar opens the selector', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
    final card = find.byType(GlassCard).first;
    // Keep the compact card budget, allowing one extra line for the subtitle.
    expect(tester.getSize(card).height, lessThanOrEqualTo(200));
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir tira'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a Inicio'));
    await tester.pumpAndSettle();
  });

  testWidgets('stored Noche quick action keeps its label and sends #200400', (tester) async {
    const night = {'kind': 'color', 'rgb': [32, 4, 0], 'name': 'night'};
    await Models(store, presetIds: {}).saveShortcuts([night]);
    final c = await start(tester);
    expect(c.shortcuts.single, night);
    await c.connect(FakeBle.strip);
    await tester.pumpAndSettle();
    final title = find.text('Acciones rápidas');
    await tester.scrollUntilVisible(title, 100);
    await tester.tap(title);
    await tester.pumpAndSettle();
    final shortcut = find.text('Noche');
    expect(shortcut, findsOneWidget);
    await tester.ensureVisible(shortcut);
    await tester.pumpAndSettle();
    await tester.tap(shortcut);
    for (var i = 0; i < 3; i++) {
      now += 50;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ble.writes.last, wire.color(32, 4, 0));
    expect(c.models.loadShortcuts().single, night);
  });

  for (final (width, language) in [(320.0, 'es'), (320.0, 'en'), (412.0, 'es'), (412.0, 'en')]) {
    testWidgets('shared color picker and palette at $width dp in $language', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, width == 320 ? 640 : 915));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final models = Models(store, presetIds: {});
      await models.saveShortcuts([]);
      await models.savePalette(['#200400']);
      final c = await start(tester);
      c.setLanguage(language);
      await c.connect(FakeBle.strip);
      await tester.pumpAndSettle();
      final before = ble.writes.length;
      final shared = find.byKey(const Key('shared-color-picker'));
      Finder inside(String key) => find.descendant(of: shared, matching: find.byKey(Key(key)));
      Finder tone(String name) => find.descendant(of: shared, matching: find.widgetWithText(ChoiceChip, name));
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final title = find.text(c.text('quickActions'));
      await tester.scrollUntilVisible(title, 100);
      await tap(title);
      final add = find.byTooltip(c.text('addShortcut'));
      final confirm = find.widgetWithText(FilledButton, c.text('quickAdd'));
      await tap(add);
      await tap(find.byKey(const Key('quick-type-color')));
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
      expect(shared, findsOneWidget);
      expect(tone(c.text('night')), findsNothing);
      expect(find.text(c.text('whiteTones')), findsNothing);
      await tap(inside('color-favorites'));
      await tap(inside('favorite-#200400'));
      expect(ble.writes, hasLength(before));
      await tap(confirm);
      expect(c.models.loadShortcuts().single, {'kind': 'color', 'rgb': [32, 4, 0], 'name': 'night'});
      await tap(add);
      await tap(find.byKey(const Key('quick-type-color')));
      final neutral = tone(c.text('whiteNeutralTone'));
      await tap(neutral);
      expect(tester.getSemantics(neutral).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      await tap(confirm);
      expect(c.models.loadShortcuts().last, {'kind': 'color', 'rgb': [255, 228, 196], 'name': 'whiteNeutralTone'});
      expect(ble.writes, hasLength(before));

      await tap(find.text(c.text('scenes')).last);
      await tap(find.byKey(const Key('scene-new')));
      await tap(find.byKey(const Key('scene-add-color')));
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
      expect(shared, findsOneWidget);
      expect(tone(c.text('night')), findsNothing);
      await tap(inside('favorite-#200400'));
      expect(ble.writes, hasLength(before));
      await tap(find.byKey(const Key('scene-apply-step')));
      final frame = find.widgetWithText(ListTile, '#200400');
      await tap(frame);
      expect(shared, findsOneWidget);
      final disc = find.descendant(of: shared, matching: find.byType(ColorDisc));
      expect(tester.widget<ColorDisc>(disc).color, const Color(0xff200400));
      await tap(tone(c.text('whiteCoolTone')));
      await tap(find.byKey(const Key('scene-apply-step')));
      expect(find.widgetWithText(ListTile, '#FFFFFF'), findsOneWidget);
      expect(ble.writes, hasLength(before));
      await tap(find.byKey(const Key('scene-close')));

      await tap(find.text('Color').last);
      expect(shared, findsOneWidget);
      expect(tone(c.text('night')), findsNothing);
      final whiteChips = ['whiteWarmTone', 'whiteNeutralTone', 'whiteCoolTone']
          .map((key) => tester.getRect(tone(c.text(key)))).toList();
      for (final chip in whiteChips) {
        expect(chip.shortestSide, greaterThanOrEqualTo(48));
        expect(chip.left, greaterThanOrEqualTo(glowScreenPadding.left));
        expect(chip.right, lessThanOrEqualTo(width - glowScreenPadding.right));
      }
      if (width == 320) {
        expect(whiteChips.last.top, greaterThanOrEqualTo(whiteChips.first.bottom));
      }
      if (inside('favorite-#200400').evaluate().isEmpty) await tap(inside('color-favorites'));
      await tap(inside('favorite-#200400'));
      for (var i = 0; i < 3; i++) {
        now += 50;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ble.writes.last, wire.color(32, 4, 0));
    });
  }

  for (final width in [320.0, 412.0]) {
    testWidgets('quick actions two-step pickers and editing at $width dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, width == 320 ? 640 : 915));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      final models = Models(store, presetIds: {});
      await models.saveSequences(createSequence([]));
      await models.saveShortcuts([]);
      final c = await start(tester);
      c.toggleEffectFavorite(210);
      void expectSelected(Finder target) {
        expect(find.descendant(of: target, matching: find.byKey(GlowSelection.markerKey)), findsOneWidget);
        expect(tester.getSemantics(target).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      }
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final title = find.text('Acciones rápidas');
      await tester.scrollUntilVisible(title, 100);
      await tap(title);
      expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isFalse);
      final add = find.byTooltip('Agregar acción rápida');
      final confirm = find.widgetWithText(FilledButton, 'Agregar');
      final first = find.text('Paso 1 de 2 · Elegir tipo');
      final second = find.text('Paso 2 de 2 · Elegir opción');
      final color = find.byKey(const Key('quick-type-color'));
      await tap(add);
      expect(first, findsOneWidget);
      await tap(color);
      expect(second, findsOneWidget);
      await tap(find.byTooltip('Volver a los tipos'));
      expect(first, findsOneWidget);
      await tap(color);
      expect(find.byKey(const Key('color-disc')), findsOneWidget);
      await tap(find.widgetWithText(ChoiceChip, 'Cálido'));
      await tap(confirm);
      expect(c.shortcuts.single, defaultShortcuts.first);
      await tap(add);
      await tap(find.byKey(const Key('quick-type-effect')));
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
      expect(find.text(c.text('favorites')), findsOneWidget);
      expect(find.byKey(const Key('effect-row-210')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('effect-search')), '210');
      await tester.pumpAndSettle();
      await tap(find.byKey(const Key('effect-row-210')));
      expectSelected(find.byKey(const Key('effect-row-210')));
      await tap(confirm);
      expect(c.shortcuts.last, {'kind': 'effect', 'effect': 210});
      await tap(add);
      await tap(find.byKey(const Key('quick-type-scene')));
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
      await tap(find.text(c.text('rasta')));
      expectSelected(find.byKey(const Key('quick-scene-rasta')));
      await tap(confirm);
      expect(c.shortcuts.last, {'kind': 'scene', 'preset': 'rasta'});
      await tap(add);
      await tap(find.byKey(const Key('quick-type-sequence')));
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
      await tap(find.text(c.models.loadSequences().single['name'] as String));
      final card = find.byKey(const Key('quick-sequence-1'));
      expectSelected(card);
      expect(find.descendant(of: card, matching: find.text('3 pasos · 1,5 s')), findsOneWidget);
      await tap(confirm);
      expect(c.shortcuts.last, {'kind': 'sequence', 'id': '1'});

      final effect = find.text(c.shortcutLabel(c.shortcuts[1]));
      Future<void> editEffect() async {
        await tester.ensureVisible(effect);
        await tester.pumpAndSettle();
        await tester.longPress(effect);
        await tester.pumpAndSettle();
      }
      await editEffect();
      await tap(find.text(c.text('moveLeft')));
      expect(c.shortcuts.first['kind'], 'effect');
      await editEffect();
      await tap(find.widgetWithText(SimpleDialogOption, c.text('changeShortcut')));
      await tap(color);
      await tap(find.widgetWithText(ChoiceChip, 'Frío'));
      await tap(find.widgetWithText(FilledButton, 'Cambiar'));
      const cool = {'kind': 'color', 'name': 'coolWhite', 'rgb': [255, 255, 255]};
      expect(c.shortcuts.first, cool);
      expect(c.models.loadShortcuts().first, cool);
      final scene = find.text(c.text('rasta'));
      await tester.ensureVisible(scene);
      await tester.pumpAndSettle();
      await tester.longPress(scene);
      await tester.pumpAndSettle();
      await tap(find.text(c.text('removeShortcut')));
      expect(c.shortcuts.map((item) => item['kind']), ['color', 'color', 'sequence']);
    });
  }

  testWidgets('compact quick effect picker can select and confirm above keyboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 420);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await start(tester);
    final quick = find.text('Acciones rápidas');
    await tester.scrollUntilVisible(quick, 100);
    await tester.ensureVisible(quick);
    await tester.pumpAndSettle();
    await tester.tap(quick);
    await tester.pumpAndSettle();
    final add = find.byTooltip('Agregar acción rápida');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final effectType = find.byKey(const Key('quick-type-effect'));
    await tester.ensureVisible(effectType);
    await tester.pumpAndSettle();
    await tester.tap(effectType);
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('effect-search'));
    await tester.tap(search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(search.hitTestable(), findsOneWidget);
    await tester.enterText(search, '210');
    await tester.pumpAndSettle();
    for (final target in [find.byKey(const Key('effect-row-210')), find.widgetWithText(FilledButton, 'Agregar')]) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    expect(c.shortcuts.last, {'kind': 'effect', 'effect': 210});
    expect(tester.takeException(), isNull);
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

  testWidgets('F11 six quick actions explain why add is unavailable', (tester) async {
    final controller = await start(tester);
    await controller.updateShortcuts([
      for (var i = 1; i <= maxShortcuts; i++) {'kind': 'effect', 'effect': i},
    ]);
    await tester.pump();
    await tester.tap(find.text(controller.text('quickActions')));
    await tester.pumpAndSettle();
    expect(find.text(controller.text('quickActionsLimit', {'max': maxShortcuts})), findsOneWidget);
    expect(find.byTooltip(controller.text('addShortcut')), findsNothing);
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

  testWidgets('a drag on the disabled brightness slider does not change tab', (tester) async {
    await start(tester, readBluetooth: () async => AvailabilityState.poweredOff);
    final slider = find.byKey(const Key('brightness'));
    await tester.scrollUntilVisible(slider, 120);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final selected = find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true);
    expect(find.ancestor(of: find.text('Inicio'), matching: selected), findsOneWidget);
  });

  for (final (problem, message) in [
    ('permissionDenied', 'Permite el acceso a dispositivos cercanos (en Android 11 o anterior, a la ubicación) para conectar.'),
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

  testWidgets('Home explains Bluetooth off before an availability read fails', (tester) async {
    await Models(store, presetIds: {}).saveRemembered(FakeBle.strip);
    final initial = Completer<AvailabilityState>();
    accessProblem = 'bluetoothOff';
    final c = await start(tester, readBluetooth: () => initial.future);
    await tester.tap(find.text('Reconectar'));
    await tester.pumpAndSettle();
    expect(find.text(c.text('bluetoothOff')), findsOneWidget);
    initial.completeError(StateError('Availability unavailable'));
    await tester.pumpAndSettle();
    expect(find.text(c.text('bluetoothOff')), findsOneWidget);
    expect(ble.connections, isEmpty);
  });

  for (final definitive in [false, true]) {
    testWidgets('only definitive power events supersede the initial Bluetooth read ($definitive)', (tester) async {
      final initial = Completer<AvailabilityState>();
      final changes = StreamController<AvailabilityState>();
      addTearDown(changes.close);
      final c = await start(tester, readBluetooth: () => initial.future, bluetoothChanges: changes.stream);
      changes.add(definitive ? AvailabilityState.poweredOn : AvailabilityState.values.firstWhere(
        (state) => state != AvailabilityState.poweredOn && state != AvailabilityState.poweredOff));
      await tester.pump();
      initial.complete(AvailabilityState.poweredOff);
      await tester.pumpAndSettle();
      expect(find.text(c.text('bluetoothOffTitle')), definitive ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('starting the same duration retries a failed timer save', (tester) async {
    expect(await saveTimerDuration(store, 60), isTrue);
    final c = await start(tester);
    await connect(tester);
    store.refusedKey = 'timerDuration';
    c.startTimer(90, fade: false);
    await tester.pump();
    expect(c.lastTimerDuration, 90);
    expect(loadTimerDuration(store), 60);
    c.cancelTimer();
    store.refusedKey = null;
    c.startTimer(90, fade: false);
    await tester.pump();
    expect(loadTimerDuration(store), 90);
  });

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

  testWidgets('timer ring paints a gradient half arc over the unfilled track', (tester) async {
    final c = await start(tester);
    await connect(tester);
    c.startTimer(60, fade: false);
    now = 30000;
    const capture = Key('timer-capture');
    await tester.pumpWidget(MaterialApp(theme: glowTheme(), home: Scaffold(
      body: RepaintBoundary(key: capture, child: TimerSheet(controller: c)),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(c.timerFraction, .5);
    final ring = find.ancestor(of: find.text('0:30'), matching: find.byType(CustomPaint)).first;
    final rect = tester.getRect(ring).shift(-tester.getTopLeft(find.byKey(capture)));
    final radius = rect.width / 2 - 6;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
        Color pixel(double x, double y) {
          final point = rect.center + Offset(x * radius, y * radius);
          final i = 4 * (point.dy.round() * image.width + point.dx.round());
          return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
        }
        void expectGradient(Color actual, double fraction) {
          final expected = Color.lerp(glowViolet, glowPink, fraction)!;
          expect(actual.r, closeTo(expected.r, .025));
          expect(actual.g, closeTo(expected.g, .025));
          expect(actual.b, closeTo(expected.b, .025));
        }
        expectGradient(pixel(.707, -.707), .25);
        expectGradient(pixel(.707, .707), .75);
        // Sample the outer half of the stroke, clear of the ring's fill edge.
        final outside = 1 + 2 / radius;
        final track = pixel(-outside, 0);
        final background = pixel(-1.15, 0);
        final expectedTrack = Color.alphaBlend(glowMuted.withValues(alpha: .35), background);
        expect(track.r, closeTo(expectedTrack.r, .01));
        expect(track.g, closeTo(expectedTrack.g, .01));
        expect(track.b, closeTo(expectedTrack.b, .01));
        expect(pixel(-.707 * outside, .707 * outside), track);
      } finally {
        image.dispose();
      }
    });
    c.cancelTimer();
  });

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

  testWidgets('empty My scenes picker opens the editor and shows the saved card', (tester) async {
    final c = await start(tester);
    final title = find.text(c.text('quickActions'));
    await tester.scrollUntilVisible(title, 100);
    await timerTap(tester, title);
    await timerTap(tester, find.byTooltip(c.text('addShortcut')));
    await timerTap(tester, find.byKey(const Key('quick-type-sequence')));
    expect(find.widgetWithText(Notice, c.text('quickNoSequences')), findsOneWidget);
    await timerTap(tester, find.byKey(const Key('quick-new-scene')));
    expect(find.text(c.text('sceneTotal', {'duration': '1,5 s'})), findsOneWidget);
    expect(find.text('Mantén presionado un paso y arrástralo para cambiar su orden.'), findsOneWidget);
    await timerTap(tester, find.byKey(const Key('scene-save')));
    expect(find.text('3 pasos · 1,5 s'), findsOneWidget);
    expect(find.byKey(const Key('quick-new-scene')), findsNothing);
  });

  testWidgets('timer sheet validates custom seconds and remembers them on reload', (tester) async {
    void expectSelected(String label) {
      final chip = find.byKey(Key('timer-$label'));
      expect(find.descendant(of: chip, matching: find.byKey(GlowSelection.markerKey)), findsOneWidget);
      expect(tester.getSemantics(chip).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
    }
    final c = await start(tester);
    await timerTap(tester, find.byTooltip(c.text('offTimer')));
    expect(find.text(c.text('connectFirst')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, c.text('startTimer'))).onPressed, isNull);
    expectSelected('minutes15');
    await timerTap(tester, find.byTooltip(c.text('close')));
    await connect(tester);
    await timerTap(tester, find.byTooltip(c.text('offTimer')));
    await timerTap(tester, find.text(c.text('custom')));
    expectSelected('custom');
    final minutes = find.widgetWithText(TextField, c.text('minutes'));
    final seconds = find.widgetWithText(TextField, c.text('seconds'));
    await tester.enterText(minutes, '0');
    await tester.enterText(seconds, '0');
    await timerTap(tester, find.text(c.text('startTimer')));
    for (final (key, kind) in [('invalidTimer', NoticeKind.error), ('timerNote', NoticeKind.info)]) {
      final notice = find.ancestor(of: find.text(c.text(key)), matching: find.byType(Notice));
      expect(tester.widget<Notice>(notice).kind, kind);
    }
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
      expect(find.byKey(const Key('glow-sheet')), findsOneWidget);
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
    await tester.tap(find.text('Acciones rápidas'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final beforeScroll = scroll.position.pixels;
    await tester.dragFrom(tester.getCenter(label.hitTestable()), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, lessThan(beforeScroll));
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
    final offset = tester.getSize(disc).width / 3;
    await tester.tapAt(tester.getCenter(disc) + Offset(offset, 0));
    await tester.pumpAndSettle();
    final tappedHue = selection().hue;
    expect(tappedHue, closeTo(90, 1));
    await tester.dragFrom(tester.getCenter(disc) + Offset(0, -offset), const Offset(-170, 0));
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

  testWidgets('step duration retains the edit and focus across a live resize', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await start(tester);
    await tapTab(tester, 'Escenas');
    await tapKey(tester, 'scene-new');
    await tester.ensureVisible(find.byKey(const Key('scene-add-effect')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'scene-add-effect');
    final field = find.byKey(const Key('scene-step-duration'));
    final editable = find.descendant(of: field, matching: find.byType(EditableText));
    final label = c.text('sceneDurationSeconds');
    expect(tester.widget<TextField>(find.descendant(of: field,
      matching: find.byType(TextField))).decoration!.labelText, label);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '42.5');
    await tester.pumpAndSettle();
    for (final width in [280.0, 600.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.descendant(of: field,
        matching: find.byType(TextField))).decoration!.labelText, width == 280 ? null : label);
      final input = tester.widget<EditableText>(editable);
      expect(input.controller.text, '42.5');
      expect(input.focusNode.hasFocus, isTrue);
    }
  });

  testWidgets('Inicio strip swipe previews the next saved strip without changing tabs', (tester) async {
    const next = RememberedStrip('second', 'Second strip');
    await Models(store, presetIds: {}).saveRememberedStrips([
      const RememberedStrip('fake', 'LEDDMX Test'), next,
    ]);
    final c = await start(tester);
    final change = find.widgetWithText(TextButton, c.text('changeStrip'));
    await tester.drag(change, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(find.text(next.label), findsOneWidget);
    expect(ble.connections, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, c.text('connect')));
    await tester.pumpAndSettle();
    expect(ble.connections, [next.id]);
    expect(find.text(c.text('chooseStrip')), findsNothing);
  });

  testWidgets('Inicio strip card opens the chooser without connecting', (tester) async {
    await Models(store, presetIds: {}).saveRemembered(FakeBle.strip);
    final c = await start(tester);
    await tester.tap(find.text(FakeBle.strip.name));
    await tester.pumpAndSettle();
    expect(find.text(c.text('chooseStrip')), findsOneWidget);
    expect(ble.connections, isEmpty);
  });

  testWidgets('tapping the body of an unsaved scan result connects to its ID', (tester) async {
    const nearby = Strip('nearby', 'LEDDMX Nearby');
    ble.results = [FakeBle.strip, nearby];
    final c = await start(tester);
    await tester.tap(find.widgetWithText(FilledButton, c.text('connect')));
    await tester.pumpAndSettle();
    expect(c.rememberedStrips, isEmpty);
    expect(ble.connections, isEmpty);
    final rowBody = find.text(nearby.name);
    expect(rowBody.hitTestable(), findsOneWidget);
    await tester.tap(rowBody);
    await tester.pumpAndSettle();
    expect(ble.connections, [nearby.id]);
    expect(c.link.strip?.id, nearby.id);
  });

  testWidgets('saved strip card connects and uses the existing pending and error states', (tester) async {
    await Models(store, presetIds: {}).saveRemembered(FakeBle.strip);
    final c = await start(tester);
    await tester.tap(find.widgetWithText(TextButton, c.text('changeStrip')));
    await tester.pumpAndSettle();
    final strip = find.text(FakeBle.strip.name);
    final opening = Completer<void>();
    ble.opening = opening.future;
    ble.unreachable.add(FakeBle.strip.id);
    await tester.tap(strip);
    await tester.pump();
    expect(ble.connections, [FakeBle.strip.id]);
    expect(find.widgetWithText(FilledButton, c.text('cancel')), findsOneWidget);
    opening.complete();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    final retry = find.widgetWithText(FilledButton, c.text('retryStrip'));
    expect(retry, findsOneWidget);
    ble.unreachable.clear();
    ble.connections.clear();
    await tester.tap(strip);
    await tester.pumpAndSettle();
    expect(c.link.strip?.id, FakeBle.strip.id);
    await tester.tap(strip);
    await tester.pumpAndSettle();
    expect(ble.connections, [FakeBle.strip.id]);
    expect(c.link.ready, isTrue);
    await tester.tap(find.widgetWithText(FilledButton, c.text('disconnect')));
    await tester.pumpAndSettle();
    expect(c.link.ready, isFalse);
  });

  for (final (width, language) in [(320.0, 'es'), (412.0, 'en')]) {
    testWidgets('transient notice is floating Glow Glass at $width dp ($language)', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await start(tester);
      c.setLanguage(language);
      await tester.pumpAndSettle();
      final quickActions = find.text(c.text('quickActions'));
      await tester.ensureVisible(quickActions);
      await tester.pumpAndSettle();
      await tester.tap(quickActions);
      await tester.pumpAndSettle();
      final shortcut = find.text(c.shortcutLabel(c.shortcuts.first));
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      final finder = find.byType(SnackBar);
      final bar = tester.widget<SnackBar>(finder);
      expect(bar.behavior, SnackBarBehavior.floating);
      expect(bar.backgroundColor, Colors.transparent);
      final blur = find.descendant(of: finder, matching: find.byType(BackdropFilter));
      expect(blur, findsOneWidget);
      final surface = find.descendant(of: blur, matching: find.byType(DecoratedBox)).first;
      final decoration = tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
      expect(decoration.color!.a, lessThan(1));
      expect(decoration.border, Border.all(color: glowLine));
      final worstBackground = Color.alphaBlend(decoration.color!, Colors.white);
      final label = find.text(c.text('connectFirst'));
      expect(tester.widget<Text>(label).style?.color, glowInk);
      expect((glowInk.computeLuminance() + .05) / (worstBackground.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5));
      expect(find.descendant(of: finder, matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
      final nav = tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar!;
      expect(tester.getBottomLeft(surface).dy, lessThan(tester.getTopLeft(find.byWidget(nav)).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('right swipe from Inicio wraps to Ajustes', (tester) async {
    await start(tester);
    await tester.dragFrom(const Offset(250, 35), const Offset(180, 0));
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
      final quick = find.text('Acciones rápidas');
      await tester.scrollUntilVisible(quick, 100);
      await tester.ensureVisible(quick);
      await tester.pumpAndSettle();
      await tester.tap(quick.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Blanco cálido'), findsOneWidget);
      final brightness = find.byKey(const Key('brightness'));
      await tester.ensureVisible(brightness);
      await tester.pumpAndSettle();
      expect(brightness.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
