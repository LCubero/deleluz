import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';
import '../model/models.dart';
import '../model/timer.dart';
import 'bluetooth_card.dart';
import 'glow_glass.dart';
import 'glow_icon.dart';
import 'notice.dart';
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
    return SingleChildScrollView(padding: glowScreenPadding, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowHeader(title: c.text('title'), controller: c, showStatus: false,
        leading: const GlowIcon(GlowGlyph.wave), actions: [
        Center(child: IconButton(tooltip: c.text('offTimer'),
          icon: SizedBox.square(dimension: 44, child: DecoratedBox(
            decoration: BoxDecoration(color: glowGlass, border: Border.all(color: glowLine),
              borderRadius: BorderRadius.circular(14)),
            child: const Center(child: GlowIcon(GlowGlyph.timer, size: 22)),
          )),
          style: IconButton.styleFrom(fixedSize: const Size.square(48), padding: EdgeInsets.zero),
          onPressed: off ? null : () => TimerSheet.open(context, c))),
      ]),
      if (c.remaining case final seconds?)
        Text(c.text('offIn', {'time': formatRemaining(seconds)}), style: style.bodySmall),
      const SizedBox(height: 12),
      if (off) ...[
        BluetoothCard(controller: c),
        const SizedBox(height: 12),
      ],
      if (c.sessionOnlyStorage) ...[
        Notice(c.text('sessionOnlyStorage'), kind: NoticeKind.warning, live: true),
        const SizedBox(height: 12),
      ],
      SliderZone(child: dim(_device(context))),
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
      ConstrainedBox(constraints: BoxConstraints(
        minHeight: 2 * MediaQuery.textScalerOf(context).scale(13) * 1.4),
        child: Text(last == null ? c.text('noCommand') : c.text('lastSentShort', {'command': last}),
          textAlign: TextAlign.center, style: style.bodySmall,
          strutStyle: const StrutStyle(fontSize: 13, height: 1.4, forceStrutHeight: true))),
      const SizedBox(height: 8),
      dim(ExcludeFocus(excluding: off, child: AbsorbPointer(absorbing: off, child: _quick(context)))),
      const SizedBox(height: 8),
      dim(_brightness()),
    ]));
  }

  Widget _quick(BuildContext context) {
    final count = c.shortcuts.length + (c.shortcuts.length < maxShortcuts ? 1 : 0);
    return Column(children: [
      Semantics(button: true, expanded: _quickOpen, child: InkWell(
        onTap: () => setState(() => _quickOpen = !_quickOpen),
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: Row(spacing: 8, children: [
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
        if (c.shortcuts.length >= maxShortcuts) ...[
          const SizedBox(height: 8),
          Notice(c.text('quickActionsLimit', {'max': maxShortcuts}), kind: NoticeKind.warning),
        ],
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Notice(c.text('connectFirst'), kind: NoticeKind.warning)));
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

  Widget _brightness() =>
    SliderZone(child: GlassCard(verticalInset: 12,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlowValueLabel(label: c.text('brightness'), value: c.text('percent', {'value': c.brightness}),
          icon: const GlowIcon(GlowGlyph.sun, size: 20)),
        const SizedBox(height: 10),
        Semantics(label: c.text('brightness'), child: Slider(key: const Key('brightness'),
          value: c.brightness.toDouble(), max: 100,
          onChanged: c.bluetoothOff ? null : (value) => c.setBrightness(value.round()),
          onChangeEnd: c.bluetoothOff ? null : (_) => c.saveSelection())),
      ]),
    ));

  Widget _device(BuildContext context) {
    final strip = c.remembered;
    final off = c.bluetoothOff;
    final connected = !off && c.link.ready && c.link.strip?.id == strip?.id;
    final pending = c.connectingId != null;
    final status = c.connectingId == strip?.id && pending ? LinkStatus.connecting
        : connected ? LinkStatus.connected
        : !c.link.ready ? c.link.status : LinkStatus.idle;
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

    ]);
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      LayoutBuilder(builder: (context, constraints) => Row(spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: name),
          // Give the status room before wrapping it, without crowding out the name.
          ConstrainedBox(constraints: BoxConstraints(maxWidth: (constraints.maxWidth - 12) * .67),
            child: ConnectionChip(controller: c, status: status)),
        ])),
      Semantics(container: true, image: true,
        label: c.text(unknown ? 'stripPreviewUnknown' : 'stripPreview'),
        child: GlowStrip(colors: previewColors, height: 14, glow: glow)),
      Row(spacing: 8, children: [
        Expanded(child: _connectButton(c.text(pending ? 'cancel' : connected ? 'disconnect'
            : strip != null ? 'reconnect' : 'connect'), neutral: pending,
          off ? null : pending ? c.cancelConnection : c.busy ? null : connected ? c.disconnect
            : strip == null ? _chooseStrip : c.reconnect)),
        TextButton(onPressed: off || c.busy ? null : _chooseStrip,
          style: TextButton.styleFrom(foregroundColor: glowLink,
            padding: const EdgeInsets.symmetric(horizontal: 8)), child: Text(c.text('changeStrip'))),
      ]),
      if (c.message case final key? when key != 'bluetoothOff' && key != 'bluetoothEnableFailed') ...[
        const SizedBox(height: 8),
        Notice(c.text(key), kind: NoticeKind.error, live: true),
      ],
      if (c.timerOffFailed) TimerOffNotice(c),
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
      case 'moveLeft': await c.updateShortcuts(moveItem(c.shortcuts, index, index - 1));
      case 'moveRight': await c.updateShortcuts(moveItem(c.shortcuts, index, index + 1));
      case 'removeShortcut': await c.updateShortcuts(removeShortcut(c.shortcuts, index));
    }
  }

  Future<void> _pickShortcut([int? index]) async {
    final item = await QuickActionsSheet.open(context, c, replacing: index != null);
    if (!mounted || item == null) return;
    await c.updateShortcuts(index == null ? addShortcut(c.shortcuts, item) : replaceShortcut(c.shortcuts, index, item));
  }

}
