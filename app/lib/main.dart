import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'model/models.dart';
import 'ui/app_shell.dart';
import 'ui/glow_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = PreferencesStore(await SharedPreferences.getInstance());
  runApp(MainApp(controller: AppController(AppBleApi(), store,
      checkAccess: bluetoothAccess)));
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
