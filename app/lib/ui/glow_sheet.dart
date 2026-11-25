import 'package:material_ui/material_ui.dart';

/// Shared Glow Glass surface and route chrome for modal sheets.
class GlowSheet extends StatelessWidget {
  const GlowSheet({super.key = const Key('glow-sheet'), required this.child});

  final Widget child;

  static Future<T?> open<T>(BuildContext context, {required WidgetBuilder builder,
    bool enableDrag = true, bool showDragHandle = false, BoxConstraints? constraints}) =>
    showModalBottomSheet<T>(context: context, isScrollControlled: true,
      useSafeArea: true, enableDrag: enableDrag, showDragHandle: showDragHandle,
      clipBehavior: Clip.antiAlias, constraints: constraints,
      builder: (context) => GlowSheet(child: builder(context)));

  @override
  Widget build(BuildContext context) => Ink(
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xff201840), Color(0xff120e26)])),
    child: child,
  );
}
