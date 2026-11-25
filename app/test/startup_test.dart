import 'dart:io';

import 'package:deleluz/app_controller.dart';
import 'package:deleluz/main.dart';
import 'package:deleluz/model/models.dart' show PreferencesStore;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deleluz/strings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui/home_test.dart' show FakeBle;

class OptimisticPreferences implements SharedPreferences {
  String? cached = 'saved';
  bool accepted = false;

  @override
  String? getString(String key) => cached;

  @override
  Future<bool> setString(String key, String value) async {
    cached = value;
    return accepted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('F8 a rejected preference edit is not read back from the optimistic cache', () async {
    final preferences = OptimisticPreferences();
    final store = PreferencesStore(preferences);
    expect(await store.write('key', 'rejected'), isFalse);
    expect(store.read('key'), 'saved');
    preferences.accepted = true;
    expect(await store.write('key', 'accepted'), isTrue);
    expect(store.read('key'), 'accepted');
  });
  testWidgets('starts with writable in-memory defaults if preferences fail', (tester) async {
    final store = await loadStore(preferences: () async => throw StateError('Preferences unavailable'));
    final ble = FakeBle();
    final controller = AppController(ble, store, checkAccess: (_) async => null);
    addTearDown(ble.changes.close);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MainApp(controller: controller));
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text(controller.text('sessionOnlyStorage')), findsOneWidget);
    expect(controller.language, 'es');
    controller.setLanguage('en');
    await tester.pump();
    expect(controller.models.loadLanguage(), 'en');
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text(controller.text('sessionOnlyStorage')), findsOneWidget);
  });

  test('Android disables backup as promised by the privacy text', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, matches(RegExp(r'<application\b[^>]*\bandroid:allowBackup="false"')));
    expect(translate('es', 'privacyText'), contains('se guardan en el teléfono'));
    expect(translate('en', 'privacyText'), contains('stored on your phone'));
  });
}
