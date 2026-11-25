import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';

const glowBackground = Color(0xff0a0918);
const glowInk = Color(0xfff5f3ff);
const glowMuted = Color(0xffbdb6dc);
const glowViolet = Color(0xffa855f7);
const glowPink = Color(0xffec4899);
const glowLine = Color(0x24ffffff);
const glowGlass = Color(0x11ffffff);

ThemeData glowTheme() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: glowViolet, brightness: Brightness.dark)
        .copyWith(primary: const Color(0xffe3c2ff), surface: const Color(0xff1b1636),
            onSurface: glowInk, onSurfaceVariant: glowMuted),
    scaffoldBackgroundColor: glowBackground,
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: const Color(0xff7e22ce), foregroundColor: Colors.white,
      minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    )),
  );
  return theme.copyWith(textTheme: theme.textTheme.copyWith(
    bodyMedium: const TextStyle(fontSize: 15, height: 1.4, color: glowInk),
    bodySmall: const TextStyle(fontSize: 13, height: 1.4, color: glowMuted),
    titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: glowInk),
  ));
}

class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: RadialGradient(
      center: Alignment(-.9, -1), radius: .85,
      colors: [Color(0x4da855f7), Colors.transparent],
    )),
    child: DecoratedBox(
      decoration: const BoxDecoration(gradient: RadialGradient(
        center: Alignment(1, .55), radius: .65,
        colors: [Color(0x2eec4899), Colors.transparent],
      )), child: child,
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: glowGlass, border: Border.all(color: glowLine),
      borderRadius: BorderRadius.circular(24)),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.link.status;
    final color = switch (status) {
      LinkStatus.idle => const Color(0xff8f88b3),
      LinkStatus.connecting => const Color(0xfffbbf24),
      LinkStatus.connected => const Color(0xff4ade80),
      LinkStatus.lost => const Color(0xfff87171),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0x1cffffff),
        border: Border.all(color: glowLine), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(child: Text(controller.text(status.name), style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
