import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';
import '../model/models.dart';
import '../model/timer.dart';
import 'bluetooth_card.dart';
import 'glow_glass.dart';
import 'glow_icon.dart';
import 'quick_actions_sheet.dart';
import 'strip_selector.dart';
import 'timer_sheet.dart';

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
  String? _previewId;
  String? _previewAnchor;
  double _swipeStart = 0;

  Future<void> _chooseStrip() => StripSelector.open(context, c);

  @override
  Widget build(BuildContext context) {
    final off = c.bluetoothOff;
    final on = !off && c.link.ready && c.sentPower == true;
    Widget dim(Widget child) => Opacity(opacity: off ? .55 : 1, child: child);
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
          onPressed: off ? null : () => TimerSheet.open(context, c))),
      ]),
      if (c.remaining case final seconds?)
        Text(c.text('offIn', {'time': formatRemaining(seconds)}), style: style.bodySmall),
      const SizedBox(height: 12),
      if (off) ...[
        BluetoothCard(controller: c),
        const SizedBox(height: 12),
      ],
      dim(_device(context)),
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
      Text(c.text(off ? 'stripControlsUnavailable' : on ? 'on' : 'off'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(last == null ? c.text('noCommand') : c.text('lastSent', {'command': last}),
        textAlign: TextAlign.center, style: style.bodySmall),
      const SizedBox(height: 12),
      dim(ExcludeFocus(excluding: off, child: AbsorbPointer(absorbing: off, child: _quick(context)))),
      if (!_quickOpen) ...[
        const SizedBox(height: 12),
        dim(_slider('speed', c.speed, !off && c.hasActiveEffect ? c.setSpeed : null,
          hint: c.hasActiveEffect ? null : c.text('speedEffectsHint'))),
      ],
      const SizedBox(height: 12),
      dim(_slider('brightness', c.brightness, off ? null : c.setBrightness)),
    ]);
  }

  Widget _quick(BuildContext context) {
    final count = c.shortcuts.length + (c.shortcuts.length < maxShortcuts ? 1 : 0);
    return Column(children: [
      Semantics(button: true, expanded: _quickOpen, child: InkWell(
        onTap: () => setState(() => _quickOpen = !_quickOpen),
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: Row(spacing: 8, children: [
          Expanded(child: Text(c.text('quickActions'), style: const TextStyle(
            color: glowMuted, fontSize: 16, fontWeight: FontWeight.w600))),
          RotatedBox(quarterTurns: _quickOpen ? 1 : 0,
            child: const GlowIcon(GlowGlyph.chevron, color: glowMuted, size: 18)),
        ])),
      )),
      if (_quickOpen) ...[
        const SizedBox(height: 10),
        GlowGrid(columns: count == 1 ? 1 : 2, children: [
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
    final kind = QuickActionKind.values.byName(item['kind'] as String);
    final rgb = item['rgb'] as List<int>?;
    final tile = GlowTile(minHeight: 60, onTap: () {
      if (c.ready) {
        c.applyShortcut(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.text('connectFirst'))));
      }
    }, onLongPress: () => _editShortcut(index), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Row(spacing: 6, children: [
          if (rgb != null) SizedBox(width: 14,
            child: GlowStrip(colors: [rgb], height: 8, dotted: false))
          else Icon(kind.icon, size: 14, color: glowLink),
          Flexible(child: Text(c.text(kind.label), style: Theme.of(context).textTheme.bodySmall)),
        ]),
        Text(c.shortcutLabel(item), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    ));
    return item['kind'] == 'color' ? SliderZone(child: tile) : tile;
  }

  Widget _slider(String label, int value, ValueChanged<int>? change, {String? hint}) =>
    SliderZone(child: GlassCard(verticalInset: 14,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlowValueLabel(label: c.text(label), value: c.text('percent', {'value': value}),
          icon: label == 'brightness' ? const GlowIcon(GlowGlyph.sun, size: 20) : null),
        const SizedBox(height: 10),
        Semantics(label: c.text(label), child: Slider(key: Key(label), value: value.toDouble(), max: 100,
          onChanged: change == null ? null : (value) => change(value.round()),
          onChangeEnd: change == null ? null : (_) => c.saveSelection())),
        if (hint != null) Text(hint, style: const TextStyle(color: glowMuted, fontSize: 13)),
      ]),
    ));

  Widget _device(BuildContext context) {
    final saved = c.rememberedStrips;
    final remembered = c.remembered;
    if (_previewAnchor != remembered?.id) {
      _previewAnchor = remembered?.id;
      _previewId = null;
    }
    final previewIndex = saved.indexWhere((strip) => strip.id == _previewId);
    final index = previewIndex < 0 ? 0 : previewIndex;
    final strip = saved.isEmpty ? null : saved[index];
    final showingRemembered = strip?.id == remembered?.id;
    final off = c.bluetoothOff;
    final connected = !off && c.link.ready && c.link.strip?.id == strip?.id;
    final pending = c.connectingId != null;
    final status = c.connectingId == strip?.id && pending ? LinkStatus.connecting
        : connected ? LinkStatus.connected
        : showingRemembered && !c.link.ready ? c.link.status : LinkStatus.idle;
    // Color unknown (nothing sent yet, or on with a mode that has no color such as music):
    // this gradient is decorative, not device telemetry. Off stays dark.
    final rgb = connected && c.sentPower == true ? c.sentColor : null;
    final unknown = connected && (c.sentPower == null
        || (c.sentPower == true && rgb == null && !c.hasActiveEffect));
    final previewColors = switch (rgb) {
      final color? => [color],
      _ when connected && c.hasActiveEffect => glowEffectColors,
      _ when unknown => const [[100, 75, 125], [141, 91, 126], [68, 117, 135]],
      _ => const <List<int>>[],
    };
    final glow = rgb == null ? null : Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
    final theme = Theme.of(context).textTheme;
    final name = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(strip?.label ?? 'LEDDMX', style: theme.titleMedium,
        maxLines: 1, overflow: TextOverflow.ellipsis),
      // Show the Bluetooth name under an alias, never the name twice.
      Text(strip != null && strip.label != strip.name ? strip.name
          : c.text(status == LinkStatus.lost ? 'keepsColor' : 'controller'),
        style: theme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      if (saved.length > 1) Padding(padding: const EdgeInsets.only(top: 4),
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Row(spacing: 4, children: [
            for (var i = 0; i < saved.length; i++) DecoratedBox(
              key: ValueKey('strip-dot-$i'), decoration: BoxDecoration(shape: BoxShape.circle,
                color: i == index ? glowViolet : glowFaint),
              child: const SizedBox.square(dimension: 5)),
          ]))),
    ]);
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Row(spacing: 12, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: off || saved.length < 2 ? name : SliderZone(child: name,
          onHorizontalDragStart: (details) => _swipeStart = details.globalPosition.dx,
          onHorizontalDragEnd: (details) {
            final dx = details.globalPosition.dx - _swipeStart;
            if (dx.abs() < 24) return;
            setState(() {
              _previewId = saved[(index + (dx < 0 ? 1 : -1)) % saved.length].id;
            });
          })),
        // Flexible keeps large text from overflowing; Align without widthFactor pins the chip right.
        Flexible(child: Align(alignment: AlignmentDirectional.topEnd, heightFactor: 1,
          child: ConnectionChip(controller: c, status: status))),
      ]),
      Semantics(container: true, image: true,
        label: c.text(unknown ? 'stripPreviewUnknown' : 'stripPreview'),
        child: GlowStrip(colors: previewColors, height: 14, glow: glow)),
      Row(spacing: 8, children: [
        Expanded(child: _connectButton(c.text(pending ? 'cancel' : connected ? 'disconnect'
            : strip != null && previewIndex < 0 ? 'reconnect' : 'connect'), neutral: pending,
          off ? null : pending ? c.cancelConnection : c.busy ? null : connected ? c.disconnect
            : strip == null ? _chooseStrip : showingRemembered ? c.reconnect : () => c.connect(strip))),
        TextButton(onPressed: off || c.busy ? null : _chooseStrip,
          style: TextButton.styleFrom(foregroundColor: glowLink,
            padding: const EdgeInsets.symmetric(horizontal: 8)), child: Text(c.text('changeStrip'))),
      ]),
      if (c.message case final key? when key != 'bluetoothOff' && key != 'bluetoothEnableFailed') ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(c.text(key), style: const TextStyle(color: Color(0xffffb4ba)))),
      ],
    ]));
  }

  // neutral: grey glass for Cancelar, so it never looks like Conectar (L54).
  Widget _connectButton(String label, VoidCallback? onPressed, {bool neutral = false}) => DecoratedBox(
    decoration: BoxDecoration(gradient: onPressed == null || neutral ? null : glowStrongGradient,
      color: neutral ? glowGlassSelected : null,
      border: neutral ? Border.all(color: glowLine) : null,
      borderRadius: BorderRadius.circular(14), boxShadow: onPressed == null || neutral ? null : const [
        BoxShadow(color: Color(0x59ec4899), blurRadius: 24, offset: Offset(0, 8)),
      ]),
    child: FilledButton.icon(onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: Colors.transparent),
      icon: neutral ? const Icon(Icons.close, size: 20) : const GlowIcon(GlowGlyph.bluetooth, size: 20),
      label: Text(label)),
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
    final item = await QuickActionsSheet.open(context, c, replacing: index != null);
    if (!mounted || item == null) return;
    c.updateShortcuts(index == null ? addShortcut(c.shortcuts, item) : replaceShortcut(c.shortcuts, index, item));
  }

}
