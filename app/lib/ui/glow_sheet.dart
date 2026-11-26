import 'package:material_ui/material_ui.dart';

/// Shared Glow Glass surface and route chrome for modal sheets.
class GlowSheet extends StatelessWidget {
  const GlowSheet({super.key = const Key('glow-sheet'), required this.child,
    this.showDragHandle = false});

  final Widget child;
  final bool showDragHandle;

  static Future<T?> open<T>(BuildContext context, {required WidgetBuilder builder,
    bool enableDrag = true, bool showDragHandle = false, BoxConstraints? constraints}) =>
    showModalBottomSheet<T>(context: context, isScrollControlled: true,
      useSafeArea: true, enableDrag: enableDrag, showDragHandle: false,
      clipBehavior: Clip.antiAlias, constraints: constraints,
      builder: (context) => GlowSheet(showDragHandle: showDragHandle, child: builder(context)));

  @override
  Widget build(BuildContext context) => Ink(
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xff201840), Color(0xff120e26)])),
    // Paint the handle and content on one continuous gradient. Route drag still applies.
    child: showDragHandle ? Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 48, child: Center(child: Container(
        key: const Key('glow-sheet-handle'), width: 32, height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).bottomSheetTheme.dragHandleColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(99)),
      ))),
      Flexible(child: child),
    ]) : child,
  );
}
