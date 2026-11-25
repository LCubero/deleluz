import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Full-value HSV picker: red at the top, hue clockwise, white at the center.
class ColorDisc extends StatelessWidget {
  const ColorDisc({super.key, required this.color, required this.label,
    required this.onChanged, this.maxDiameter = 216});

  final Color color;
  final String label;
  final ValueChanged<HSVColor> onChanged;
  final double maxDiameter;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    final radians = hsv.hue * math.pi / 180;
    final hex = (color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');
    return Center(child: Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: math.min(maxDiameter, MediaQuery.sizeOf(context).width * .55),
        child: LayoutBuilder(builder: (context, constraints) {
          final radius = constraints.maxWidth / 2;
          final center = Offset(radius, radius);
          void select(Offset position) {
            final delta = position - center;
            final saturation = (delta.distance / radius).clamp(0.0, 1.0);
            final hue = saturation == 0 ? hsv.hue
                : (math.atan2(delta.dx, -delta.dy) * 180 / math.pi) % 360;
            onChanged(HSVColor.fromAHSV(1, hue, saturation, 1));
          }

          void start(DragStartDetails details) => select(details.localPosition);
          void update(DragUpdateDetails details) => select(details.localPosition);

          return Semantics(label: label, value: '#${hex.toUpperCase()}',
            child: GestureDetector(
              key: const Key('color-disc'),
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if ((details.localPosition - center).distance <= radius) {
                  select(details.localPosition);
                }
              },
              // Compete on both axes so the disc wins over page scrolling and tab swipes.
              onHorizontalDragStart: start, onHorizontalDragUpdate: update,
              onVerticalDragStart: start, onVerticalDragUpdate: update,
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x40a855f7), blurRadius: 38)],
                  gradient: SweepGradient(transform: GradientRotation(-math.pi / 2), colors: [
                    Color(0xffff0000), Color(0xffffff00), Color(0xff00ff00), Color(0xff00ffff),
                    Color(0xff0000ff), Color(0xffff00ff), Color(0xffff0000),
                  ]),
                ))),
                const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(radius: .5, colors: [Colors.white, Color(0x00ffffff)]),
                ))),
                Transform.translate(
                  offset: Offset(math.sin(radians), -math.cos(radians)) * (radius * hsv.saturation),
                  child: Container(width: 24, height: 24, decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0xaa0a0918), offset: Offset(0, 2), blurRadius: 8)],
                  )),
                ),
              ]),
            ),
          );
        }),
      ),
    ));
  }
}
