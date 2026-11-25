import 'package:material_ui/material_ui.dart';

import 'glow_glass.dart';

enum NoticeKind { info, warning, error }

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.kind = NoticeKind.info, this.live = false,
    this.icon, this.heading, this.prominent = false, this.compact = false, this.action});

  final String text;
  final NoticeKind kind;
  final bool live;
  final IconData? icon;
  final String? heading;
  final Widget? action;
  final bool prominent, compact;

  static const warningColor = Color(0xfffbbf24);
  static const warningSurface = Color(0xff251e2c);

  @override
  Widget build(BuildContext context) {
    final (glyph, color) = switch (kind) {
      NoticeKind.info => (Icons.info_outline, glowLink),
      NoticeKind.warning => (Icons.warning_amber_rounded, warningColor),
      NoticeKind.error => (Icons.error_outline, Color(0xfff87171)),
    };
    final theme = Theme.of(context).textTheme;
    return Semantics(liveRegion: live, child: DecoratedBox(
      decoration: BoxDecoration(color: prominent ? null : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: prominent ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 4 : 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          ExcludeSemantics(child: Icon(icon ?? glyph, color: color, size: glassInset)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (heading != null) Text(heading!, style: theme.titleMedium?.copyWith(color: color)),
            Text(text, style: theme.bodySmall?.copyWith(color: glowMuted)),
            ?action,
          ])),
        ]),
      ),
    ));
  }
}
