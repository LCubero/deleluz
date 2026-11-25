import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';
import '../model/models.dart';
import 'glow_glass.dart';

class StripSelector extends StatefulWidget {
  const StripSelector({super.key, required this.controller});
  final AppController controller;

  @override
  State<StripSelector> createState() => _StripSelectorState();
}

class _StripSelectorState extends State<StripSelector> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.startScan();
    });
  }

  bool _connected(Strip strip) => c.link.ready && c.link.strip?.id == strip.id;
  String _action(Strip strip) => _connected(strip) ? 'disconnect' : 'connect';

  void _toggle(Strip strip) {
    if (_connected(strip)) {
      c.disconnect();
    } else {
      c.connect(strip);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    final saved = c.rememberedStrips;
    final savedIds = saved.map((strip) => strip.id).toSet();
    final devices = c.devices;
    final nearby = devices.where((strip) => !savedIds.contains(strip.id)).toList();
    final seen = devices.map((strip) => strip.id).toSet();
    final theme = Theme.of(context).textTheme;
    final children = <Widget>[
        Text(c.text('oneStrip'), style: theme.bodySmall),
        const SizedBox(height: 12),
        Semantics(expanded: c.stripsExpanded, child: TextButton(
          onPressed: c.toggleStripsExpanded,
          child: Row(spacing: 8, children: [
            Expanded(child: Text(c.text('myStrips', {'count': saved.length}), style: theme.titleMedium)),
            Icon(c.stripsExpanded ? Icons.expand_less : Icons.expand_more),
          ]),
        )),
        if (c.stripsExpanded)
          for (final strip in saved) Padding(
            key: ValueKey(strip.id), padding: const EdgeInsets.only(top: 10),
            child: _row(strip, saved: strip, state: _connected(strip) ? 'connected'
              : c.scanCompleted && !seen.contains(strip.id) ? 'stripOutOfRange' : 'rememberedStrip'),
          ),
        const SizedBox(height: 20),
        Text(c.text('newNearbyStrips'), style: theme.titleMedium),
        for (final strip in nearby) Padding(
          key: ValueKey(strip.id), padding: const EdgeInsets.only(top: 10), child: _row(strip),
        ),
        if (c.scanning || (c.scanCompleted && nearby.isEmpty)) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(c.text(c.scanning ? 'scanning' : 'noNewStrips'))),
        ),
        if (c.message case final key?) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(c.text(key),
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: c.busy || c.scanning ? null : c.startScan,
          child: Text(c.text('scanAgain'))),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(c.text('chooseStrip')), leading: IconButton(
        tooltip: c.text('backToHome'), icon: const BackButtonIcon(),
        onPressed: () => Navigator.of(context).pop(),
      )),
      body: GlowBackdrop(child: SafeArea(top: false, child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(padding: glowScreenPadding, children: children),
      )))),
    );
  });

  Widget _row(Strip strip, {RememberedStrip? saved, String? state}) {
    final theme = Theme.of(context).textTheme;
    return Material(color: glowGlass,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _connected(strip) ? glowViolet : glowLine)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: saved == null || c.busy ? null : () => _menu(saved),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(saved?.label ?? strip.name, style: theme.titleMedium),
              if (saved != null) Text(strip.name, style: theme.bodySmall),
              if (state != null) Text(c.text(state), style: theme.bodySmall),
            ]),
            Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8, runSpacing: 8, children: [
                if (saved != null) ...[
                  IconButton(tooltip: c.text('renameStrip'), icon: const Icon(Icons.edit_outlined),
                    onPressed: c.busy ? null : () => _rename(saved)),
                  IconButton(tooltip: c.text('forgetStripAction'), icon: const Icon(Icons.delete_outline),
                    onPressed: c.busy ? null : () => _forget(saved)),
                ],
                FilledButton(onPressed: c.busy ? null : () => _toggle(strip), child: Text(c.text(_action(strip)))),
              ]),
          ],
        )),
      ),
    );
  }

  Future<void> _menu(RememberedStrip strip) async {
    final action = _action(strip);
    final chosen = await showDialog<String>(context: context, builder: (context) => SimpleDialog(
      title: Text(strip.label), children: [
        for (final key in [action, 'renameStrip', 'forgetStripAction'])
          SimpleDialogOption(onPressed: () => Navigator.pop(context, key), child: Text(c.text(key))),
      ],
    ));
    if (!mounted || c.busy) return;
    switch (chosen) {
      case 'connect' || 'disconnect': _toggle(strip);
      case 'renameStrip': await _rename(strip);
      case 'forgetStripAction': await _forget(strip);
    }
  }

  Future<void> _rename(RememberedStrip strip) async {
    var value = strip.alias ?? '';
    final alias = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      scrollable: true, title: Text(c.text('renameStripTitle')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Text(strip.name),
        TextFormField(initialValue: value, maxLength: maxStripAlias,
          decoration: InputDecoration(labelText: c.text('stripAlias')),
          onChanged: (text) => value = text),
        Text(c.text('stripAliasHint'), style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(c.text('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, value), child: Text(c.text('saveStripAlias'))),
      ],
    ));
    if (mounted && alias != null) c.renameStrip(strip.id, alias);
  }

  Future<void> _forget(RememberedStrip strip) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      scrollable: true, title: Text(c.text('forgetStrip')),
      content: Text(c.text('forgetStripConfirm', {'name': strip.label})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(c.text('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(c.text('forgetStripAction'))),
      ],
    ));
    if (mounted && confirmed == true) await c.forgetStrip(strip.id);
  }
}
