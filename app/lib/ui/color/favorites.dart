import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';
import '../glow_glass.dart';

/// Uses the same persisted palette as the scene editor and shortcut picker.
class ColorFavorites extends StatefulWidget {
  const ColorFavorites({super.key, required this.controller, required this.current,
    required this.onColor});

  final AppController controller;
  final String current;
  final ValueChanged<List<int>> onColor;

  @override
  State<ColorFavorites> createState() => _ColorFavoritesState();
}

class _ColorFavoritesState extends State<ColorFavorites> {
  static const _openKey = 'deleluz.app.favoritesOpen.color';
  AppController get c => widget.controller;
  late bool _open;
  bool _saving = false;
  String? _slot;
  String? _dragging;
  String? _message;

  @override
  void initState() {
    super.initState();
    try {
      _open = c.models.storage.read(_openKey) == '1';
    } catch (_) {
      _open = false;
    }
  }

  Future<void> _persistOpen(bool value) async {
    try {
      await c.models.storage.write(_openKey, value ? '1' : '0');
    } catch (_) {
      // Keep the open state in memory when the store is unavailable.
    }
  }

  Future<void> _save(List<String> before, List<String> after) async {
    if (_saving) return;
    setState(() {
      _slot = null;
      _message = null;
      _saving = !identical(before, after);
    });
    if (!_saving) return;
    final saved = await c.models.savePalette(after);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) _message = 'appStorageFailed';
    });
  }

  void _plus() {
    final before = c.models.loadPalette();
    final index = before.indexOf(_slot ?? '');
    if (index < 0 && before.length >= paletteLimit) {
      setState(() => _message = 'paletteFull');
      return;
    }
    final after = index < 0 ? addPaletteColor(before, widget.current) :
        replacePaletteColor(before, index, widget.current);
    unawaited(_save(before, after));
  }

  void _drop(String source, String? target) {
    final before = c.models.loadPalette();
    final from = before.indexOf(source);
    final after = target == null ? removeItem(before, from) :
        moveItem(before, from, before.indexOf(target));
    unawaited(_save(before, after));
  }

  Widget _swatch(String hex) {
    final rgb = [for (final i in [1, 3, 5]) int.parse(hex.substring(i, i + 2), radix: 16)];
    final name = colorName(hex);
    final label = name == 'solid' ? c.text('paletteColorHex', {'hex': hex.toUpperCase()}) : c.text(name);
    final color = Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
    final selected = widget.current == hex;
    Widget circle(bool highlighted) => SizedBox.square(dimension: 34, child: DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color,
        border: Border.all(color: highlighted ? Colors.white : glowLine, width: 2)),
    ));
    return DragTarget<String>(key: Key('favorite-$hex'),
      onWillAcceptWithDetails: (details) => !_saving && details.data != hex,
      onAcceptWithDetails: (details) => _drop(details.data, hex),
      builder: (_, incoming, rejected) => LongPressDraggable<String>(
        data: hex, maxSimultaneousDrags: _saving ? 0 : 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: FractionalTranslation(translation: const Offset(-.5, -.5), child: circle(true)),
        onDragStarted: () => setState(() => _dragging = hex),
        onDragEnd: (_) { if (mounted) setState(() => _dragging = null); },
        child: Semantics(label: label, child: Tooltip(message: label,
          triggerMode: TooltipTriggerMode.manual, excludeFromSemantics: true,
          child: IconButton(isSelected: selected,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48), fixedSize: const Size.square(48),
              padding: EdgeInsets.zero,
              side: BorderSide(color: _slot == hex ? glowViolet :
                  selected ? Colors.white : Colors.transparent, width: 2),
            ),
            onPressed: _saving ? null : () {
              setState(() { _slot = hex; _message = null; });
              widget.onColor(rgb);
            }, icon: circle(incoming.isNotEmpty)),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _open ? c.models.loadPalette() : const <String>[];
    final trash = _dragging != null;
    final style = Theme.of(context).textTheme.bodySmall;
    return GlowDisclosure(titleKey: const Key('color-favorites'), minHeight: 44,
      inlineChevron: true,
      title: c.text('favorites'), initiallyExpanded: _open, onExpansionChanged: (open) {
        setState(() => _open = open);
        unawaited(_persistOpen(open));
      }, children: [
      if (_open) ...[
        const SizedBox(height: 8),
        SliderZone(child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final hex in colors) _swatch(hex),
          DragTarget<String>(key: const Key('favorite-plus'),
            onWillAcceptWithDetails: (_) => !_saving,
            onAcceptWithDetails: (details) => _drop(details.data, null),
            builder: (_, incoming, rejected) => IconButton.outlined(
              tooltip: c.text(trash ? 'dropToDelete' : colors.contains(_slot)
                  ? 'replaceSavedColor' : 'saveSelectedColor'),
              onPressed: trash || _saving ? null : _plus,
              icon: Icon(trash ? Icons.delete_outline : Icons.add,
                color: incoming.isEmpty ? null : glowPink),
            ),
          ),
        ])),
        const SizedBox(height: 12),
        Text(c.text('paletteHint'), textAlign: TextAlign.center, style: style),
        if (_message case final message?) Padding(padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(c.text(message),
            textAlign: TextAlign.center, style: style))),
      ],
    ]);
  }
}
