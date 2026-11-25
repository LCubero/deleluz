import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Stroke geometry from the inline SVG symbols in webapp/index.html.
enum GlowGlyph { wave, home, color, scenes, settings, sun, power, timer, bluetooth, chevron }

class GlowIcon extends StatelessWidget {
  const GlowIcon(this.glyph, {super.key, this.size = 22, this.color,
    this.highlight = false});

  final GlowGlyph glyph;
  final double size;
  final Color? color;
  final bool highlight;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: glyph == GlowGlyph.wave ? const Size(30, 18) : Size.square(size),
    painter: _GlowIconPainter(glyph, color ?? IconTheme.of(context).color ?? Colors.white, highlight),
  );
}

class _GlowIconPainter extends CustomPainter {
  const _GlowIconPainter(this.glyph, this.color, this.highlight);
  final GlowGlyph glyph;
  final Color color;
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final wave = glyph == GlowGlyph.wave;
    final sx = size.width / (wave ? 30 : 24);
    final sy = size.height / (wave ? 18 : 24);
    canvas.scale(sx, sy);
    final path = Path();
    void line(List<Offset> points, {bool close = false}) {
      path.addPolygon(points, close);
    }
    void circle(double x, double y, double radius) {
      path.addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
    }
    switch (glyph) {
      case GlowGlyph.wave:
        path.moveTo(2, 14);
        path.relativeCubicTo(4, -12, 8, -12, 13, -5);
        path.relativeCubicTo(5, 7, 9, 7, 13, -5);
      case GlowGlyph.home:
        line(const [Offset(4, 11), Offset(12, 4), Offset(20, 11), Offset(20, 20),
          Offset(15, 20), Offset(15, 14), Offset(9, 14), Offset(9, 20), Offset(4, 20)], close: true);
      case GlowGlyph.color:
        circle(12, 12, 8);
        circle(12, 12, 3);
      case GlowGlyph.scenes:
        line(const [Offset(12, 3), Offset(21, 8), Offset(12, 13), Offset(3, 8)], close: true);
        line(const [Offset(3, 13), Offset(12, 18), Offset(21, 13)]);
      case GlowGlyph.settings:
        line(const [Offset(4, 7), Offset(13, 7)]);
        line(const [Offset(17, 7), Offset(20, 7)]);
        line(const [Offset(4, 17), Offset(7, 17)]);
        line(const [Offset(11, 17), Offset(20, 17)]);
        circle(15, 7, 2);
        circle(9, 17, 2);
      case GlowGlyph.sun:
        circle(12, 12, 4);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final direction = Offset(math.cos(angle), math.sin(angle));
          line([const Offset(12, 12) + direction * 8, const Offset(12, 12) + direction * 10]);
        }
      case GlowGlyph.power:
        line(const [Offset(12, 3), Offset(12, 11)]);
        path.moveTo(6.3, 7.3);
        path.arcToPoint(const Offset(17.7, 7.3), radius: const Radius.circular(8),
          largeArc: true, clockwise: false);
      case GlowGlyph.timer:
        circle(12, 13, 8);
        line(const [Offset(12, 9), Offset(12, 13), Offset(14.5, 15)]);
        line(const [Offset(9, 2), Offset(15, 2)]);
      case GlowGlyph.bluetooth:
        line(const [Offset(7, 7), Offset(17, 17), Offset(12, 21), Offset(12, 3),
          Offset(17, 7), Offset(7, 17)]);
      case GlowGlyph.chevron:
        line(const [Offset(9, 6), Offset(15, 12), Offset(9, 18)]);
    }
    final ink = Paint()..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = wave ? 4 : 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (highlight) {
      canvas.drawPath(path, Paint()..color = const Color(0xffec4899)
        ..style = PaintingStyle.stroke..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    if (wave) {
      ink.shader = const LinearGradient(colors: [Color(0xffa855f7), Color(0xffec4899)])
        .createShader(const Rect.fromLTWH(2, 0, 26, 18));
    }
    canvas.drawPath(path, ink);
  }

  @override
  bool shouldRepaint(_GlowIconPainter oldDelegate) =>
    glyph != oldDelegate.glyph || color != oldDelegate.color || highlight != oldDelegate.highlight;
}
