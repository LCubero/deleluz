import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';
import '../model/models.dart';
import '../model/timer.dart';
import 'glow_glass.dart';
import 'glow_icon.dart';
import 'home_presets.dart';
import 'hue_wheel.dart';
import 'strip_selector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.openScenes});
  final AppController controller;
  final VoidCallback openScenes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get c => widget.controller;
  bool _quickOpen = false;

  Future<void> _chooseStrip() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => StripSelector(controller: c),
    ));
    await c.stopScan();
  }

  @override
  Widget build(BuildContext context) {
    final on = c.link.ready && c.sentPower == true;
    final height = MediaQuery.sizeOf(context).height;
    final diameter = height <= 720 ? (height * .09).clamp(48.0, 72.0).toDouble()
      : height <= 820 ? (height * .12).clamp(72.0, 100.0).toDouble() : 120.0;
    final style = Theme.of(context).textTheme;
    final last = c.lastSentLabel;
    return ListView(padding: glowScreenPadding, children: [
      GlowHeader(title: c.text('title'), controller: c, showStatus: false,
        leading: const GlowIcon(GlowGlyph.wave), actions: [
        Center(child: IconButton(tooltip: c.text('offTimer'),
          icon: const GlowIcon(GlowGlyph.timer, size: 22),
          style: IconButton.styleFrom(backgroundColor: glowGlass,
            fixedSize: const Size.square(44), padding: EdgeInsets.zero,
            side: const BorderSide(color: glowLine),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => showDialog<void>(context: context,
            builder: (_) => _TimerDialog(controller: c)))),
      ]),
      if (c.remaining case final seconds?)
        Text(c.text('offIn', {'time': formatRemaining(seconds)}), style: style.bodySmall),
      const SizedBox(height: 12),
      _device(context),
      const SizedBox(height: 12),
      Center(child: Opacity(opacity: c.ready ? 1 : .5, child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff1b1636),
          border: Border.all(color: const Color(0x33ffffff)),
          gradient: const RadialGradient(center: Alignment(0, -.3), stops: [0, .6],
            colors: [Color(0x1fffffff), Color(0x08ffffff)]),
          boxShadow: on ? const [BoxShadow(color: Color(0x2ea855f7), spreadRadius: 6),
            BoxShadow(color: Color(0x73ec4899), blurRadius: 50)] : null),
        child: IconButton(key: const Key('power'), tooltip: c.text('power'),
          isSelected: on, onPressed: c.ready ? () => c.setPower(!on) : null,
          style: IconButton.styleFrom(fixedSize: Size.square(diameter)),
          icon: GlowIcon(GlowGlyph.power, size: height <= 720 ? 32 : 52,
            color: on ? Colors.white : glowFaint)),
      ))),
      const SizedBox(height: 6),
      Text(on ? (c.language == 'en' ? 'On' : c.text('power')) : c.text('off'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(last == null ? c.text('noCommand') : c.text('lastSent', {'command': last}),
        textAlign: TextAlign.center, style: style.bodySmall),
      const SizedBox(height: 12),
      _quick(context),
      if (!_quickOpen) ...[
        const SizedBox(height: 12),
        _slider('speed', c.speed, c.hasActiveEffect ? c.setSpeed : null,
          hint: c.hasActiveEffect ? null : c.text('speedEffectsHint')),
      ],
      const SizedBox(height: 12),
      _slider('brightness', c.brightness, c.setBrightness),
    ]);
  }

  Widget _quick(BuildContext context) {
    final count = c.shortcuts.length + (c.shortcuts.length < maxShortcuts ? 1 : 0);
    final columns = count <= 3 ? count : count == 4 ? 2 : 3;
    return Column(children: [
      Row(spacing: 8, children: [
        Expanded(child: Semantics(button: true, expanded: _quickOpen, child: InkWell(
          onTap: () => setState(() => _quickOpen = !_quickOpen),
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: Row(spacing: 8, children: [
            Flexible(child: Text(c.text('quickScenes').toUpperCase(), style: const TextStyle(
              color: glowMuted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.04))),
            RotatedBox(quarterTurns: _quickOpen ? 1 : 0,
              child: const GlowIcon(GlowGlyph.chevron, color: glowMuted, size: 18)),
          ])),
        ))),
        Flexible(child: Align(alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: widget.openScenes,
            style: TextButton.styleFrom(foregroundColor: glowLink, padding: EdgeInsets.zero,
              textStyle: const TextStyle(fontSize: 13)),
            child: Text(c.text('allScenes'), textAlign: TextAlign.end)))),
      ]),
      if (_quickOpen) ...[
        const SizedBox(height: 10),
        GlowGrid(columns: columns, children: [
          for (var i = 0; i < c.shortcuts.length; i++) _shortcut(context, i),
          if (c.shortcuts.length < maxShortcuts)
            GlowTile(onTap: () => _pickShortcut(), minHeight: 60,
              child: Tooltip(message: c.text('addShortcut'), child: const Center(child: Icon(Icons.add)))),
        ]),
      ],
    ]);
  }

  Widget _shortcut(BuildContext context, int index) {
    final item = c.shortcuts[index];
    final colors = switch (item['kind']) {
      'scene' => presetPreviewColors(item['preset'] as String),
      'sequence' => c.models.loadSequences().where((scene) => scene['id'] == item['id'])
        .firstOrNull?['colors'] as List<List<int>>?,
      _ => [item['rgb'] as List<int>],
    };
    return GlowTile(minHeight: 60, onTap: () {
      if (c.ready) {
        c.applyShortcut(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.text('connectFirst'))));
      }
    }, onLongPress: () => _editShortcut(index), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        GlowStrip(colors: colors ?? const [], height: 8, dotted: false),
        Text(c.shortcutLabel(item), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    ));
  }

  Widget _slider(String label, int value, ValueChanged<int>? change, {String? hint}) =>
    GlassCard(verticalInset: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GlowValueLabel(label: c.text(label), value: c.text('percent', {'value': value}),
        icon: label == 'brightness' ? const GlowIcon(GlowGlyph.sun, size: 20) : null),
      const SizedBox(height: 10),
      Semantics(label: c.text(label), child: Slider(key: Key(label), value: value.toDouble(), max: 100,
        onChanged: change == null ? null : (value) => change(value.round()),
        onChangeEnd: change == null ? null : (_) => c.saveSelection())),
      if (hint != null) Text(hint, style: const TextStyle(color: glowMuted, fontSize: 13)),
    ]));

  Widget _device(BuildContext context) {
    final connected = c.link.ready;
    // No visual command yet: this gradient is decorative, not device telemetry.
    final unknown = connected && c.sentPower == null;
    final rgb = connected && c.sentPower == true ? c.sentColor : null;
    final previewColors = switch (rgb) {
      final color? => [color],
      _ when c.hasActiveEffect => glowEffectColors,
      _ when unknown => const [[100, 75, 125], [141, 91, 126], [68, 117, 135]],
      _ => const <List<int>>[],
    };
    final glow = rgb == null ? null : Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
    final strip = c.remembered;
    final theme = Theme.of(context).textTheme;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Row(spacing: 12, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(strip?.label ?? 'LEDDMX', style: theme.titleMedium,
            maxLines: 1, overflow: TextOverflow.ellipsis),
          // Second line: the Bluetooth name under an alias; otherwise a short description, never the name twice.
          Text(strip != null && strip.label != strip.name ? strip.name
              : c.text(c.link.status == LinkStatus.lost ? 'keepsColor' : 'controller'),
            style: theme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        // Flexible keeps large text from overflowing; Align without widthFactor pins the chip right.
        Flexible(child: Align(alignment: AlignmentDirectional.topEnd, heightFactor: 1,
          child: ConnectionChip(controller: c))),
      ]),
      Semantics(container: true, image: true,
        label: c.text(unknown ? 'stripPreviewUnknown' : 'stripPreview'),
        child: GlowStrip(colors: previewColors, height: 14, glow: glow)),
      Row(spacing: 8, children: [
        Expanded(child: _connectButton(c.text(connected ? 'disconnect' : strip != null ? 'reconnect' : 'connect'),
          c.busy ? null : connected ? c.disconnect : strip != null ? c.reconnect : _chooseStrip)),
        TextButton(onPressed: c.busy ? null : _chooseStrip,
          style: TextButton.styleFrom(foregroundColor: glowLink,
            padding: const EdgeInsets.symmetric(horizontal: 8)), child: Text(c.text('changeStrip'))),
      ]),
      if (c.message case final key?) ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(c.text(key), style: const TextStyle(color: Color(0xffffb4ba)))),
      ],
    ]));
  }

  Widget _connectButton(String label, VoidCallback? onPressed) => DecoratedBox(
    decoration: BoxDecoration(gradient: onPressed == null ? null : glowStrongGradient,
      borderRadius: BorderRadius.circular(14), boxShadow: onPressed == null ? null : const [
        BoxShadow(color: Color(0x59ec4899), blurRadius: 24, offset: Offset(0, 8)),
      ]),
    child: FilledButton.icon(onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: Colors.transparent),
      icon: const GlowIcon(GlowGlyph.bluetooth, size: 20), label: Text(label)),
  );

  Future<void> _editShortcut(int index) async {
    final action = await showDialog<String>(context: context, builder: (context) => SimpleDialog(
      title: Text(c.shortcutLabel(c.shortcuts[index])),
      children: [
        for (final key in ['changeShortcut', if (index > 0) 'moveLeft',
          if (index + 1 < c.shortcuts.length) 'moveRight', 'removeShortcut'])
          SimpleDialogOption(onPressed: () => Navigator.pop(context, key), child: Text(c.text(key))),
      ],
    ));
    if (!mounted) return;
    switch (action) {
      case 'changeShortcut': await _pickShortcut(index);
      case 'moveLeft': c.updateShortcuts(moveItem(c.shortcuts, index, index - 1));
      case 'moveRight': c.updateShortcuts(moveItem(c.shortcuts, index, index + 1));
      case 'removeShortcut': c.updateShortcuts(removeShortcut(c.shortcuts, index));
    }
  }

  Future<void> _pickShortcut([int? index]) async {
    double hue = 0;
    final item = await showDialog<Fields>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => AlertDialog(
        title: Text(c.text(index == null ? 'addShortcut' : 'changeShortcut')),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ExpansionTile(title: Text(c.text('scenes')), children: [
            for (final preset in homePresets.keys)
              ListTile(title: Text(c.text(preset)), onTap: () => Navigator.pop(context, <String, Object?>{'kind': 'scene', 'preset': preset})),
            for (final scene in c.models.loadSequences())
              ListTile(title: Text(scene['name'] as String), onTap: () => Navigator.pop(context, <String, Object?>{'kind': 'sequence', 'id': scene['id']})),
          ]),
          ExpansionTile(title: Text(c.text('colors')), children: [
            for (final item in [...defaultShortcuts, {'kind': 'color', 'name': 'night', 'rgb': [32, 4, 0]},
              for (final hex in c.models.loadPalette()) {'kind': 'color', 'rgb': [
                for (final offset in [1, 3, 5]) int.parse(hex.substring(offset, offset + 2), radix: 16),
              ]}])
              ListTile(leading: _swatch(item['rgb'] as List<int>), title: Text(c.shortcutLabel(item)),
                onTap: () => Navigator.pop(context, item)),
            const SizedBox(height: 12),
            HueWheel(hue: hue, label: c.text('hue'),
              onChanged: (value) => setModalState(() => hue = value)),
            TextButton(onPressed: () {
              final color = HSVColor.fromAHSV(1, hue, 1, 1).toColor().toARGB32();
              Navigator.pop(context, <String, Object?>{'kind': 'color',
                'rgb': [(color >> 16) & 255, (color >> 8) & 255, color & 255]});
            }, child: Text(c.text('addThisColor'))),
          ]),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(c.text('cancel')))],
      ),
    ));
    if (!mounted || item == null) return;
    c.updateShortcuts(index == null ? addShortcut(c.shortcuts, item) : replaceShortcut(c.shortcuts, index, item));
  }

  Widget _swatch(List<int> rgb) => CircleAvatar(radius: 12, backgroundColor: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]));
}

class _TimerDialog extends StatefulWidget {
  const _TimerDialog({required this.controller});
  final AppController controller;

  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  int? _preset = 15;
  String _minutes = '', _seconds = '';
  bool _fade = false, _invalid = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AlertDialog(scrollable: true, title: Text(c.text('offTimer')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.text('timerNote')),
        if (!c.ready) Text(c.text('connectFirst')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final (minutes, key) in [(15, 'minutes15'), (30, 'minutes30'),
            (60, 'hour1'), (120, 'hours2'), (null, 'custom')])
            ChoiceChip(label: Text(c.text(key)), selected: _preset == minutes,
              onSelected: (_) => setState(() { _preset = minutes; _invalid = false; })),
        ]),
        if (_preset == null) ...[
          TextField(decoration: InputDecoration(labelText: c.text('minutes')),
            keyboardType: TextInputType.number, onChanged: (value) => _minutes = value),
          TextField(decoration: InputDecoration(labelText: c.text('seconds')),
            keyboardType: TextInputType.number, onChanged: (value) => _seconds = value),
        ],
        if (_invalid) Text(c.text('invalidTimer')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(c.text('fade')),
          value: _fade, onChanged: (value) => setState(() => _fade = value ?? false)),
      ]),
      actions: [
        if (c.remaining != null)
          TextButton(onPressed: () { c.cancelTimer(restoreBrightness: true); Navigator.pop(context); }, child: Text(c.text('cancelTimer'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(c.text('close'))),
        FilledButton(onPressed: !c.ready ? null : () {
          final seconds = _preset == null ? parseTimerDuration(_minutes, _seconds) : _preset! * 60;
          if (seconds == null) {
            setState(() => _invalid = true);
          } else {
            c.startTimer(seconds, fade: _fade);
            Navigator.pop(context);
          }
        }, child: Text(c.text(c.remaining == null ? 'startTimer' : 'restartTimer'))),
      ],
    );
  }
}
