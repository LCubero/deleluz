import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/models.dart';
import '../model/timer.dart';
import 'glow_glass.dart';
import 'home_presets.dart';
import 'hue_wheel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.openScenes});
  final AppController controller;
  final VoidCallback openScenes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get c => widget.controller;
  bool _chooser = false;
  bool _quickOpen = false;

  Future<void> _scan() async {
    await c.startScan();
    if (mounted) setState(() => _chooser = c.scanning || c.devices.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final on = c.sentPower == true;
    final style = Theme.of(context).textTheme;
    final last = c.lastSentLabel;
    return ListView(padding: glowScreenPadding, children: [
      GlowHeader(title: c.text('title'), controller: c,
        leading: const Icon(Icons.light_mode_outlined, color: Color(0xffe3c2ff)), actions: [
        PopupMenuButton<String>(tooltip: c.text('settingsLanguage'),
          icon: const Icon(Icons.language), onSelected: c.setLanguage, itemBuilder: (_) => [
            PopupMenuItem(value: 'es', child: Text(c.text('spanish'))),
            PopupMenuItem(value: 'en', child: Text(c.text('english'))),
          ]),
        IconButton(tooltip: c.text('offTimer'), icon: const Icon(Icons.timer_outlined),
          onPressed: () => showDialog<void>(context: context,
            builder: (_) => _TimerDialog(controller: c))),
      ]),
      if (c.remaining case final seconds?)
        Text(c.text('offIn', {'time': formatRemaining(seconds)}), style: style.bodySmall),
      const SizedBox(height: 12),
      _device(context),
      const SizedBox(height: 16),
      Center(child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle,
          border: Border.all(color: glowLine),
          gradient: const RadialGradient(center: Alignment(0, -.4), colors: [Color(0xff382952), Color(0xff1b1636)]),
          boxShadow: on ? const [BoxShadow(color: Color(0x66ec4899), blurRadius: 32)] : null),
        child: IconButton(key: const Key('power'), tooltip: c.text('power'),
          isSelected: on, iconSize: 52, onPressed: c.ready ? () => c.setPower(!on) : null,
          style: IconButton.styleFrom(fixedSize: const Size.square(116)),
          icon: const Icon(Icons.power_settings_new)),
      )),
      const SizedBox(height: 10),
      Text(last == null ? c.text('noCommand') : c.text('lastSent', {'command': last}),
        textAlign: TextAlign.center, style: style.bodySmall),
      const SizedBox(height: 16),
      GlassCard(child: GlowDisclosure(
        title: c.text('quickScenes'),
        onExpansionChanged: (value) => setState(() => _quickOpen = value),
        children: [
          Align(alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: widget.openScenes, child: Text(c.text('allScenes')))),
          Align(alignment: AlignmentDirectional.centerStart, child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < c.shortcuts.length; i++)
              OutlinedButton(onPressed: () {
                if (c.ready) {
                  c.applyShortcut(c.shortcuts[i]);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.text('connectFirst'))));
                }
              }, onLongPress: () => _editShortcut(i), child: Text(c.shortcutLabel(c.shortcuts[i]))),
            if (c.shortcuts.length < maxShortcuts)
              IconButton.outlined(tooltip: c.text('addShortcut'),
                onPressed: () => _pickShortcut(), icon: const Icon(Icons.add)),
          ])),
        ],
      )),
      const SizedBox(height: 12),
      _slider(context, 'brightness', c.brightness, c.setBrightness),
      if (!_quickOpen) ...[
        const SizedBox(height: 12),
        _slider(context, 'speed', c.speed, c.setSpeed),
      ],
    ]);
  }

  Widget _slider(BuildContext context, String label, int value, ValueChanged<int> change) =>
    GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GlowValueLabel(label: c.text(label), value: c.text('percent', {'value': value})),
      Semantics(label: c.text(label), child: Slider(key: Key(label), value: value.toDouble(), max: 100,
        onChanged: c.ready ? (value) => change(value.round()) : null,
        onChangeEnd: (_) => c.saveSelection())),
    ]));

  Widget _device(BuildContext context) {
    final rgb = c.sentColor;
    final preview = c.link.ready && c.sentPower == true && rgb != null
        ? Color.fromARGB(255, rgb[0], rgb[1], rgb[2]) : null;
    final strip = c.link.ready ? c.link.strip : c.remembered;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(strip?.name ?? c.text('device'), style: Theme.of(context).textTheme.titleMedium),
      if (preview != null) ...[
        const SizedBox(height: 14),
        Semantics(label: c.text('stripPreview'), child: Container(height: 14,
          decoration: BoxDecoration(color: preview, borderRadius: BorderRadius.circular(99),
            boxShadow: [BoxShadow(color: preview.withAlpha(120), blurRadius: 16)]))),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (!c.link.ready && c.remembered != null)
          FilledButton(onPressed: c.busy ? null : c.reconnect, child: Text(c.text('reconnect'))),
        if (!_chooser)
          FilledButton(onPressed: c.busy ? null : _scan, child: Text(c.text(c.remembered == null ? 'connect' : 'switchStrip')))
        else
          OutlinedButton(onPressed: () {
            c.stopScan();
            setState(() => _chooser = false);
          }, child: Text(c.text('close'))),
        if (c.link.ready)
          OutlinedButton(onPressed: c.busy ? null : c.disconnect, child: Text(c.text('disconnect'))),
        if (c.remembered != null)
          TextButton(onPressed: c.busy ? null : c.forget, child: Text(c.text('forgetStrip'))),
      ]),
      if (_chooser) ...[
        const SizedBox(height: 8),
        if (c.scanning) Text(c.text('scanning')),
        if (!c.scanning && c.devices.isEmpty) Text(c.text('noStrips')),
        for (final device in c.devices)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.bluetooth),
            title: Text(device.name), enabled: !c.busy && !(c.link.ready && c.link.strip?.id == device.id),
            onTap: () {
              setState(() => _chooser = false);
              c.connect(device);
            }),
      ],
      if (c.message case final key?) ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(c.text(key), style: const TextStyle(color: Color(0xffffb4ba)))),
      ],
    ]));
  }

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
