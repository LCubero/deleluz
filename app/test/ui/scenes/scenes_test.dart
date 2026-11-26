import 'package:deleluz/app_controller.dart';
import 'package:deleluz/model/models.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/home_presets.dart';
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
    // Tabs sit above the panels; cards below them.
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, value.startsWith('scenes-') ? -100 : 100);
    }
    if (target.hitTestable().evaluate().isEmpty) {
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pumpAndSettle();
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tick(WidgetTester tester, [int ms = 50]) async {
    now += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  testWidgets('audit: scene primary actions use the shared gradient button', (tester) async {
    await start(tester);
    await tap(tester, 'scene-new');
    expect(key('scene-save').hitTestable(), findsOneWidget);
    expect(tester.widget(key('scene-save')), isA<GlowPrimaryButton>());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget(key('scene-new')), isA<GlowPrimaryButton>());
    await tap(tester, 'scenes-included');
    await tester.longPress(key('included-police'));
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(GlowPrimaryButton, c.text('apply'));
    expect(apply, findsOneWidget);
    expect(tester.widget<GlowPrimaryButton>(apply).onPressed, isNull);
  });

  testWidgets('audit: failed command notice does not move scene tabs', (tester) async {
    await start(tester, connected: true, size: const Size(320, 915), scale: 1.5);
    final tabs = key('scenes-mine');
    final before = tester.getRect(tabs);
    ble.failWrite = (_) => true;
    final failed = c.setEffect(1);
    for (var i = 0; i < 5; i++) { await tick(tester, 100); }
    expect(await failed, isFalse);
    await tester.pumpAndSettle();
    expect(find.text(c.text('commandFailed')), findsOneWidget);
    expect(tester.getRect(tabs), before);
    ble.failWrite = null;
    final sent = c.setEffect(1);
    for (var i = 0; i < 5; i++) { await tick(tester, 100); }
    expect(await sent, isTrue);
    await tester.pumpAndSettle();
    expect(tester.getRect(tabs), before);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(c.text('commandFailed')), findsNothing);
    expect(tester.getRect(tabs), before);
  });

  testWidgets('audit: preview status does not move dialog actions', (tester) async {
    await start(tester, connected: true, size: const Size(320, 1600), scale: 1.5);
    await tap(tester, 'scenes-included');
    final card = key('included-police');
    await Scrollable.ensureVisible(tester.element(card), alignment: .5);
    await tester.pumpAndSettle();
    expect(card.hitTestable(), findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(c.text('noCommand')), findsOneWidget);
    final before = tester.getRect(key('scene-close'));
    final sent = c.setEffect(1);
    for (var i = 0; i < 5; i++) { await tick(tester, 100); }
    expect(await sent, isTrue);
    expect(find.textContaining(c.text('lastSent', {'command': ''})), findsOneWidget);
    expect(tester.getRect(key('scene-close')), before);
  });

  testWidgets('audit: dialog preview uses an animated shared strip', (tester) async {
    await start(tester);
    await tap(tester, 'scenes-included');
    await tester.longPress(key('included-police'));
    await tester.pumpAndSettle();
    final strip = find.descendant(of: find.byType(AlertDialog), matching: find.byType(GlowStrip));
    expect(strip, findsOneWidget);
    final before = tester.widget<GlowStrip>(strip).colors;
    await tick(tester, 350);
    expect(tester.widget<GlowStrip>(strip).colors, isNot(before));
  });

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

  testWidgets('F11 scene name counter uses trimmed UTF-16 units', (tester) async {
    await start(tester);
    await tap(tester, 'scenes-mine');
    await tap(tester, 'scene-new');
    await tester.enterText(key('scene-name'), '  A😀  ');
    await tester.pump();
    expect(find.text(c.text('sceneNameCount', {'count': 3, 'max': 24})), findsOneWidget);
  });

  testWidgets('F11 full scenes and steps explain why add is disabled', (tester) async {
    await start(tester);
    expect(await c.models.saveSequences([
      for (var i = 1; i <= maxSequences; i++)
        {'id': '$i', 'name': 'Scene $i', 'bri': 80, 'steps': [
          for (var step = 1; step <= maxColors; step++)
            {'rgb': [step, 0, 0], 'durationMs': 500},
        ]},
    ]), isTrue);
    await tap(tester, 'scenes-mine');
    expect(find.text(c.text('scenesLimit', {'max': maxSequences})), findsOneWidget);
    expect(tester.widget<GlowPrimaryButton>(key('scene-new')).onPressed, isNull);
    await tap(tester, 'scene-edit-1');
    final stepLimit = find.text(c.text('sceneStepsLimit', {'max': maxColors}));
    expect(stepLimit, findsOneWidget);
    await tester.ensureVisible(key('scene-add-color'));
    expect(tester.widget<OutlinedButton>(key('scene-add-color')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(key('scene-add-effect')).onPressed, isNull);
  });

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
      expect(find.text(c.text('whiteTones')), findsNothing);
      for (final tone in ['whiteWarmTone', 'whiteNeutralTone', 'whiteCoolTone']) {
        expect(find.widgetWithText(ChoiceChip, c.text(tone)), findsOneWidget);
      }
      await tap(tester, 'scene-apply-step');
      await tap(tester, 'scene-add-effect');
      expect(key('glow-sheet'), findsOneWidget);
      expect(key('effect-row-210'), findsOneWidget);
      await tester.enterText(key('effect-search'), '210');
      await tester.pumpAndSettle();
      await tap(tester, 'effect-row-210');
      expect(find.descendant(of: key('effect-row-210'),
        matching: find.byKey(const ValueKey('glow-selected'))), findsOneWidget);
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
      for (var candidate = 1; candidate <= 4; candidate++) {
        final card = key('scene-voice-$candidate');
        expect(find.descendant(of: card, matching: find.byKey(GlowSelection.markerKey)),
          candidate == mode ? findsOneWidget : findsNothing);
        final material = tester.widget<Material>(find.descendant(of: card, matching: find.byType(Material)).first);
        expect(material.color, candidate == mode ? GlowSelection.tint : glowGlass);
        if (candidate == mode) {
          expect((material.shape as RoundedRectangleBorder).side, GlowSelection.border);
        }
      }
    }
    expect(ble.writes.where((w) => w[2] == 11).map((w) => w[3]), [1, 2, 3, 4]);
    ble.failWrite = (_) => true;
    await tap(tester, 'scene-voice-1');
    for (var i = 0; i < 5; i++) { await tick(tester, 100); }
    expect(find.descendant(of: key('scene-voice-4'), matching: find.byKey(GlowSelection.markerKey)),
      findsOneWidget);
    expect(find.descendant(of: key('scene-voice-1'), matching: find.byKey(GlowSelection.markerKey)),
      findsNothing);
    ble.failWrite = null;
    await tester.ensureVisible(slider);
    for (final value in [0.0, 100.0]) {
      tester.widget<Slider>(slider).onChanged!(value);
      await tick(tester);
      expect(ble.writes.last.sublist(2, 4), [12, value.toInt()]);
    }
    expect(find.text(c.text('micSensitivity')), findsOneWidget);
    expect(find.textContaining(c.text('lastSent', {'command': ''})), findsNothing);
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('last started scene owns the check without moving cards at $width dp', (tester) async {
      await start(tester, connected: true, savedScenes: legacyScene,
        size: Size(width, 1600), scale: 1.3);
      const preset = 'included-police';
      const effect = 'included-effect-1';
      const saved = 'scene-play-1';
      const music = 'scene-voice-1';
      Finder check(String card) => find.descendant(of: key(card),
        matching: find.byKey(GlowSelection.markerKey));
      Future<void> play(String card) async {
        await tap(tester, card);
        for (var i = 0; i < 5; i++) { await tick(tester, 100); }
        await tester.pumpAndSettle();
      }
      Future<void> select(String card) async {
        await tester.scrollUntilVisible(key(card), 100);
        await tester.pumpAndSettle();
        final before = tester.getRect(key(card));
        expect(check(card), findsNothing);
        await play(card);
        expect(check(card), findsOneWidget);
        expect(tester.getRect(key(card)), before);
        final material = tester.widget<Material>(find.descendant(of: key(card),
          matching: find.byType(Material)).first);
        expect(material.color, GlowSelection.tint);
        expect((material.shape as RoundedRectangleBorder).side, GlowSelection.border);
      }
      await tap(tester, 'scenes-included');
      await select(preset);
      await select(effect);
      await tester.scrollUntilVisible(key(preset), 100);
      expect(check(preset), findsNothing);
      await tap(tester, 'scenes-mine');
      ble.failWrite = (_) => true;
      await play(saved);
      expect(check(saved), findsNothing);
      await tap(tester, 'scenes-included');
      expect(check(effect), findsOneWidget);
      ble.failWrite = null;
      await tap(tester, 'scenes-mine');
      await select(saved);
      await tap(tester, 'scenes-included');
      expect(check(effect), findsNothing);
      await tap(tester, 'scenes-music');
      await select(music);
      await tap(tester, 'scenes-mine');
      expect(check(saved), findsNothing);
      await select(saved);
      await tap(tester, 'scenes-music');
      expect(check(music), findsNothing);
      c.setForeground(false);
      await tick(tester, 100);
    });
  }

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
    expect(tester.widget<GlowPrimaryButton>(key('scene-new')).onPressed, isNull);
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

  for (final language in const ['es', 'en']) {
    testWidgets('scene cards say which need the app open and connected ($language)', (tester) async {
      await start(tester, size: const Size(320, 915), savedScenes: legacyScene);
      c.setLanguage(language);
      await tester.pumpAndSettle();
      await tap(tester, 'scenes-included');
      Future<String> tagOf(String card) async {
        await tester.scrollUntilVisible(key(card), 100);
        return tester.widget<Text>(find.descendant(of: key(card),
          matching: find.byKey(const Key('scene-runtime-tag')))).data!;
      }
      expect(find.text(c.text('needsAppLegend')), findsOneWidget);
      for (final preset in homePresets.keys) {
        expect(await tagOf('included-$preset'), c.text('needsApp'), reason: preset);
      }
      for (final id in const [255, 1, 2]) {
        expect(await tagOf('included-effect-$id'), c.text('onStrip'), reason: '$id');
      }
      await tap(tester, 'scenes-mine');
      expect(await tagOf('scene-play-1'), c.text('needsApp'));
      expect(find.text(c.text('mineNeedsAppNote')), findsOneWidget);
      expect(c.text('foregroundPlaybackHint'), contains(language == 'es' ? 'conectada' : 'connected'));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale, language) in const [(320.0, 1.0, 'es'), (320.0, 1.3, 'es'),
      (320.0, 1.0, 'en'), (412.0, 1.0, 'es'), (412.0, 1.3, 'en')]) {
    testWidgets('scene tabs keep labels and heights stable at $width dp x$scale $language', (tester) async {
      await start(tester, size: Size(width, 915), scale: scale);
      c.setLanguage(language);
      await tester.pumpAndSettle();
      const ids = ['included', 'mine', 'music'];
      final targets = find.descendant(of: find.byType(GlowSegments<String>),
        matching: find.byType(GlowSelectionTarget));
      Map<String, Rect> labels() => {for (final id in ids) id: tester.getRect(key('scenes-$id'))};
      List<double> heights() => [for (var i = 0; i < 3; i++) tester.getSize(targets.at(i)).height];
      final first = labels();
      for (final id in ids) {
        await tap(tester, 'scenes-$id');
        final checks = find.descendant(of: find.byType(GlowSegments<String>),
          matching: find.byKey(GlowSelection.markerKey));
        expect(checks, findsOneWidget, reason: 'one visible check for $id');
        final now = labels();
        for (final other in ids) {
          expect(now[other], first[other], reason: '$other label moved when $id selected');
        }
        final h = heights();
        expect(h.toSet().length, 1, reason: 'segment heights differ when $id selected: $h');
        final check = tester.getRect(checks);
        final target = tester.getRect(targets.at(ids.indexOf(id)));
        expect(check.center.dy, closeTo(target.center.dy, 1), reason: 'check centered vertically');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('my scenes note keeps a 12 dp gap above the cards', (tester) async {
    await start(tester, savedScenes: legacyScene);
    await tap(tester, 'scenes-mine');
    final note = find.text(c.text('mineNeedsAppNote'));
    final noteBox = find.ancestor(of: note, matching: find.byType(DecoratedBox)).first;
    expect(tester.getTopLeft(key('scene-play-1')).dy - tester.getBottomLeft(noteBox).dy,
      closeTo(12, 0.5));
  });

  testWidgets('included lists strip effects first, then app-driven scenes', (tester) async {
    await start(tester, size: const Size(412, 3000));
    await tap(tester, 'scenes-included');
    final ids = ['included-effect-255', 'included-effect-1', 'included-effect-2',
      for (final preset in homePresets.keys) 'included-$preset'];
    final tops = [for (final id in ids) tester.getTopLeft(key(id))];
    for (var i = 1; i < tops.length; i++) {
      final before = tops[i - 1], now = tops[i];
      expect(now.dy > before.dy || (now.dy == before.dy && now.dx > before.dx), isTrue,
        reason: '${ids[i]} should follow ${ids[i - 1]}');
    }
  });
}
