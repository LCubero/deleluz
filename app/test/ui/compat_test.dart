import 'package:deleluz/app_controller.dart';
import 'package:deleluz/main.dart';
import 'package:deleluz/ui/glow_glass.dart';
import 'package:deleluz/ui/notice.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_test.dart' show FakeBle, Store;

void main() {
  const phones = [
    (320, 568), (360, 640), (360, 780), (375, 667), (390, 844),
    (384, 832), (393, 851), (411, 834), (412, 892), (412, 915),
    (412, 923), (412, 1004), (428, 926), (432, 960), (448, 998), (480, 854),
  ];
  for (final (width, height) in phones) {
    for (final scale in [1.0, 1.3, if (height == 640 || height == 915) 2.0]) {
      for (final bottom in [0.0, 24.0]) {
        // Exercise both locales at the design skill's boundary widths, without
        // doubling the entire phone matrix.
        for (final language in ['es', if (width == 320 || height == 915) 'en']) {
          testWidgets('$width×$height / $scale / bottom $bottom / $language', (tester) async {
            const density = 2.625;
            const top = 32.0;
            tester.view.devicePixelRatio = density;
            tester.view.physicalSize = Size((width * density).roundToDouble(),
              (height * density).roundToDouble());
            final insets = FakeViewPadding(top: top * density, bottom: bottom * density);
            tester.view.padding = insets;
            tester.view.viewPadding = insets;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            final store = Store();
            await store.write('deleluz.app.favoritesOpen.color', '0');
            final ble = FakeBle();
            final c = AppController(ble, store, checkAccess: (_) async => null);
            addTearDown(() async { c.dispose(); await ble.changes.close(); });
            c.setLanguage(language);
            final issues = <String>{};
            final nav = find.byWidgetPredicate((w) => w is Scaffold && w.bottomNavigationBar != null);
            Finder key(String value) => find.byKey(Key(value));
            Finder label(String value) => find.text(c.text(value));
            Finder tip(String value) => find.byTooltip(c.text(value));
            Finder navLabel(String value) => find.descendant(
              of: find.byWidget(tester.widget<Scaffold>(nav).bottomNavigationBar!), matching: label(value));

            void check(String stage, {bool modal = false}) {
              if (tester.takeException() case final error?) issues.add('$stage: $error');
              final navBox = tester.getRect(find.byWidget(tester.widget<Scaffold>(nav).bottomNavigationBar!));
              final safeBottom = tester.view.physicalSize.height / density - bottom;
              for (final element in find.byType(RichText).hitTestable().evaluate()) {
                final paragraph = element.renderObject! as RenderParagraph;
                final text = paragraph.text.toPlainText();
                // User names and shortcut names intentionally have a display limit.
                final limitedName = paragraph.maxLines != null && element.findAncestorWidgetOfExactType<ConnectionChip>() == null &&
                    element.findAncestorWidgetOfExactType<Notice>() == null;
                if (!limitedName && paragraph.didExceedMaxLines) issues.add('$stage: clipped "$text"');
              }
              final controls = find.byWidgetPredicate((w) => w is ButtonStyleButton ||
                w is IconButton || w is ChoiceChip || w is Slider || w is SwitchListTile ||
                w is InkWell && (w.onTap != null || w.onLongPress != null)).hitTestable();
              for (final element in controls.evaluate()) {
                // Material's visual ink can be smaller than the padded outer hit box.
                if (element.widget is InkWell && (
                    element.findAncestorWidgetOfExactType<IconButton>() != null ||
                    element.findAncestorWidgetOfExactType<ChoiceChip>() != null ||
                    element.findAncestorWidgetOfExactType<TextButton>() != null ||
                    element.findAncestorWidgetOfExactType<FilledButton>() != null ||
                    element.findAncestorWidgetOfExactType<OutlinedButton>() != null ||
                    element.findAncestorWidgetOfExactType<SwitchListTile>() != null)) {
                  continue;
                }
                final control = find.byWidget(element.widget);
                final rect = tester.getRect(control);
                final description = element.widget.key ?? element.widget.runtimeType;
                if (rect.shortestSide < 47.99) issues.add('$stage: $description target ${rect.size}');
                final inNav = !modal && rect.center.dy >= navBox.top;
                final outerBottom = modal || inNav ? safeBottom : navBox.top;
                // Scrollable content may straddle its viewport edge. Verify bounds
                // on fixed controls; scrolled controls are checked in tap().
                if (element.findAncestorWidgetOfExactType<Scrollable>() == null &&
                    (rect.top < top - .01 || rect.bottom > outerBottom + .01)) {
                  issues.add('$stage: $description outside safe bounds ($rect)');
                }
              }
            }

            Future<void> tap(Finder target) async {
              expect(target, findsOneWidget);
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              expect(target.hitTestable(), findsOneWidget, reason: 'Unreachable control: $target');
              final navWidget = tester.widget<Scaffold>(nav).bottomNavigationBar!;
              final navFinder = find.byWidget(navWidget);
              final navBox = tester.getRect(navFinder);
              final rect = tester.getRect(target);
              final onShell = ModalRoute.of(tester.element(target)) == ModalRoute.of(tester.element(navFinder));
              final inNav = rect.top >= navBox.top;
              final boundary = onShell && !inNav ? navBox.top : tester.view.physicalSize.height / density - bottom;
              expect(rect.top, greaterThanOrEqualTo(top - .01), reason: '$target under status bar');
              expect(rect.bottom, lessThanOrEqualTo(boundary + .01), reason: '$target under bottom bar');
              await tester.tap(target);
              await tester.pumpAndSettle();
            }

            await tester.pumpWidget(MainApp(controller: c));
            await tester.pumpAndSettle();
            check('Inicio');
            await tap(tip('offTimer'));
            check('Timer', modal: true);
            await tap(label('custom'));
            check('Custom timer', modal: true);
            await tap(tip('close'));
            await tap(label('quickActions'));
            await tap(tip('addShortcut'));
            check('Quick action types', modal: true);
            for (final type in ['color', 'effect', 'scene', 'sequence']) {
              await tap(key('quick-type-$type'));
              check('Quick action $type', modal: true);
              await tap(tip('quickBack'));
            }
            await tap(tip('close'));
            await tap(navLabel('color'));
            check('Color fijo collapsed');
            await tap(key('color-favorites'));
            check('Color fijo expanded');
            await tap(key('color-effects'));
            check('Efectos integrados');
            await tap(navLabel('scenes'));
            check('Mis escenas');
            final newScene = key('scene-new');
            if (newScene.evaluate().isEmpty) {
              final list = find.byType(ListView).hitTestable();
              final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
              await tester.scrollUntilVisible(newScene, 120, scrollable: scrollable);
            }
            await tap(newScene);
            check('Scene editor', modal: true);
            await tap(key('scene-add-color'));
            check('Scene color step', modal: true);
            await tap(key('scene-apply-step'));
            await tap(key('scene-add-effect'));
            check('Scene effect step', modal: true);
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            await tap(key('scene-close'));
            await tap(key('scenes-included'));
            check('Incluidas');
            await tap(key('scenes-music'));
            check('Música');
            await tap(navLabel('settings'));
            check('Ajustes');
            expect(issues, isEmpty, reason: issues.join('\n'));
          });
        }
      }
    }
  }
}

