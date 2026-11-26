import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/effects.dart';
import '../../model/models.dart';
import '../../protocol.dart' as wire;
import '../glow_glass.dart';
import '../glow_sheet.dart';
import '../notice.dart';
import '../glow_icon.dart';
import '../home_presets.dart';
import '../color_picker.dart';
import '../effect_list.dart';
import '../scroll_hint.dart';
import 'scene_transport.dart';

part 'scene_editor.dart';

Color _rgb(List<int> rgb) => Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
const _voiceColors = [
  [[236, 72, 153], [168, 85, 247]], [[34, 211, 238], [59, 130, 246]],
  [[34, 197, 94], [250, 204, 21]], [[249, 115, 22], [239, 68, 68]],
];

class ScenesScreen extends StatefulWidget {
  const ScenesScreen({super.key, required this.controller, this.active = true});
  final bool active;
  final AppController controller;

  @override
  State<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  AppController get c => widget.controller;
  late SceneTransport _transport = SceneTransport(c);
  String _panel = 'mine';

  @override
  void didUpdateWidget(ScenesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _panel = 'mine';
    if (oldWidget.controller != c) {
      _transport.dispose();
      _transport = SceneTransport(c);
    }
  }

  @override
  void dispose() {
    _transport.dispose();
    super.dispose();
  }

  void _connectFirst() => showGlowNotice(context, c.text('connectFirst'), kind: NoticeKind.warning);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _transport,
    builder: (context, _) {
      return SafeArea(bottom: false, child: ListView(
        padding: glowScreenPadding,
        children: [
          GlowHeader(title: c.text('scenes'), controller: c),
          if (_transport.failed)
            Notice(c.text('commandFailed'), kind: NoticeKind.error, live: true),
          const SizedBox(height: 12),
          GlowSegments<String>(selected: _panel,
            onSelected: (panel) => setState(() => _panel = panel), segments: [
              for (final (id, label) in const [('included', 'includedScenes'),
                ('mine', 'myScenes'), ('music', 'music')])
                ButtonSegment(value: id, label: Text(c.text(label),
                  key: Key('scenes-$id'), textAlign: TextAlign.center)),
            ]),
          const SizedBox(height: 12),
          ...switch (_panel) {
            'mine' => _mine(),
            'music' => [_music()],
            _ => [Notice(c.text('needsAppLegend')), const SizedBox(height: 12),
              GlowGrid(columns: 2, children: _included())],
          },
        ],
      ));
    },
  );

  List<Widget> _included() => [
    for (final entry in homePresets.entries)
      _card('included-${entry.key}', c.text(entry.key), presetPreviewColors(entry.key),
        () => _applyPreset(entry.key),
        () => _preview(c.text(entry.key), entry.value.colors, entry.value.interval, (interval) {
          _transport.useShared({'kind': 'scene', 'preset': entry.key, 'interval': interval});
        }, preset: entry.key), needsApp: true),
    for (final id in const [wire.autoEffect, 1, 2])
      _card('included-effect-$id', _effectName(id), glowEffectColors,
        () => _applyEffect(id),
        () => _preview(_effectName(id), glowEffectColors, 650, (_) => _applyEffect(id), effect: id),
        needsApp: false),
  ];

  String _effectName(int id) => id == wire.autoEffect ? c.text('autoCycle') : effectNames[id - 1];

  void _applyPreset(String preset) {
    if (!_transport.ready) return _connectFirst();
    _transport.useShared({'kind': 'scene', 'preset': preset});
  }

  void _applyEffect(int effect) {
    if (!_transport.ready) return _connectFirst();
    unawaited(_transport.playEffect(effect));
  }

  Future<void> _preview(String title, List<List<int>> colors, int interval, ValueChanged<int> apply,
      {String? preset, int? effect}) async {
    final transport = _transport;
    final confirmed = await showDialog<int>(context: context, builder: (_) => _IncludedPreview(
      title: title, colors: colors, interval: interval, transport: transport,
      preset: preset, effect: effect,
    ));
    if (!mounted || transport != _transport) return;
    transport.stopPreview(restore: confirmed == null);
    if (confirmed != null) apply(confirmed);
  }

  List<Widget> _mine() {
    final items = c.models.loadSequences();
    return [
      Align(alignment: Alignment.center, child: FilledButton.icon(key: const Key('scene-new'),
        icon: const Icon(Icons.add), label: Text(c.text('newSequence')),
        onPressed: items.length < maxSequences ? () => _edit(null) : null)),
      const SizedBox(height: 12),
      if (items.isEmpty) Notice(c.text('sequencesEmpty')) else Notice(c.text('mineNeedsAppNote')),
      if (items.length >= maxSequences)
        Notice(c.text('scenesLimit', {'max': maxSequences}), kind: NoticeKind.warning),
      GlowGrid(columns: 2, children: [
        for (final item in items)
          _card('scene-play-${item['id']}', item['name'] as String, item['colors'] as List<List<int>>,
            () {
              if (!_transport.ready) return _connectFirst();
              _transport.useShared({'kind': 'sequence', 'id': item['id']});
            }, () => _edit(item), userName: true, needsApp: true,
            trailing: IconButton(key: Key('scene-edit-${item['id']}'),
              tooltip: c.text('renameSequence'), icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(item))),
      ]),
    ];
  }

  Future<void> _edit(Fields? item) async {
    final transport = _transport;
    await showDialog<void>(context: context, builder: (_) => SceneEditor._(transport: transport, item: item));
    if (!mounted || transport != _transport) return;
    transport.stopPreview();
    setState(() {});
  }

  Widget _card(String key, String title, List<List<int>> colors, VoidCallback tap,
      VoidCallback hold, {Widget? trailing, bool userName = false, required bool needsApp}) => GlowTile(key: Key(key),
    onTap: tap, onLongPress: hold, inset: glassInset + 1, minHeight: 92,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      ConstrainedBox(constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(15) * 2.6),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.3),
          key: userName ? const Key('scene-display-name') : null,
          maxLines: userName ? 2 : null, overflow: userName ? TextOverflow.ellipsis : null)),
      GlowStrip(colors: colors, dotted: false),
      Row(children: [
        Expanded(child: _RuntimeTag(text: c.text(needsApp ? 'needsApp' : 'onStrip'), needsApp: needsApp)),
        ?trailing,
      ]),
    ]),
  );

  Widget _music() => SliderZone(child: GlassCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(c.text('musicTitle'), style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Notice(c.text('musicHint')),
    const SizedBox(height: 12),
    GlowGrid(columns: 2, children: [
      for (var mode = 1; mode <= 4; mode++)
        GlowTile(key: Key('scene-voice-$mode'), onTap: () {
          if (!_transport.ready) return _connectFirst();
          unawaited(_transport.playVoice(mode));
        }, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Text('${c.text('voiceModeWord')} $mode', style: Theme.of(context).textTheme.titleMedium),
          GlowStrip(colors: _voiceColors[mode - 1], dotted: false),
        ])),
    ]),
    const SizedBox(height: 18),
    _SceneSlider(controller: c, id: 'scene-sensitivity', label: 'micSensitivity',
      value: _transport.sensitivity, onChanged: _transport.changeSensitivity,
      onChangeEnd: (_) => c.saveSelection()),
    ]),
  ));
}

/// Icon plus text, so the runtime difference never relies on color alone.
class _RuntimeTag extends StatelessWidget {
  const _RuntimeTag({required this.text, required this.needsApp});
  final String text;
  final bool needsApp;

  @override
  Widget build(BuildContext context) => Row(spacing: 6, children: [
    Icon(needsApp ? Icons.phone_android : Icons.memory, size: 16, color: glowMuted),
    Flexible(child: Text(text, key: const Key('scene-runtime-tag'),
      style: Theme.of(context).textTheme.bodySmall)),
  ]);
}

class _LastSent extends StatelessWidget {
  const _LastSent({required this.transport});
  final SceneTransport transport;

  @override
  Widget build(BuildContext context) {
    final c = transport.controller;
    final command = c.lastSentLabel;
    return Text(command == null ? c.text('noCommand') : c.text('lastSent', {'command': command}),
      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _SceneSlider extends StatelessWidget {
  const _SceneSlider({required this.controller, required this.id, required this.label,
    required this.value, required this.onChanged, this.onChangeEnd, this.min = 0, this.icon});

  final AppController controller;
  final String id, label;
  final int value, min;
  final ValueChanged<int> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    String percent(int n) => controller.text('percent', {'value': n});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowValueLabel(label: controller.text(label), value: percent(value), icon: icon),
      Semantics(label: controller.text(label), child: Slider(key: Key(id),
        value: value.toDouble(), min: min.toDouble(), max: 100,
        label: percent(value), semanticFormatterCallback: (value) => percent(value.round()),
        onChanged: (value) => onChanged(value.round()), onChangeEnd: onChangeEnd)),
    ]);
  }
}

class _IncludedPreview extends StatefulWidget {
  const _IncludedPreview({required this.title, required this.colors, required this.interval,
    required this.transport, this.preset, this.effect});

  final String title;
  final List<List<int>> colors;
  final int interval;
  final SceneTransport transport;
  final String? preset;
  final int? effect;

  @override
  State<_IncludedPreview> createState() => _IncludedPreviewState();
}

class _IncludedPreviewState extends State<_IncludedPreview> with WidgetsBindingObserver {
  Timer? _animation;
  var _index = 0;
  late int _interval = widget.interval;
  AppController get c => widget.transport.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _animate();

  void _animate() {
    _animation?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (MediaQuery.disableAnimationsOf(context) ||
        (state != null && state != AppLifecycleState.resumed)) {
      return;
    }
    _animation = Timer.periodic(Duration(milliseconds: _interval.clamp(350, 2000)), (_) {
      setState(() => _index = (_index + 1) % widget.colors.length);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.transport,
    builder: (context, _) => AlertDialog(
      title: Text(widget.title), scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.text('screenPreview')),
          const SizedBox(height: 10),
          Container(height: 16, decoration: BoxDecoration(color: _rgb(widget.colors[_index]),
            borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 10),
          if (widget.preset != null) ...[
            SliderZone(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlowValueLabel(label: c.text('stepInterval'), value: '$_interval ms'),
              Semantics(label: c.text('stepInterval'), child: Slider(
                min: 150, max: 2000, divisions: 185, value: _interval.toDouble(),
                semanticFormatterCallback: (value) => '${value.round()} ms',
                onChanged: (value) {
                  setState(() => _interval = value.round());
                  _animate();
                },
              )),
            ])),
            Notice(c.text('foregroundPlaybackHint')),
          ],
          const SizedBox(height: 8),
          _LastSent(transport: widget.transport),
          if (widget.transport.failed) Notice(c.text('commandFailed'), kind: NoticeKind.error, live: true),
        ],
      ),
      actions: [
        TextButton(key: const Key('scene-close'), onPressed: () => Navigator.pop(context), child: Text(c.text('close'))),
        TextButton(onPressed: widget.transport.ready ? () {
          if (widget.effect case final id?) {
            unawaited(widget.transport.playEffect(id, preview: true));
          } else {
            unawaited(widget.transport.playColors(widget.colors, _interval, 50));
          }
        } : null, child: Text(c.text('tryScene'))),
        FilledButton(onPressed: widget.transport.ready ? () => Navigator.pop(context, _interval) : null,
          child: Text(c.text('apply'))),
      ],
    ));
}
