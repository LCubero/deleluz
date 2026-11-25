import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'glow_glass.dart';

/// Hue only, matching the fully saturated colors in the web shortcut picker.
class HueWheel extends StatelessWidget {
  const HueWheel({super.key, required this.hue, required this.label, required this.onChanged,
    this.color, this.maxDiameter = 250});

  final double hue;
  final String label;
  final ValueChanged<double> onChanged;
  final Color? color;
  final double maxDiameter;

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: math.min(maxDiameter, MediaQuery.sizeOf(context).width * .7)),
    child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (context, constraints) {
      final size = constraints.maxWidth;
      final radians = hue * math.pi / 180;
      final color = this.color ?? HSVColor.fromAHSV(1, hue, 1, 1).toColor();
      void select(Offset local) {
        final delta = local - Offset(size / 2, size / 2);
        if (delta.distance > 0) {
          onChanged((math.atan2(delta.dx, -delta.dy) * 180 / math.pi) % 360);
        }
      }

      return Semantics(slider: true, label: label, value: '${hue.round()}°',
        increasedValue: '${((hue + 15) % 360).round()}°',
        decreasedValue: '${((hue - 15) % 360).round()}°',
        onIncrease: () => onChanged((hue + 15) % 360),
        onDecrease: () => onChanged((hue - 15) % 360),
        child: SliderZone(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => select(details.localPosition),
          onHorizontalDragStart: (details) => select(details.localPosition),
          onHorizontalDragUpdate: (details) => select(details.localPosition),
          child: Stack(alignment: Alignment.center, children: [
            const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x59a855f7), blurRadius: 60)],
              gradient: SweepGradient(transform: GradientRotation(-math.pi / 2), colors: [
                Color(0xffff0000), Color(0xffffff00), Color(0xff00ff00), Color(0xff00ffff),
                Color(0xff0000ff), Color(0xffff00ff), Color(0xffff0000)]),
            ))),
            Container(width: size * .54, height: size * .54, decoration: BoxDecoration(
              color: const Color(0xff100d22), shape: BoxShape.circle,
              border: Border.all(color: const Color(0x24ffffff)))),
            Container(width: size * .38, height: size * .38, decoration: BoxDecoration(
              color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 30)])),
            Transform.translate(offset: Offset(math.sin(radians), -math.cos(radians)) * (size * .38),
              child: Container(width: 30, height: 30, decoration: BoxDecoration(
                color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4),
                boxShadow: const [BoxShadow(color: Color(0x80000000), offset: Offset(0, 2), blurRadius: 10)]))),
          ]),
        )),
      );
    })),
  ));
}
