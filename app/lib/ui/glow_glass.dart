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
const glassInset = 16.0;
const glowScreenPadding = EdgeInsets.fromLTRB(18, 10, 18, 18);

ThemeData glowTheme() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: glowViolet, brightness: Brightness.dark)
        .copyWith(primary: const Color(0xffe3c2ff), surface: const Color(0xff1b1636),
            onSurface: glowInk, onSurfaceVariant: glowMuted),
    scaffoldBackgroundColor: glowBackground,
    sliderTheme: const SliderThemeData(trackShape: _FlushSliderTrack()),
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
    padding: const EdgeInsets.all(glassInset),
    decoration: BoxDecoration(color: glowGlass, border: Border.all(color: glowLine),
      borderRadius: BorderRadius.circular(24)),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class GlowHeader extends StatelessWidget {
  const GlowHeader({super.key, required this.title, required this.controller,
    this.leading, this.actions = const []});

  final String title;
  final AppController controller;
  final Widget? leading;
  final List<Widget> actions;

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
    final chipWidth = widthOf(controller.text(controller.link.status.name), theme.bodySmall)
        + ConnectionChip.horizontalChrome;
    final inline = widthOf(title, theme.titleLarge) + (leading == null ? 0 : 32)
        + 48 * actions.length + 8 + chipWidth <= constraints.maxWidth;
    final row = ConstrainedBox(constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        if (leading != null) ...[SizedBox(width: 24, child: leading), const SizedBox(width: 8)],
        Expanded(child: Text(title, style: theme.titleLarge)),
        for (final action in actions) SizedBox(width: 48, child: action),
        if (inline) ...[const SizedBox(width: 8), SizedBox(width: chipWidth, child: chip)],
      ]));
    return inline ? row : Column(crossAxisAlignment: CrossAxisAlignment.end,
      children: [row, const SizedBox(height: 4), chip]);
  });
}

class GlowValueLabel extends StatelessWidget {
  const GlowValueLabel({super.key, required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(spacing: 8,
    crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
    children: [Expanded(child: Text(label)), Text(value, textAlign: TextAlign.end)],
  );
}

class GlowDisclosure extends StatelessWidget {
  const GlowDisclosure({super.key, required this.title, required this.children,
    this.titleKey, this.initiallyExpanded = false, this.onExpansionChanged});
  final String title;
  final Key? titleKey;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.trailing,
    title: Text(title, key: titleKey),
    initiallyExpanded: initiallyExpanded,
    onExpansionChanged: onExpansionChanged,
    children: children,
  );
}

class GlowSegments<T> extends StatelessWidget {
  const GlowSegments({super.key, required this.segments, required this.selected,
    required this.onSelected});
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
    expandedInsets: EdgeInsets.zero,
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
    segments: segments,
    selected: {selected},
    onSelectionChanged: (value) => onSelected(value.single),
  );
}

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.controller});
  final AppController controller;
  static const _horizontalPadding = 12.0;
  static const _dotSize = 8.0;
  static const _gap = 8.0;
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
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding, vertical: 8),
      decoration: BoxDecoration(color: const Color(0x1cffffff),
        border: Border.all(color: glowLine), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: _dotSize, height: _dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: _gap),
        Flexible(child: Text(controller.text(status.name), style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
