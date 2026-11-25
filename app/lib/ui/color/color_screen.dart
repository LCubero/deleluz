import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';
import '../../protocol.dart' as wire;
import '../glow_glass.dart';
import '../color_disc.dart';
import '../effect_list.dart';
import 'app_auto_card.dart';
import 'favorites.dart';

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
    });
    if (c.canSend) {
      unawaited(c.applyShortcut({'kind': 'color', 'rgb': rgb}));
    }
  }

  Future<void> _playEffect(int id) async {
    if (!c.canSend) return;
    setState(() {
      _auto = id == wire.autoEffect;
      if (!_auto) _effect = id;
    });
    if (_auto) FocusScope.of(context).unfocus();
    await c.setEffect(id);
  }

  Widget _effectCard() {
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_auto) ...[
        Text(c.text('allEffects'), key: const Key('strip-cycle-all'), textAlign: TextAlign.center),
        Semantics(liveRegion: true, child: Text(c.text('autoCycleAll'), textAlign: TextAlign.center)),
      ],
      Center(child: FilterChip(key: const Key('effect-auto'),
        label: Text(c.text('stripCycle')), selected: _auto,
        onSelected: c.canSend ? (_) => _playEffect(wire.autoEffect) : null)),
      const SizedBox(height: 12),
      EffectList(favorites: c.effectFavorites, text: c.text,
        selected: _auto || c.appAutoPlaying ? null : _effect, onFavorite: c.toggleEffectFavorite,
        onSelected: c.canSend ? _playEffect : null),
      const SizedBox(height: 12),
      Text(c.text('effectsNote'), style: Theme.of(context).textTheme.bodySmall),
    ]));
  }

  Widget _whites() {
    final presets = [
      ('whiteWarmTone', defaultShortcuts[0]['rgb'] as List<int>),
      // #FFE4C4 rounds each channel at the midpoint of the two quick-scene whites.
      ('whiteNeutralTone', const [255, 228, 196]),
      ('whiteCoolTone', defaultShortcuts[1]['rgb'] as List<int>),
    ];
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(c.text('whiteTones'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
        for (final (label, rgb) in presets)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: Color.fromARGB(255, rgb[0], rgb[1], rgb[2])),
            label: Text(c.text(label)),
            selected: rgbHex(_rgb) == rgbHex(rgb),
            onSelected: (_) => _choose(rgb),
            showCheckmark: false,
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
      ]),
    ]));
  }

  Widget _slider(String key, int value, ValueChanged<int> change) {
    final shown = value.clamp(1, 100);
    return SliderZone(child: GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GlowValueLabel(label: c.text(key), value: c.text('percent', {'value': shown})),
        Semantics(label: c.text(key), child: Slider(key: Key('color-$key'),
          min: 1, max: 100, divisions: 99, value: shown.toDouble(),
          semanticFormatterCallback: (value) => c.text('percent', {'value': value.round()}),
          onChanged: (value) => change(value.round()),
          onChangeEnd: (_) => c.saveSelection())),
        if (key == 'brightness') Text(c.text('dragNote'), style: Theme.of(context).textTheme.bodySmall),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    final color = Color.fromARGB(255, _rgb[0], _rgb[1], _rgb[2]);
    final style = Theme.of(context).textTheme;
    return SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(padding: glowScreenPadding, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GlowHeader(title: c.text('color'), controller: c),
          if (c.message == 'commandFailed')
            Text(c.text('commandFailed'), textAlign: TextAlign.center, style: style.bodySmall),
          const SizedBox(height: 12),
          GlowSegments<bool>(selected: _effects,
            onSelected: (effects) => setState(() => _effects = effects), segments: [
              ButtonSegment(value: false, label: Text(c.text('solid'),
                key: const Key('color-solid'), textAlign: TextAlign.center)),
              ButtonSegment(value: true, label: Text(c.text('builtIn'),
                key: const Key('color-effects'), textAlign: TextAlign.center)),
            ]),
          const SizedBox(height: 16),
          if (_effects) ...[
            AppAutoCard(key: const Key('app-auto'), controller: c,
              onStart: () => setState(() => _auto = false)),
            const SizedBox(height: 12),
            _effectCard(),
          ] else ...[
            ColorDisc(color: color, label: c.text('colorDiscLabel'),
              onChanged: (hsv) {
                final selected = hsv.toColor().toARGB32();
                _choose([(selected >> 16) & 255, (selected >> 8) & 255, selected & 255]);
              }),
            Text(c.text('colorDiscHint'), textAlign: TextAlign.center, style: style.bodySmall),
            const SizedBox(height: 12),
            _whites(),
            const SizedBox(height: 12),
            ColorFavorites(controller: c, current: rgbHex(_rgb).toLowerCase(),
              onColor: _choose),
          ],
          const SizedBox(height: 16),
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
