import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'model/models.dart';
import 'ui/app_shell.dart';
import 'ui/glow_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await loadStore();
  runApp(MainApp(controller: AppController(AppBleApi(), store,
      checkAccess: bluetoothAccess)));
}

Future<LocalStore> loadStore({
  Future<SharedPreferences> Function() preferences = SharedPreferences.getInstance,
}) async {
  try {
    return PreferencesStore(await preferences());
  } catch (_) {
    return _MemoryStore();
  }
}

class _MemoryStore implements LocalStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<bool> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    return true;
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DeleLuz',
    debugShowCheckedModeBanner: false,
    theme: glowTheme(),
    home: AppShell(controller: controller),
  );
}
