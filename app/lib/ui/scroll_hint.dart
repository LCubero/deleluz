import 'package:material_ui/material_ui.dart';

import 'glow_glass.dart';

/// Reserves a footer outside the viewport so the cue never obscures content.
class ScrollHint extends StatefulWidget {
  const ScrollHint({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<ScrollHint> {
  bool _more = false;

  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    final more = metrics.extentAfter > 0;
    // Scroll notifications can be dispatched during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _more != more) setState(() => _more = more);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (event) {
      _update(event.metrics, event.depth);
      return false;
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (event) {
        _update(event.metrics, event.depth);
        return false;
      },
      child: Column(children: [
        Expanded(child: widget.child),
        SizedBox(height: glassInset, child: _more ? const ExcludeSemantics(
          child: Icon(Icons.keyboard_arrow_down, size: glassInset, color: glowMuted),
        ) : null),
      ]),
    ),
  );
}
