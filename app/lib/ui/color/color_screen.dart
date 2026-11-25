import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/effects.dart';
import '../../model/models.dart';
import '../../protocol.dart' as wire;
import '../glow_glass.dart';
import '../hue_wheel.dart';
import 'favorites.dart';

class ColorScreen extends StatefulWidget {
  const ColorScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

class _ColorScreenState extends State<ColorScreen> {
  AppController get c => widget.controller;
  late List<int> _rgb;
  late int _effect;
  late final TextEditingController _number;
  final _numberFocus = FocusNode();
  bool _effects = false;
  bool _auto = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _loadSelection();
    _number = TextEditingController(text: '$_effect');
    _numberFocus.addListener(_focusChanged);
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
    if (!identical(oldWidget.controller, c)) {
      _dirty = false;
      _loadSelection();
      _number.text = '$_effect';
    }
  }

  @override
  void dispose() {
    _numberFocus.removeListener(_focusChanged);
    _numberFocus.dispose();
    _number.dispose();
    super.dispose();
  }

  void _choose(List<int> rgb) {
    setState(() {
      _rgb = rgb;
      _auto = false;
      _number.text = '$_effect';
    });
    if (c.canSend) {
      unawaited(c.applyShortcut({'kind': 'color', 'rgb': rgb}));
    }
  }

  void _focusChanged() {
    if (!_numberFocus.hasFocus && _dirty) _commitEffect();
  }

  int? get _typed {
    final value = _number.text.trim();
    if (!RegExp(r'^\d+$').hasMatch(value)) return null;
    return (int.tryParse(value) ?? 210).clamp(1, 210);
  }

  void _commitEffect() {
    final id = _typed;
    _dirty = false;
    if (id != null && c.canSend) {
      unawaited(_playEffect(id));
    } else {
      setState(() => _number.text = _auto ? '' : '$_effect');
    }
  }

  Future<void> _playEffect(int id) async {
    if (!c.canSend) return;
    setState(() {
      _dirty = false;
      _auto = id == wire.autoEffect;
      if (!_auto) _effect = id;
      _number.text = _auto ? '' : '$_effect';
    });
    await c.setEffect(id);
  }

  String _lastSent() => switch (c.lastSentLabel) {
    final command? => c.text('lastSent', {'command': command}),
    null => c.text('noCommand'),
  };

  Widget _effectCard() {
    final preview = _dirty ? _typed : null;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(c.text('effect'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Row(children: [
        IconButton.outlined(key: const Key('effect-previous'),
          tooltip: c.text('previousEffect'), icon: const Icon(Icons.chevron_left),
          onPressed: c.canSend ? () => _playEffect(_effect == 1 ? 210 : _effect - 1) : null),
        const SizedBox(width: 8),
        Expanded(child: Semantics(label: c.text('effectRange'), child: TextField(
          key: const Key('effect-number'), controller: _number, focusNode: _numberFocus,
          enabled: c.canSend, keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done, textAlign: TextAlign.center,
          onChanged: (_) => setState(() => _dirty = true),
          onSubmitted: (_) { if (_dirty) _commitEffect(); },
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        ))),
        const SizedBox(width: 8),
        IconButton.outlined(key: const Key('effect-next'),
          tooltip: c.text('nextEffect'), icon: const Icon(Icons.chevron_right),
          onPressed: c.canSend ? () => _playEffect(_effect == 210 ? 1 : _effect + 1) : null),
      ]),
      const SizedBox(height: 12),
      if (_auto && preview == null) Text(c.text('allEffects'), textAlign: TextAlign.center),
      Semantics(liveRegion: true, child: Text(
        _auto && preview == null ? c.text('autoCycleAll') : effectName(preview ?? _effect)!,
        textAlign: TextAlign.center,
      )),
      const SizedBox(height: 12),
      Center(child: FilterChip(key: const Key('effect-auto'),
        label: Text(c.text('autoCycle')), selected: _auto,
        onSelected: c.canSend ? (_) => _playEffect(wire.autoEffect) : null)),
      const SizedBox(height: 12),
      Text(c.text('effectsNote'), style: Theme.of(context).textTheme.bodySmall),
    ]));
  }

  Widget _slider(String key, int value, ValueChanged<int> change) {
    final shown = value.clamp(1, 100);
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
        Text(c.text(key)), Text(c.text('percent', {'value': shown})),
      ]),
      Semantics(label: c.text(key), child: Slider(key: Key('color-$key'),
        min: 1, max: 100, divisions: 99, value: shown.toDouble(),
        semanticFormatterCallback: (value) => c.text('percent', {'value': value.round()}),
        onChanged: c.canSend ? (value) => change(value.round()) : null,
        onChangeEnd: c.canSend ? (_) => c.saveSelection() : null)),
      if (key == 'brightness') Text(c.text('dragNote'), style: Theme.of(context).textTheme.bodySmall),
    ]));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    final color = Color.fromARGB(255, _rgb[0], _rgb[1], _rgb[2]);
    final style = Theme.of(context).textTheme;
    return SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: ConnectionChip(controller: c)),
          const SizedBox(height: 12),
          Text(c.text('color'), textAlign: TextAlign.center, style: style.titleLarge),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_lastSent(),
            textAlign: TextAlign.center, style: style.bodySmall)),
          if (c.message == 'commandFailed')
            Text(c.text('commandFailed'), textAlign: TextAlign.center, style: style.bodySmall),
          const SizedBox(height: 12),
          Center(child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            ChoiceChip(key: const Key('color-solid'), label: Text(c.text('solid')),
              selected: !_effects, onSelected: (_) => setState(() => _effects = false)),
            ChoiceChip(key: const Key('color-effects'), label: Text(c.text('builtIn')),
              selected: _effects, onSelected: (_) => setState(() => _effects = true)),
          ])),
          const SizedBox(height: 16),
          if (_effects) _effectCard() else ...[
            HueWheel(hue: HSVColor.fromColor(color).hue, label: c.text('hue'),
              onChanged: (hue) {
                final selected = HSVColor.fromAHSV(1, hue, 1, 1).toColor().toARGB32();
                _choose([(selected >> 16) & 255, (selected >> 8) & 255, selected & 255]);
              }),
            const SizedBox(height: 16),
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
