import 'package:deleluz/app_controller.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/scenes/scenes_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../home_test.dart' show FakeBle, Store;

void main() {
  late FakeBle ble;
  late AppController c;
  late double now;

  Future<void> start(WidgetTester tester, {bool connected = false,
      Size size = const Size(412, 915), double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ble = FakeBle();
    now = 0;
    c = AppController(ble, Store(), checkAccess: (_) async => null, now: () => now);
    addTearDown(c.dispose);
    if (connected) await c.connect(FakeBle.strip);
    const screenKey = Key('screen');
    await tester.pumpWidget(MaterialApp(theme: glowTheme(), builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!), home: Scaffold(body: ScenesScreen(key: screenKey, controller: c))));
    await tester.pump();
  }

  Finder key(String value) => find.byKey(Key(value));

  Future<void> tap(WidgetTester tester, String value) async {
    final target = key(value);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tick(WidgetTester tester, [int ms = 50]) async {
    now += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  testWidgets('included gallery previews offline and applies a foreground sequence', (tester) async {
    await start(tester, connected: true);
    expect(find.byType(ConnectionChip), findsOneWidget);
    await tester.longPress(key('included-police'));
    await tester.pumpAndSettle();
    expect(find.text(c.text('screenPreview')), findsOneWidget);
    expect(ble.writes, isEmpty);
    await tap(tester, 'scene-close');
    await tap(tester, 'included-police');
    await tick(tester);
    await tick(tester);
    expect(ble.writes.map((w) => w[2]), [4, 1, 7]);
    await tick(tester, 180);
    expect(ble.writes.where((w) => w[2] == 7).map((w) => w[3]), [255, 0]);
    c.setForeground(false);
    await tick(tester, 1000);
    expect(ble.writes, hasLength(4));
  });

  testWidgets('draft validates names and color boundaries, saves and confirms deletion', (tester) async {
    await start(tester);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    await tester.enterText(key('scene-name'), '   ');
    await tap(tester, 'scene-save');
    expect(c.models.loadSequences(), isEmpty);
    await tester.enterText(key('scene-name'), 'a' * 25);
    await tap(tester, 'scene-save');
    expect(c.models.loadSequences(), isEmpty);
    await tester.enterText(key('scene-name'), ' ${'a' * 24} ');
    for (var i = 3; i < 8; i++) {
      await tap(tester, 'scene-add-color');
    }
    expect(tester.widget<OutlinedButton>(key('scene-add-color')).onPressed, isNull);
    for (var i = 8; i > 1; i--) {
      await tap(tester, 'scene-remove-color');
    }
    expect(tester.widget<OutlinedButton>(key('scene-remove-color')).onPressed, isNull);
    await tap(tester, 'scene-save');
    final saved = c.models.loadSequences().single;
    expect(saved['name'], 'a' * 24);
    expect(saved['colors'] as List, hasLength(1));
    await tap(tester, 'scene-new');
    await tester.enterText(key('scene-name'), 'A' * 24);
    await tap(tester, 'scene-save');
    expect(c.models.loadSequences(), hasLength(1));
    await tap(tester, 'scene-close');
    await tap(tester, 'scene-edit-${saved['id']}');
    await tap(tester, 'scene-delete');
    await tap(tester, 'scene-cancel-delete');
    expect(c.models.loadSequences(), hasLength(1));
    await tap(tester, 'scene-delete');
    await tap(tester, 'scene-confirm-delete');
    expect(c.models.loadSequences(), isEmpty);
  });

  testWidgets('music sends four wire modes and higher sensitivity without phone audio', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'scenes-music');
    final slider = key('scene-sensitivity');
    for (var mode = 1; mode <= 4; mode++) {
      await tap(tester, 'scene-voice-$mode');
      for (var i = 0; i < 5; i++) {
        await tick(tester, 100);
      }
    }
    expect(ble.writes.where((w) => w[2] == 11).map((w) => w[3]), [1, 2, 3, 4]);
    await tester.ensureVisible(slider);
    for (final value in [0.0, 100.0]) {
      tester.widget<Slider>(slider).onChanged!(value);
      await tick(tester);
      expect(ble.writes.last.sublist(2, 4), [12, value.toInt()]);
    }
    expect(find.textContaining(c.text('micSensitivity'), findRichText: true), findsAtLeastNWidgets(2));
  });

  testWidgets('draft player stops when the app loses foreground', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    await tap(tester, 'scene-start');
    await tick(tester);
    await tick(tester);
    expect(ble.writes.map((w) => w[2]), [4, 1, 7]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    c.setForeground(false);
    await tick(tester, 2000);
    expect(ble.writes, hasLength(3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    c.setForeground(true);
    await tick(tester, 2000);
    expect(ble.writes, hasLength(3));
  });

  testWidgets('long-press drag reorders; preview sends draft only and stops', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    final square = tester.getCenter(key('scene-frame-0'));
    final destination = tester.getCenter(key('scene-frame-2'));
    final gesture = await tester.startGesture(square);
    await tester.pump(const Duration(milliseconds: 550));
    await gesture.moveTo(destination);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.models.loadSequences(), isEmpty);
    for (final (id, value) in [('scene-speed', 100.0), ('scene-intensity', 1.0)]) {
      final slider = key(id);
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(value);
      await tester.pumpAndSettle();
    }
    await tap(tester, 'scene-start');
    await tick(tester);
    await tick(tester);
    expect(ble.writes[1].sublist(2, 5), [1, 0, 1]);
    expect(ble.writes[2].sublist(3, 6), [255, 200, 0]);
    await tick(tester, 150);
    expect(ble.writes.last.sublist(3, 6), [255, 0, 0]);
    await tap(tester, 'scene-stop');
    await tick(tester, 1000);
    expect(ble.writes.last.sublist(2, 4), [4, 0]);
    expect(tester.widget<TextButton>(key('scene-stop')).onPressed, isNull);
    await tap(tester, 'scene-save');
    final item = c.models.loadSequences().single;
    expect(item['interval'], 150);
    expect(item['bri'], 1);
    expect(item['colors'], [[255, 200, 0], [255, 0, 0], [0, 255, 0]]);
    await tap(tester, 'scene-edit-${item['id']}');
    await tap(tester, 'scene-rename');
    await tester.enterText(key('scene-name'), ' Revised ');
    await tester.ensureVisible(key('scene-speed'));
    tester.widget<Slider>(key('scene-speed')).onChanged!(0);
    await tester.pumpAndSettle();
    await tap(tester, 'scene-save');
    expect(c.models.loadSequences().single['name'], 'Revised');
    expect(c.models.loadSequences().single['interval'], 2000);
    await tap(tester, 'scene-play-${item['id']}');
    for (var i = 0; i < 3; i++) {
      await tick(tester);
    }
    expect(ble.writes.last.sublist(3, 6), [255, 200, 0]);
    await tick(tester, 1900);
    expect(ble.writes.last.sublist(3, 6), [255, 200, 0]);
    await tick(tester, 100);
    expect(ble.writes.last.sublist(3, 6), [255, 0, 0]);
    c.setForeground(false);
  });

  testWidgets('disconnected strip actions do not write and drafts can be discarded', (tester) async {
    await start(tester);
    await tap(tester, 'included-police');
    expect(find.text(c.text('connectFirst')), findsOneWidget);
    await tap(tester, 'scenes-music');
    await tap(tester, 'scene-voice-1');
    final slider = tester.widget<Slider>(key('scene-sensitivity'));
    expect(slider.onChanged, isNull);
    await tester.pumpAndSettle();
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    expect(tester.widget<TextButton>(key('scene-start')).onPressed, isNull);
    await tester.enterText(key('scene-name'), 'Unsaved');
    await tap(tester, 'scene-close');
    expect(c.models.loadSequences(), isEmpty);
    expect(ble.writes, isEmpty);
    expect(c.models.loadState()['micSens'], 50);
  });

  testWidgets('saved scenes are capped at twelve', (tester) async {
    await start(tester);
    await c.models.saveSequences([
      for (var i = 1; i <= 12; i++) {
        'id': '$i', 'name': 'Scene $i', 'colors': [[255, 0, 0]], 'bri': 80, 'interval': 500,
      },
    ]);
    await tap(tester, 'scenes-mine');
    expect(tester.widget<FilledButton>(key('scene-new')).onPressed, isNull);
    expect(ble.writes, isEmpty);
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('scene gallery, editor, and music fit $size at 1.6×', (tester) async {
      await start(tester, size: size, scale: 1.6);
      expect(tester.takeException(), isNull);
      await tap(tester, 'scenes-mine');
      await tap(tester, 'scene-new');
      await tester.ensureVisible(key('scene-intensity'));
      await tester.pumpAndSettle();
      expect(key('scene-save').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, 'scene-close');
      c.setLanguage('en');
      await tester.pumpAndSettle();
      await tap(tester, 'scenes-music');
      expect(tester.takeException(), isNull);
    });
  }
}
