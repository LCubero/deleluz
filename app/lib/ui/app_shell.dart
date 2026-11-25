import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import 'glow_glass.dart';
import 'home.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const tabs = ['home', 'color', 'scenes', 'settings'];
  static const icons = [Icons.home_outlined, Icons.palette_outlined,
    Icons.auto_awesome_outlined, Icons.settings_outlined];
  int _tab = 0;
  double _travel = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setForeground(state == AppLifecycleState.resumed);
  }

  void _show(int index) => setState(() => _tab = index % tabs.length);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(listenable: controller, builder: (context, _) => Scaffold(
      body: GlowBackdrop(child: SafeArea(bottom: false, child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _travel = 0,
            onHorizontalDragUpdate: (details) => _travel += details.delta.dx,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_travel.abs() < 48 && velocity.abs() < 400) return;
              _show(_tab + ((_travel == 0 ? velocity : _travel) < 0 ? 1 : -1));
            },
            child: IndexedStack(index: _tab, sizing: StackFit.expand, children: [
              HomeScreen(controller: controller, openScenes: () => _show(2)),
              for (final tab in tabs.skip(1))
                Align(key: Key('placeholder-$tab'), alignment: Alignment.topCenter,
                  child: Padding(padding: const EdgeInsets.all(18),
                    child: ConnectionChip(controller: controller))),
            ]),
          ),
        ),
      ))),
      bottomNavigationBar: Material(color: const Color(0xff17122c), child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(child: Semantics(selected: _tab == index, button: true,
              child: InkWell(onTap: () => _show(index), child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icons[index], color: index == _tab ? const Color(0xffedb7ff) : glowMuted),
                  const SizedBox(height: 4),
                  Text(controller.text(tabs[index]), textAlign: TextAlign.center,
                    style: TextStyle(color: index == _tab ? glowInk : glowMuted,
                      fontWeight: index == _tab ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12)),
                ]),
              )),
            )),
        ]),
      )),
    ));
  }
}
