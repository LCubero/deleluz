import 'package:deleluz/app_controller.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/scenes/scenes_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../home_test.dart' show FakeBle, Store;

void main() {
  late FakeBle ble;
  late AppController c;
  late double now;
  late Store store;

  const legacyScene = '[{"id":"1","name":"Secuencia 1","colors":[[0,255,0],[255,200,0],[255,0,0]],"interval":500,"bri":80}]';

  Future<void> start(WidgetTester tester, {bool connected = false,
      Size size = const Size(412, 915), double scale = 1, String? savedScenes}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ble = FakeBle();
    now = 0;
    store = Store();
    if (savedScenes != null) store.values[Models.sequencesKey] = savedScenes;
    c = AppController(ble, store, checkAccess: (_) async => null, now: () => now);
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

  for (final mixed in [false, true]) {
    testWidgets('${mixed ? 'mixed' : 'legacy'} stored scene sends timed exact frames', (tester) async {
      await start(tester, connected: true);
      store.values[Models.sequencesKey] = mixed
          ? '[{"id":"1","name":"Mixed","bri":80,"steps":[{"rgb":[0,255,0],"durationMs":150},{"effect":210,"durationMs":1000},{"rgb":[255,0,0],"durationMs":450}]}]'
          : legacyScene;
      c.applyShortcut({'kind': 'sequence', 'id': '1'});
      await tick(tester);
      await tick(tester);
      List<List<int>> frames() => ble.writes.where((w) => w[2] == 7 || w[2] == 3).toList();
      const green = [123, 255, 7, 0, 255, 0, 0, 255, 191];
      const red = [123, 255, 7, 255, 0, 0, 0, 255, 191];
      final second = mixed ? [123, 255, 3, 210, 255, 255, 255, 255, 191]
          : [123, 255, 7, 255, 200, 0, 0, 255, 191];
      expect(frames(), [green]);
      await tick(tester, mixed ? 149 : 499);
      expect(frames(), [green]);
      await tick(tester, 1);
      expect(frames(), [green, second]);
      await tick(tester, mixed ? 999 : 499);
      expect(frames(), [green, second]);
      await tick(tester, 1);
      expect(frames(), [green, second, red]);
      await tick(tester, mixed ? 449 : 499);
      expect(frames(), [green, second, red]);
      await tick(tester, 1);
      expect(frames(), [green, second, red, green]);
      c.setForeground(false);
      await tick(tester, 3000);
      expect(frames(), [green, second, red, green]);
    });
  }

  testWidgets('legacy scene duration edited in the picker survives save and playback', (tester) async {
    await start(tester, connected: true, savedScenes: legacyScene);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-edit-1');
    await tap(tester, 'scene-frame-0');
    await tester.ensureVisible(key('scene-step-duration'));
    expect(find.text('500'), findsOneWidget);
    await tester.enterText(key('scene-step-duration'), '2000');
    await tap(tester, 'scene-apply-step');
    await tap(tester, 'scene-save');
    expect(sceneSteps(c.models.loadSequences().single).map((step) => step['durationMs']),
      [2000, 500, 500]);

    c.applyShortcut({'kind': 'sequence', 'id': '1'});
    await tick(tester);
    await tick(tester);
    List<List<int>> frames() => ble.writes.where((w) => w[2] == 7).toList();
    const green = [123, 255, 7, 0, 255, 0, 0, 255, 191];
    const yellow = [123, 255, 7, 255, 200, 0, 0, 255, 191];
    expect(frames(), [green]);
    await tick(tester, 1999);
    expect(frames(), [green]);
    await tick(tester, 1);
    expect(frames(), [green, yellow]);
    c.setForeground(false);
  });

  testWidgets('unsaved mixed editor draft sends the exact effect on time and stops', (tester) async {
    await start(tester, connected: true);
    c.toggleEffectFavorite(210);
    await tap(tester, 'scene-new');
    await tap(tester, 'scene-remove-step-2');
    await tap(tester, 'scene-remove-step-1');
    await tap(tester, 'scene-add-effect');
    await tap(tester, 'effect-row-210');
    await tester.ensureVisible(key('scene-step-duration'));
    await tester.enterText(key('scene-step-duration'), '1');
    await tap(tester, 'scene-apply-step');

    expect(c.models.loadSequences(), isEmpty);
    await tap(tester, 'scene-start');
    await tick(tester);
    await tick(tester);
    List<List<int>> frames() => ble.writes.where((w) => w[2] == 7 || w[2] == 3).toList();
    const green = [123, 255, 7, 0, 255, 0, 0, 255, 191];
    const effect = [123, 255, 3, 210, 255, 255, 255, 255, 191];
    expect(frames(), [green]);
    await tick(tester, 499);
    expect(frames(), [green]);
    await tick(tester, 1);
    expect(frames(), [green, effect]);

    await tap(tester, 'scene-stop');
    await tick(tester, 2000);
    expect(frames(), [green, effect]);
    expect(c.models.loadSequences(), isEmpty);
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('color and effect sheets fit and save at $width dp with large text', (tester) async {
      await start(tester, size: Size(width, 640), scale: 1.5);
      c.toggleEffectFavorite(210);
      await tap(tester, 'scene-new');
      await tap(tester, 'scene-add-color');
      await tester.tap(key('color-disc'));
      await tester.pumpAndSettle();
      expect(find.text(c.text('whiteTones')), findsOneWidget);
      await tap(tester, 'scene-apply-step');
      await tap(tester, 'scene-add-effect');
      expect(key('effect-row-210'), findsOneWidget);
      await tester.enterText(key('effect-search'), '210');
      await tester.pumpAndSettle();
      await tap(tester, 'effect-row-210');
      await tester.ensureVisible(key('scene-step-duration'));
      await tester.enterText(key('scene-step-duration'), '601');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(key('scene-apply-step')).onPressed, isNull);
      await tester.enterText(key('scene-step-duration'), '5');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(key('scene-apply-step')).onPressed, isNotNull);
      await tap(tester, 'scene-apply-step');
      expect(find.text(c.text('sceneTotal', {'duration': '7 s'})), findsOneWidget);
      await tap(tester, 'scene-save');
      expect(sceneSteps(c.models.loadSequences().single).skip(3), [
        {'rgb': [255, 255, 255], 'durationMs': 500},
        {'effect': 210, 'durationMs': 5000},
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('included gallery previews offline and applies a foreground sequence', (tester) async {
    await start(tester, connected: true);
    expect(find.byType(ConnectionChip), findsOneWidget);
    await tap(tester, 'scenes-included');
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
      await tap(tester, 'scene-apply-step');
    }
    expect(tester.widget<OutlinedButton>(key('scene-add-color')).onPressed, isNull);
    for (var i = 8; i > 1; i--) {
      await tap(tester, 'scene-remove-step-${i - 1}');
    }
    expect(tester.widget<IconButton>(key('scene-remove-step-0')).onPressed, isNull);
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

  testWidgets('draft delete is destructive and separated from playback status', (tester) async {
    await start(tester);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    final action = key('scene-delete');
    expect(action, findsOneWidget);
    expect(tester.getCenter(action).dx,
      closeTo(tester.getCenter(find.byType(Dialog)).dx, .01));
    final button = tester.widget<OutlinedButton>(action);
    final context = tester.element(action);
    expect(button.style!.foregroundColor!.resolve({}), Theme.of(context).colorScheme.error);
    expect(tester.getTopLeft(action).dy - tester.getBottomLeft(find.text(c.text('foregroundPlaybackHint'))).dy,
      greaterThanOrEqualTo(18));
    await tap(tester, 'scene-delete');
    await tap(tester, 'scene-cancel-delete');
    expect(action, findsOneWidget);
    await tap(tester, 'scene-delete');
    await tap(tester, 'scene-confirm-delete');
    expect(action, findsNothing);
    expect(c.models.loadSequences(), isEmpty);
  });

  testWidgets('scene brightness sends the latest draft value before the next color', (tester) async {
    await start(tester, connected: true);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    await tap(tester, 'scene-start');
    await tick(tester);
    await tick(tester);
    expect(ble.writes.map((w) => w[2]), [4, 1, 7]);
    final slider = key('scene-intensity');
    final change = tester.widget<Slider>(slider).onChanged!;
    change(28);
    change(71);
    await tick(tester);
    expect(ble.writes.skip(3).map((w) => w.sublist(2, 5)), [[1, 22, 71]]);
    expect(find.text('Brillo'), findsOneWidget);
    expect(tester.widget<Slider>(slider).value, 71);
    await tick(tester, 2000);
    expect(ble.writes.last[2], 7);
    await tap(tester, 'scene-save');
    await tick(tester);
    expect(c.models.loadSequences().single['bri'], 71);
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
    expect(find.text(c.text('micSensitivity')), findsOneWidget);
    expect(find.textContaining(c.text('lastSent', {'command': ''})), findsNothing);
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
    Future<void> changeDuration(int index, String value) async {
      await tap(tester, 'scene-frame-$index');
      await tester.ensureVisible(key('scene-step-duration'));
      await tester.enterText(key('scene-step-duration'), value);
      await tap(tester, 'scene-apply-step');
    }
    for (var i = 0; i < 3; i++) {
      await changeDuration(i, '150');
    }
    tester.widget<Slider>(key('scene-intensity')).onChanged!(1);
    await tester.pumpAndSettle();
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
    expect(sceneSteps(item).map((step) => step['durationMs']), [150, 150, 150]);
    expect(item['bri'], 1);
    expect(item['colors'], [[255, 200, 0], [255, 0, 0], [0, 255, 0]]);
    await tap(tester, 'scene-edit-${item['id']}');
    await tap(tester, 'scene-rename');
    await tester.enterText(key('scene-name'), ' Revised ');
    await changeDuration(0, '2000');
    await tap(tester, 'scene-save');
    expect(c.models.loadSequences().single['name'], 'Revised');
    expect(sceneSteps(c.models.loadSequences().single).first['durationMs'], 2000);
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
    await tap(tester, 'scenes-included');
    await tap(tester, 'included-police');
    expect(find.text(c.text('connectFirst')), findsOneWidget);
    await tap(tester, 'scenes-music');
    await tap(tester, 'scene-voice-1');
    final slider = tester.widget<Slider>(key('scene-sensitivity'));
    slider.onChanged!(72);
    await tester.pumpAndSettle();
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    expect(tester.widget<TextButton>(key('scene-start')).onPressed, isNull);
    await tester.enterText(key('scene-name'), 'Unsaved');
    await tap(tester, 'scene-close');
    expect(c.models.loadSequences(), isEmpty);
    expect(ble.writes, isEmpty);
    expect(c.models.loadState()['micSens'], 72);
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
