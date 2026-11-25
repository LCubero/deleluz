import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Hue only, matching the fully saturated colors in the web shortcut picker.
class HueWheel extends StatelessWidget {
  const HueWheel({super.key, required this.hue, required this.label, required this.onChanged});

  final double hue;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (context, constraints) {
      final size = constraints.maxWidth;
      final radians = hue * math.pi / 180;
      final color = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
      void select(Offset local) {
        final delta = local - Offset(size / 2, size / 2);
        if (delta.distance > 0) {
          onChanged((math.atan2(delta.dy, delta.dx) * 180 / math.pi) % 360);
        }
      }

      return Semantics(slider: true, label: label, value: '${hue.round()}°',
        increasedValue: '${((hue + 15) % 360).round()}°',
        decreasedValue: '${((hue - 15) % 360).round()}°',
        onIncrease: () => onChanged((hue + 15) % 360),
        onDecrease: () => onChanged((hue - 15) % 360),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => select(details.localPosition),
          onPanStart: (details) => select(details.localPosition),
          onPanUpdate: (details) => select(details.localPosition),
          child: Stack(alignment: Alignment.center, children: [
            const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [Colors.red, Colors.yellow, Colors.greenAccent,
                Colors.cyanAccent, Colors.blue, Colors.pinkAccent, Colors.red]),
            ))),
            Container(width: size * .63, height: size * .63, decoration: const BoxDecoration(
              color: Color(0xff100d22), shape: BoxShape.circle)),
            Container(width: size * .42, height: size * .42, decoration: BoxDecoration(
              color: color, shape: BoxShape.circle)),
            Transform.translate(offset: Offset(math.cos(radians), math.sin(radians)) * (size * .40),
              child: Container(width: 22, height: 22, decoration: BoxDecoration(
                color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
          ]),
        ),
      );
    })),
  ));
}
