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
const glowGlassSelected = Color(0x1cffffff);
const glowFaint = Color(0xff8f88b3);
const glowLink = Color(0xfff0abfc);
const glowStrongGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xff7e22ce), Color(0xffbe185d)]);
const glassInset = 16.0;
const glowScreenPadding = EdgeInsets.fromLTRB(18, 16, 18, 18);

ThemeData glowTheme() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: glowViolet, brightness: Brightness.dark)
        .copyWith(primary: const Color(0xffe3c2ff), surface: const Color(0xff1b1636),
            onSurface: glowInk, onSurfaceVariant: glowMuted),
    scaffoldBackgroundColor: glowBackground,
    sliderTheme: const SliderThemeData(trackHeight: 10, trackShape: _FlushSliderTrack(),
      thumbShape: _GlowThumb(), overlayShape: RoundSliderOverlayShape(overlayRadius: 22)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: const Color(0xff7e22ce), foregroundColor: Colors.white,
      minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    )),
  );
  return theme.copyWith(textTheme: theme.textTheme.copyWith(
    bodyMedium: const TextStyle(fontSize: 15, height: 1.4, color: glowInk),
    bodySmall: const TextStyle(fontSize: 13, height: 1.4, color: glowMuted),
    titleLarge: const TextStyle(fontSize: 22, letterSpacing: -.44, fontWeight: FontWeight.w700, color: glowInk),
    titleMedium: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w700, color: glowInk),
  ));
}

// Remove the default horizontal track inset without shrinking the touch target.
class _FlushSliderTrack extends RoundedRectSliderTrackShape {
  const _FlushSliderTrack();

  @override
  Rect getPreferredRect({required RenderBox parentBox, Offset offset = Offset.zero,
    required SliderThemeData sliderTheme, bool isEnabled = false, bool isDiscrete = false}) {
    final track = super.getPreferredRect(parentBox: parentBox, offset: offset,
      sliderTheme: sliderTheme, isEnabled: isEnabled, isDiscrete: isDiscrete);
    return Rect.fromLTRB(offset.dx, track.top, offset.dx + parentBox.size.width, track.bottom);
  }

  @override
  void paint(PaintingContext context, Offset offset, {required RenderBox parentBox,
    required SliderThemeData sliderTheme, required Animation<double> enableAnimation,
    required TextDirection textDirection, required Offset thumbCenter, Offset? secondaryOffset,
    bool isDiscrete = false, bool isEnabled = false, double additionalActiveTrackHeight = 2}) {
    final track = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    final outline = RRect.fromRectAndRadius(track, const Radius.circular(99));
    final canvas = context.canvas;
    canvas.drawRRect(outline, Paint()..color = const Color(0x1fffffff));
    final x = thumbCenter.dx.clamp(track.left, track.right).toDouble();
    final rtl = textDirection == TextDirection.rtl;
    final fill = Rect.fromLTRB(rtl ? x : track.left, track.top, rtl ? track.right : x, track.bottom);
    if (fill.isEmpty) return;
    final alpha = .45 + .55 * enableAnimation.value;
    final gradient = LinearGradient(begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
      end: rtl ? Alignment.centerLeft : Alignment.centerRight,
      colors: [glowViolet.withValues(alpha: alpha), glowPink.withValues(alpha: alpha)]);
    canvas.save();
    canvas.clipRRect(outline);
    canvas.drawRect(fill, Paint()..shader = gradient.createShader(fill));
    canvas.restore();
  }
}

class _GlowThumb extends RoundSliderThumbShape {
  const _GlowThumb() : super(enabledThumbRadius: 14);

  @override
  void paint(PaintingContext context, Offset center, {required Animation<double> activationAnimation,
    required Animation<double> enableAnimation, required bool isDiscrete, required TextPainter labelPainter,
    required RenderBox parentBox, required SliderThemeData sliderTheme, required TextDirection textDirection,
    required double value, required double textScaleFactor, required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    final alpha = .45 + .55 * enableAnimation.value;
    canvas.drawCircle(center.translate(0, 4), 14, Paint()..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(center, 18, Paint()..color = glowViolet.withValues(alpha: .4 * alpha));
    canvas.drawCircle(center, 14, Paint()..color = Colors.white.withValues(alpha: alpha));
  }
}

class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: const _BackdropPainter(), child: child);
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset center, double x, double y, Color color) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(x, y);
      final shader = RadialGradient(radius: .5, colors: [color, color.withValues(alpha: 0)],
        stops: const [0, .7]).createShader(const Rect.fromLTWH(-1, -1, 2, 2));
      canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
      canvas.restore();
    }
    // CSS paints the first listed background above the second.
    glow(Offset(size.width, size.height * .7), 400, 340, const Color(0x2eec4899));
    glow(Offset(size.width * .1, 0), 420, 300, const Color(0x4da855f7));
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

/// Keeps a drag that starts on a slider's label, track or padding in its zone.
class SliderZone extends StatelessWidget {
  const SliderZone({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    // The slider can win on its track; a vertical scroll can still win anywhere.
    onHorizontalDragStart: (_) {},
    child: child,
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.verticalInset = glassInset});
  final Widget child;
  final double verticalInset;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: glassInset, vertical: verticalInset),
    decoration: BoxDecoration(color: glowGlass, border: Border.all(color: glowLine),
      borderRadius: BorderRadius.circular(24)),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class GlowGrid extends StatelessWidget {
  const GlowGrid({super.key, required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(spacing: 10, children: [
    for (var start = 0; start < children.length; start += columns)
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
        for (var i = start; i < start + columns; i++)
          Expanded(child: i < children.length ? children[i] : const SizedBox.shrink()),
      ]),
  ]);
}

class GlowTile extends StatelessWidget {
  const GlowTile({super.key, required this.child, required this.onTap,
    this.onLongPress, this.minHeight = 64, this.inset = 10});
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double minHeight, inset;

  @override
  Widget build(BuildContext context) => Material(color: glowGlass,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: glowLine)),
    child: InkWell(onTap: onTap, onLongPress: onLongPress, borderRadius: BorderRadius.circular(16),
      child: Container(constraints: BoxConstraints(minHeight: minHeight),
        padding: EdgeInsets.all(inset), child: child)),
  );
}

// Illustrative swatch for controller effects, whose actual colors are not read.
const glowEffectColors = [[236, 72, 153], [168, 85, 247], [34, 211, 238]];

class GlowStrip extends StatelessWidget {
  const GlowStrip({super.key, required this.colors, this.height = 10, this.dotted = true, this.glow});
  final List<List<int>> colors;
  final double height;
  final bool dotted;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final stops = [for (final rgb in colors) Color.fromARGB(255, rgb[0], rgb[1], rgb[2])];
    return Container(height: height, decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: stops.isEmpty ? const Color(0xff2a2540) : stops.first,
      gradient: stops.length > 1 ? LinearGradient(colors: stops) : null,
      boxShadow: glow == null ? null : [BoxShadow(color: glow!.withValues(alpha: .55), blurRadius: 22)],
    ), child: dotted ? const CustomPaint(painter: _StripDots()) : null);
  }
}

class _StripDots extends CustomPainter {
  const _StripDots();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(99)));
    final paint = Paint()..color = const Color(0x73000000);
    for (double x = 6; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripDots oldDelegate) => false;
}

class GlowHeader extends StatelessWidget {
  const GlowHeader({super.key, required this.title, required this.controller,
    this.leading, this.actions = const [], this.showStatus = true});

  final String title;
  final AppController controller;
  final Widget? leading;
  final List<Widget> actions;
  final bool showStatus;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final theme = Theme.of(context).textTheme;
    final chip = ConnectionChip(controller: controller);
    double widthOf(String text, TextStyle? style) {
      final painter = TextPainter(text: TextSpan(text: text, style: style),
        textScaler: MediaQuery.textScalerOf(context), textDirection: Directionality.of(context))..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }
    final titleStyle = leading == null ? theme.titleLarge
      : theme.titleLarge?.copyWith(fontSize: 20, letterSpacing: -.2);
    final chipWidth = widthOf(controller.text(controller.link.status.name), ConnectionChip.textStyle)
        + ConnectionChip.horizontalChrome + 12; // Margin: measured text can differ from the rendered font.
    final inline = showStatus && widthOf(title, titleStyle) + (leading == null ? 0 : 38)
        + 48 * actions.length + 8 + chipWidth <= constraints.maxWidth;
    final row = ConstrainedBox(constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        if (leading != null) ...[SizedBox(width: 30, child: leading), const SizedBox(width: 8)],
        Expanded(child: Text(title, style: titleStyle)),
        for (final action in actions) SizedBox(width: 48, child: action),
        if (inline) ...[const SizedBox(width: 8), chip],
      ]));
    return inline || !showStatus ? row : Column(crossAxisAlignment: CrossAxisAlignment.end,
      children: [row, const SizedBox(height: 4), chip]);
  });
}

class GlowValueLabel extends StatelessWidget {
  const GlowValueLabel({super.key, required this.label, required this.value, this.icon});
  final String label, value;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(fontWeight: FontWeight.w600), child: Row(spacing: 8,
      children: [?icon, Expanded(child: Text(label)), Text(value, textAlign: TextAlign.end)],
    ));
}

class GlowDisclosure extends StatelessWidget {
  const GlowDisclosure({super.key, required this.title, required this.children,
    this.titleKey, this.initiallyExpanded = false, this.onExpansionChanged,
    this.padding = EdgeInsets.zero, this.minHeight = 56,
    this.inlineChevron = false, this.smallChevron = false});
  final String title;
  final Key? titleKey;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsets padding;
  final double minHeight;
  final bool inlineChevron, smallChevron;
  static const _chevron = Icon(Icons.chevron_right, size: 18);

  @override
  Widget build(BuildContext context) {
    final label = Text(title, key: titleKey, style: TextStyle(fontSize: 15,
      fontWeight: inlineChevron ? FontWeight.w700 : FontWeight.w600,
      color: inlineChevron ? Colors.white : glowInk));
    return ExpansionTile(
      tilePadding: padding,
      minTileHeight: minHeight,
      shape: const Border(), collapsedShape: const Border(),
      controlAffinity: ListTileControlAffinity.trailing,
      showTrailingIcon: !inlineChevron,
      trailing: smallChevron ? _chevron : null,
      title: inlineChevron ? Row(children: [Flexible(child: label), _chevron]) : label,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }
}

class GlowSegments<T> extends StatelessWidget {
  const GlowSegments({super.key, required this.segments, required this.selected,
    required this.onSelected});
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Material(color: glowGlass,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: glowLine)),
    child: Padding(padding: const EdgeInsets.all(4), child: Row(children: [
      for (final segment in segments) Expanded(child: Semantics(button: true,
        selected: segment.value == selected, child: Material(
          color: segment.value == selected ? glowGlassSelected : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
            side: segment.value == selected ? const BorderSide(color: Color(0x2effffff)) : BorderSide.none),
          child: InkWell(borderRadius: BorderRadius.circular(10),
            onTap: segment.enabled ? () => onSelected(segment.value) : null,
            child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44),
              child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: DefaultTextStyle.merge(textAlign: TextAlign.center,
                  style: TextStyle(fontSize: segments.length == 3 ? 14 : 15, fontWeight: FontWeight.w600,
                    color: segment.value == selected ? glowInk : glowMuted),
                  child: segment.label ?? const SizedBox.shrink())))),
          ),
        ),
      )),
    ])));
}

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.controller});
  final AppController controller;
  static const _horizontalPadding = 12.0;
  static const _dotSize = 8.0;
  static const _gap = 8.0;
  static const textStyle = TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: glowInk);
  // Padding, border, indicator, and gap; the remaining width is the status text.
  static const horizontalChrome = 2 * _horizontalPadding + 2 + _dotSize + _gap;

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
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding, vertical: 6),
      decoration: BoxDecoration(color: glowGlassSelected,
        border: Border.all(color: glowLine), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: _dotSize, height: _dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle,
            boxShadow: status == LinkStatus.idle ? null : [BoxShadow(color: color, blurRadius: 10)])),
        const SizedBox(width: _gap),
        Flexible(child: Text(controller.text(status.name), style: textStyle,
          maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
