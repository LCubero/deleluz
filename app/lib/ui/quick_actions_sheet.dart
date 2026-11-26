import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/models.dart';
import 'color_picker.dart';
import 'effect_list.dart';
import 'glow_glass.dart';
import 'glow_sheet.dart';
import 'notice.dart';
import 'home_presets.dart';
import 'scenes/scenes_screen.dart';
import 'scroll_hint.dart';

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
      GlowSheet.open<Fields>(context, enableDrag: false, constraints: const BoxConstraints(maxWidth: 480),
        builder: (context) => QuickActionsSheet._(controller, replacing));

  @override
  State<QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<QuickActionsSheet> {
  static const Fields _neutral = {'kind': 'color', 'rgb': SharedColorPicker.neutral, 'name': 'whiteNeutralTone'};
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
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    // Give the search/results the full viewport in short windows with the keyboard up.
    final compactEffect = kind == QuickActionKind.effect && inset > 0 &&
        MediaQuery.sizeOf(context).height - inset < 280;
    final confirm = GlowPrimaryButton(onPressed: selected == null ? null : () => Navigator.pop(context, selected),
      label: Text(c.text(widget.replacing ? 'changeShortcut' : 'quickAdd')));
    return PopScope<Fields>(canPop: kind == null, onPopInvokedWithResult: (popped, _) {
      if (!popped && kind != null) _back();
    }, child: Padding(padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!compactEffect) ...[
            Row(children: [
              if (kind != null) IconButton(tooltip: c.text('quickBack'),
                onPressed: _back, icon: const Icon(Icons.arrow_back)),
              Expanded(child: Semantics(header: true, child: Text(c.text(kind?.label ??
                (widget.replacing ? 'quickChangeTitle' : 'addShortcut')), style: style.titleLarge))),
              IconButton(tooltip: c.text('close'), icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
            ]),
            if (kind != QuickActionKind.sequence)
              Text(c.text(kind == null ? 'quickStepType' : 'quickStepOption'), style: style.bodySmall),
            const SizedBox(height: 8),
          ],
          Flexible(key: const ValueKey('quick-picker-body'), child: ScrollHint(key: ValueKey(kind), shrinkWrap: true,
            showHint: !compactEffect, child: SingleChildScrollView(child: switch (kind) {
            null => LayoutBuilder(builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              return GlowGrid(columns: scale >= 1.5 && constraints.maxWidth < 220 * scale ? 1 : 2, children: [
              for (final type in QuickActionKind.values)
                GlowTile(key: Key('quick-type-${type.name}'), minHeight: 104,
                  onTap: () => setState(() => _kind = type),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                    Icon(type.icon, color: glowLink),
                    Text(c.text(type.label), style: style.titleMedium),
                    Text(c.text(type.hint), style: style.bodySmall),
                  ])),
              ]);
            }),
            QuickActionKind.color => _colors(rgb!),
            QuickActionKind.effect => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListenableBuilder(listenable: c, builder: (context, _) =>
                EffectList(favorites: c.effectFavorites, text: c.text, onFavorite: c.toggleEffectFavorite,
                  selected: selected?['effect'] as int?,
                  onSelected: (id) => _select({'kind': 'effect', 'effect': id}))),
              if (compactEffect) confirm,
            ]),
            QuickActionKind.scene => _scenes(),
            QuickActionKind.sequence => _scenes(own: true),
          }))),
          if (kind != null && !compactEffect &&
              (kind != QuickActionKind.sequence || c.models.loadSequences().isNotEmpty)) ...[
            const SizedBox(height: 8),
            if (kind != QuickActionKind.sequence) ...[
              Row(spacing: 8, children: [
                if (rgb != null) SizedBox(width: 24, child: GlowStrip(colors: [rgb], dotted: false)),
                Expanded(child: Text(selected == null ? c.text('quickChooseOption')
                  : c.text('quickPreview', {'name': c.shortcutLabel(selected)}), style: style.bodySmall)),
              ]),
              const SizedBox(height: 4),
            ],
            confirm,
          ],
        ]),
      )),
    ));
  }

  Widget _colors(List<int> rgb) => SharedColorPicker(controller: c, rgb: rgb,
    onChanged: (rgb, name) => _select({'kind': 'color', 'rgb': rgb, 'name': ?name}));

  Widget _scenes({bool own = false}) {
    final scenes = own ? c.models.loadSequences() : const <Fields>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      if (own) ...[
        if (scenes.isEmpty) ...[
          Notice(c.text('quickNoSequences')),
          GlowPrimaryButton(key: const Key('quick-new-scene'), icon: const Icon(Icons.add),
            label: Text(c.text('newSequence')), onPressed: () async {
              await SceneEditor.create(context, c);
              if (mounted) setState(() {});
            }),
        ],
        if (scenes.isNotEmpty) Notice(c.text('mineNeedsAppNote')),
        for (final scene in scenes) _sceneCard(scene),
      ] else ...[
        Notice(c.text('foregroundPlaybackHint'), key: const Key('quick-scenes-needs-app')),
        for (final preset in homePresets.keys)
          GlowTile(key: Key('quick-scene-$preset'), minHeight: 48,
            selected: _selected?['preset'] == preset,
            onTap: () => _select({'kind': 'scene', 'preset': preset}),
            child: Text(c.text(preset))),
      ],
    ]);
  }

  Widget _sceneCard(Fields scene) {
    final steps = sceneSteps(scene);
    final duration = glowSeconds(steps.fold(0, (total, step) => total + (step['durationMs'] as int)), c.language);
    final style = Theme.of(context).textTheme;
    return GlowTile(key: ValueKey('quick-sequence-${scene['id']}'), minHeight: 92, inset: glassInset,
      selected: _selected?['id'] == scene['id'],
      onTap: () => _select({'kind': 'sequence', 'id': scene['id']}),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Text(scene['name'] as String, style: style.titleMedium),
        ExcludeSemantics(child: Row(spacing: 4, children: [
          for (final step in steps)
            Expanded(child: switch (step['rgb']) {
              final List<int> rgb => GlowStrip(colors: [rgb], dotted: false),
              _ => const Icon(Icons.auto_awesome, color: glowLink, size: 16),
            }),
        ])),
        Text(c.text(steps.length == 1 ? 'quickSceneOneStep' : 'quickSceneSteps',
          {'count': steps.length, 'duration': duration}), style: style.bodySmall),
      ]));
  }
}
