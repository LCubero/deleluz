import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/models.dart';
import 'color_disc.dart';
import 'effect_list.dart';
import 'glow_glass.dart';
import 'home_presets.dart';

enum QuickActionKind {
  color('color', 'quickColorHint', Icons.palette_outlined),
  effect('effect', 'quickEffectHint', Icons.auto_awesome),
  scene('quickScene', 'quickSceneHint', Icons.diamond_outlined),
  sequence('quickSequence', 'quickSequenceHint', Icons.layers_outlined);

  const QuickActionKind(this.label, this.hint, this.icon);
  final String label, hint;
  final IconData icon;
}

class QuickActionsSheet extends StatefulWidget {
  const QuickActionsSheet._(this.controller, this.replacing);

  final AppController controller;
  final bool replacing;

  static Future<Fields?> open(BuildContext context, AppController controller, {required bool replacing}) =>
      showModalBottomSheet<Fields>(context: context, isScrollControlled: true,
        useSafeArea: true, enableDrag: false, constraints: const BoxConstraints(maxWidth: 480),
        builder: (context) => QuickActionsSheet._(controller, replacing));

  @override
  State<QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<QuickActionsSheet> {
  static const Fields _neutral = {'kind': 'color', 'rgb': [255, 228, 196], 'name': 'whiteNeutralTone'};
  final _choices = <QuickActionKind, Fields>{QuickActionKind.color: _neutral};
  QuickActionKind? _kind;

  AppController get c => widget.controller;
  Fields? get _selected => _choices[_kind];
  void _select(Fields item) => setState(() => _choices[_kind!] = item);

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() => _kind = null);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final selected = _selected;
    final style = Theme.of(context).textTheme;
    final rgb = selected?['rgb'] as List<int>?;
    return PopScope<Fields>(canPop: kind == null, onPopInvokedWithResult: (popped, _) {
      if (!popped && kind != null) _back();
    }, child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (kind != null) IconButton(tooltip: c.text('quickBack'),
              onPressed: _back, icon: const Icon(Icons.arrow_back)),
            Expanded(child: Semantics(header: true, child: Text(c.text(kind?.label ??
              (widget.replacing ? 'quickChangeTitle' : 'addShortcut')), style: style.titleLarge))),
            IconButton(tooltip: c.text('close'), icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
          ]),
          Text(c.text(kind == null ? 'quickStepType' : 'quickStepOption'), style: style.bodySmall),
          const SizedBox(height: 8),
          Flexible(child: SingleChildScrollView(key: ValueKey(kind), child: switch (kind) {
            null => GlowGrid(columns: 2, children: [
              for (final type in QuickActionKind.values)
                GlowTile(key: Key('quick-type-${type.name}'), minHeight: 104,
                  onTap: () => setState(() => _kind = type),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                    Icon(type.icon, color: glowLink),
                    Text(c.text(type.label), style: style.titleMedium),
                    Text(c.text(type.hint), style: style.bodySmall),
                  ])),
            ]),
            QuickActionKind.color => _colors(rgb!),
            QuickActionKind.effect => ListenableBuilder(listenable: c, builder: (context, _) =>
              EffectList(favorites: c.effectFavorites, text: c.text, onFavorite: c.toggleEffectFavorite,
                selected: selected?['effect'] as int?,
                onSelected: (id) => _select({'kind': 'effect', 'effect': id}))),
            QuickActionKind.scene => _scenes(),
            QuickActionKind.sequence => _scenes(own: true),
          })),
          if (kind != null) ...[
            const SizedBox(height: 8),
            Row(spacing: 8, children: [
              if (rgb != null) SizedBox(width: 24, child: GlowStrip(colors: [rgb], dotted: false)),
              Expanded(child: Text(selected == null ? c.text('quickChooseOption')
                : c.text('quickPreview', {'name': c.shortcutLabel(selected)}), style: style.bodySmall)),
            ]),
            const SizedBox(height: 4),
            FilledButton(onPressed: selected == null ? null : () => Navigator.pop(context, selected),
              child: Text(c.text(widget.replacing ? 'changeShortcut' : 'quickAdd'))),
          ],
        ]),
      )),
    ));
  }

  Widget _colors(List<int> rgb) {
    final whites = [defaultShortcuts[0], _neutral, defaultShortcuts[1]];
    final favorites = c.models.loadPalette();
    final style = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      ColorDisc(color: _color(rgb), label: c.text('colorDiscLabel'), onChanged: (hsv) {
        final value = hsv.toColor().toARGB32();
        _select({'kind': 'color', 'rgb': [(value >> 16) & 255, (value >> 8) & 255, value & 255]});
      }),
      Text(c.text('whiteTones'), style: style.titleMedium),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < whites.length; i++)
          _chip(c.text(const ['whiteWarmTone', 'whiteNeutralTone', 'whiteCoolTone'][i]), whites[i], rgb),
      ]),
      Text(c.text('quickColorFavorites'), style: style.titleMedium),
      if (favorites.isEmpty) Text(c.text('quickNoColors'), style: style.bodySmall),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final hex in favorites) _chip(hex, {'kind': 'color', 'rgb': [
          for (final offset in [1, 3, 5]) int.parse(hex.substring(offset, offset + 2), radix: 16),
        ]}, rgb),
      ]),
    ]);
  }

  static Color _color(List<int> rgb) => Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);

  Widget _chip(String label, Fields item, List<int> current) {
    final rgb = item['rgb'] as List<int>;
    return ChoiceChip(avatar: CircleAvatar(backgroundColor: _color(rgb)),
      label: Text(label), selected: rgbHex(rgb) == rgbHex(current),
      showCheckmark: false, visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded, onSelected: (_) => _select(item));
  }

  Widget _scenes({bool own = false}) {
    final scenes = own ? c.models.loadSequences() : const <Fields>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(c.text(own ? 'myScenes' : 'quickIncluded'), style: Theme.of(context).textTheme.titleMedium),
      if (own) ...[
        if (scenes.isEmpty) Text(c.text('quickNoSequences')),
        for (final scene in scenes)
          ListTile(title: Text(scene['name'] as String), selected: _selected?['id'] == scene['id'],
            onTap: () => _select({'kind': 'sequence', 'id': scene['id']})),
      ] else
        for (final preset in homePresets.keys)
          ListTile(title: Text(c.text(preset)), selected: _selected?['preset'] == preset,
            onTap: () => _select({'kind': 'scene', 'preset': preset})),
    ]);
  }
}
