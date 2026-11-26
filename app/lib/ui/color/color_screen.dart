import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/effects.dart';
import '../../protocol.dart' as wire;
import '../color_picker.dart';
import '../effect_list.dart';
import '../glow_glass.dart';
import '../notice.dart';
import 'app_auto_card.dart';

class ColorScreen extends StatefulWidget {
  const ColorScreen({super.key, required this.controller, this.active = true});

  final AppController controller;
  final bool active;

  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

class _ColorScreenState extends State<ColorScreen> {
  AppController get c => widget.controller;
  late List<int> _rgb;
  late int _effect;
  int? _manualEffect;
  bool _effects = false;
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  void _loadSelection() {
    final saved = c.models.loadState();
    _rgb = saved['rgb'] as List<int>;
    _manualEffect = null;
    _auto = c.effect == wire.autoEffect;
    _effect = _auto ? 1 : c.effect;
  }

  @override
  void didUpdateWidget(ColorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _effects = false;
    if (!identical(oldWidget.controller, c)) _loadSelection();
  }

  void _choose(List<int> rgb) {
    setState(() {
      _rgb = rgb;
      _auto = false;
      _manualEffect = null;
    });
    if (c.canSend) {
      unawaited(c.applyShortcut({'kind': 'color', 'rgb': rgb}));
    }
  }

  Future<void> _playEffect(int id) async {
    if (!c.canSend) return;
    final controller = c;
    if (id == wire.autoEffect) FocusScope.of(context).unfocus();
    final sent = await controller.setEffect(id);
    if (!sent || !mounted || c != controller) return;
    setState(() {
      _auto = id == wire.autoEffect;
      _manualEffect = _auto ? null : id;
      if (!_auto) _effect = id;
    });
  }

  Widget _effectCard() {
    final manual = _manualEffect;
    final name = manual != null && manual == c.effect && c.hasActiveEffect && !c.appAutoPlaying
        ? effectName(manual) : null;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_auto) ...[
        Text(c.text('allEffects'), key: const Key('strip-cycle-all'), textAlign: TextAlign.center),
        Semantics(liveRegion: true, child: Text(c.text('autoCycleAll'), textAlign: TextAlign.center)),
      ],
      Center(child: GlowChoice(choiceKey: const Key('effect-auto'),
        label: Text(c.text('stripCycle')), selected: _auto,
        onSelected: c.canSend ? (_) => _playEffect(wire.autoEffect) : null)),
      const SizedBox(height: 12),
      GlowStatusSlot(lines: MediaQuery.textScalerOf(context).scale(13) > 16 ? 4 : 2,
        live: true, text: name == null ? null :
          c.text('manualEffectPlaying', {'id': '$manual'.padLeft(2, '0'), 'name': name})),
      const SizedBox(height: 8),
      EffectList(favorites: c.effectFavorites, text: c.text,
        selected: _auto || c.appAutoPlaying ? null : _effect, onFavorite: c.toggleEffectFavorite,
        onSelected: c.canSend ? _playEffect : null),
      const SizedBox(height: 12),
      Notice(c.text('effectsNote')),
    ]));
  }

  Widget _slider(String key, int value, ValueChanged<int> change) {
    final shown = value.clamp(1, 100);
    return SliderZone(child: GlassCard(verticalInset: glassInset - 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GlowValueLabel(label: c.text(key), value: c.text('percent', {'value': shown})),
        Semantics(label: c.text(key), child: Slider(key: Key('color-$key'),
          min: 1, max: 100, divisions: 99, value: shown.toDouble(),
          semanticFormatterCallback: (value) => c.text('percent', {'value': value.round()}),
          onChanged: (value) => change(value.round()),
          onChangeEnd: (_) => c.saveSelection())),
        if (key == 'brightness')
          Notice(c.text(_effects ? 'dragNote' : 'brightnessDragHint'), compact: true),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    return SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        padding: glowScreenPadding, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GlowHeader(title: c.text('color'), controller: c),
          if (c.message == 'commandFailed')
            Notice(c.text('commandFailed'), kind: NoticeKind.error, live: true),
          const SizedBox(height: 12),
          GlowSegments<bool>(selected: _effects,
            onSelected: (effects) => setState(() => _effects = effects), segments: [
              ButtonSegment(value: false, label: Text(c.text('solid'),
                key: const Key('color-solid'), textAlign: TextAlign.center)),
              ButtonSegment(value: true, label: Text(c.text('builtIn'),
                key: const Key('color-effects'), textAlign: TextAlign.center)),
            ]),
          const SizedBox(height: 8),
          if (_effects) ...[
            _effectCard(),
            const SizedBox(height: 12),
            AppAutoCard(key: const Key('app-auto'), controller: c,
              onStart: () => setState(() {
                _auto = false;
                _manualEffect = null;
              })),
          ] else ...[
            SharedColorPicker(controller: c, rgb: _rgb, showDiscHint: false,
              onChanged: (rgb, _) => _choose(rgb)),
          ],
          const SizedBox(height: 8),
          _slider('brightness', c.brightness, c.setBrightness),
          if (_effects) ...[
            const SizedBox(height: 12),
            _slider('speed', c.speed, c.setSpeed),
          ],
        ],
      )),
    )));
  });
}
