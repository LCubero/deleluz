import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../link.dart';
import '../model/models.dart';
import 'glow_glass.dart';
import 'notice.dart';

class StripSelector extends StatefulWidget {
  const StripSelector({super.key, required this.controller, this.backLabel = 'backToHome'});
  final AppController controller;
  final String backLabel;

  static Future<void> open(BuildContext context, AppController controller,
      {String backLabel = 'backToHome'}) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => StripSelector(controller: controller, backLabel: backLabel),
    ));
    controller.cancelScan();
  }

  @override
  State<StripSelector> createState() => _StripSelectorState();
}

class _StripSelectorState extends State<StripSelector> {
  AppController get c => widget.controller;
  final _search = TextEditingController();
  final _failures = <String, String>{};

  // Fold precomposed Latin accents and decomposed combining marks.
  static final _accents = {
    RegExp('[àáâãäåāăą]'): 'a', RegExp('[çćĉċč]'): 'c',
    RegExp('[èéêëēĕėęě]'): 'e', RegExp('[ìíîïĩīĭį]'): 'i',
    RegExp('[ñńņň]'): 'n', RegExp('[òóôõöøōŏő]'): 'o',
    RegExp('[ùúûüũūŭůűų]'): 'u', RegExp('[ýÿŷ]'): 'y',
    RegExp(r'[\u0300-\u036f]'): '',
  };

  String _fold(String value) => _accents.entries.fold(value.toLowerCase(),
    (text, accent) => text.replaceAll(accent.key, accent.value));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
      _connect(strip);
    }
  }

  void _connect(Strip strip) {
    if (c.busy || _connected(strip)) return;
    setState(() => _failures.remove(strip.id));
    c.connect(strip, onFailure: (key) {
      if (mounted) setState(() => _failures[strip.id] = key);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    final saved = c.rememberedStrips;
    final savedIds = saved.map((strip) => strip.id).toSet();
    final devices = c.devices;
    final nearby = devices.where((strip) => !savedIds.contains(strip.id)).toList();
    final showSearch = saved.length + nearby.length >= 4;
    final query = showSearch ? _fold(_search.text.trim()) : '';
    bool matches(Strip strip) => _fold(strip.name).contains(query) ||
      (strip is RememberedStrip && _fold(strip.label).contains(query));
    final savedMatches = saved.where(matches).toList();
    final nearbyMatches = nearby.where(matches).toList();
    final seen = devices.map((strip) => strip.id).toSet();
    final theme = Theme.of(context).textTheme;
    final header = Row(spacing: 10, children: [
          Material(color: glowGlass, shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: const BorderSide(color: glowLine)),
            child: IconButton(tooltip: c.text(widget.backLabel), icon: const BackButtonIcon(),
              onPressed: () => Navigator.of(context).pop())),
          Expanded(child: Text(c.text('chooseStrip'), style: theme.titleLarge)),
    ]);
    final children = <Widget>[
        Notice(c.text('oneStrip')),
        if (showSearch) ...[
          const SizedBox(height: 12),
          TextField(controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: c.text('searchStrip'),
              prefixIcon: const Icon(Icons.search), filled: true, fillColor: glowGlass,
              border: _searchBorder(glowLine), enabledBorder: _searchBorder(glowLine),
              focusedBorder: _searchBorder(glowViolet))),
        ],
        const SizedBox(height: 12),
        Semantics(expanded: c.stripsExpanded || query.isNotEmpty, child: TextButton(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
          onPressed: query.isEmpty ? c.toggleStripsExpanded : null,
          child: Row(spacing: 8, children: [
            Expanded(child: _section(c.text('myStrips', {'count': savedMatches.length}))),
            if (query.isEmpty) Icon(c.stripsExpanded ? Icons.expand_less : Icons.expand_more),
          ]),
        )),
        if (c.stripsExpanded || query.isNotEmpty)
          for (final strip in savedMatches) Padding(
            key: ValueKey(strip.id), padding: const EdgeInsets.only(top: 10),
            child: _row(strip, saved: strip, state: _connected(strip) ? 'connected'
              : c.scanCompleted && !seen.contains(strip.id) ? 'stripOutOfRange' : 'rememberedStrip'),
          ),
        const SizedBox(height: 20),
        _section(c.text('newNearbyStrips')),
        for (final strip in nearbyMatches) Padding(
          key: ValueKey(strip.id), padding: const EdgeInsets.only(top: 10), child: _row(strip),
        ),
        if (query.isNotEmpty && savedMatches.isEmpty && nearbyMatches.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 10),
            child: Notice(c.text('noMatchingStrips'), live: true)),
        if (c.scanning || (query.isEmpty && c.scanCompleted && nearby.isEmpty)) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Notice(c.text(c.scanning ? 'scanning' : 'noNewStrips'), live: true),
        ),
        if (c.message case final key?) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Notice(c.text(key), kind: NoticeKind.error, live: true),
        ),
        const SizedBox(height: 14),
        OutlinedButton(style: OutlinedButton.styleFrom(backgroundColor: glowGlass,
          side: const BorderSide(color: glowLine)),
          onPressed: c.connectingId != null ? null : c.canCancelScan ? c.cancelScan
              : c.busy ? null : c.startScan,
          child: Text(c.text(c.canCancelScan && c.connectingId == null ? 'cancel' : 'scanAgain'))),
    ];
    return Scaffold(
      body: GlowBackdrop(child: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 0), child: header),
          Expanded(child: ListView(key: const Key('strip-selector-list'),
            padding: glowScreenPadding, children: children)),
        ]),
      )))),
    );
  });

  OutlineInputBorder _searchBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: color));

  Widget _section(String label) => Text(label.toUpperCase(), style: const TextStyle(
    fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: glowMuted));

  Widget _row(Strip strip, {RememberedStrip? saved, String? state}) {
    final theme = Theme.of(context).textTheme;
    final connected = _connected(strip);
    final pending = c.connectingId == strip.id;
    final failure = connected || pending ? null : _failures[strip.id];
    final error = Theme.of(context).colorScheme.error;
    final primary = !connected && failure == null && !pending; // Cancelar stays grey (L54).
    final pill = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.square(48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: const StadiumBorder(),
        backgroundColor: primary ? Colors.transparent : glowGlassSelected,
        foregroundColor: failure == null ? glowInk : error,
        side: primary ? null : BorderSide(color: failure == null ? glowLine : error),
        textStyle: const TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w700),
      ),
      onPressed: pending ? c.cancelConnection : c.busy ? null : () => _toggle(strip),
      child: Text(c.text(pending ? 'cancel' : failure == null ? _action(strip) : 'retryStrip'),
        textAlign: TextAlign.center),
    );
    return Material(color: glowGlass,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: failure != null ? error : connected ? glowViolet : glowLine)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: c.busy || connected ? null : () => _connect(strip),
        onLongPress: saved == null || c.busy ? null : () => _menu(saved),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(spacing: 8, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(flex: 3, child: Padding(padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(saved?.label ?? strip.name, style: theme.titleMedium),
                  if (saved != null && saved.label != strip.name)
                    Text(strip.name, style: theme.bodySmall),
                  if (state != null) Row(spacing: 5, children: [
                    DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
                      color: connected ? const Color(0xff34d399) : glowFaint),
                      child: const SizedBox.square(dimension: 6)),
                    Flexible(child: Text(c.text(state), style: theme.bodySmall)),
                  ]),
                ]))),
              Flexible(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (saved != null) Row(mainAxisSize: MainAxisSize.min, children: [
                  _rowIcon('renameStrip', Icons.edit_outlined, () => _rename(saved)),
                  _rowIcon('forgetStripAction', Icons.delete_outline, () => _forget(saved)),
                ]),
                if (primary && !c.busy)
                  Ink(decoration: const ShapeDecoration(gradient: glowStrongGradient, shape: StadiumBorder()), child: pill)
                else pill,
              ])),
            ]),
            if (failure != null) Padding(padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Notice(c.text(failure), kind: NoticeKind.error, live: true)),
          ])),
      ),
    );
  }

  Widget _rowIcon(String label, IconData icon, VoidCallback action) => SizedBox.square(dimension: 48,
    child: IconButton(tooltip: c.text(label), icon: Icon(icon, size: 22), padding: EdgeInsets.zero,
      color: glowMuted, onPressed: c.busy ? null : action));

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
    final alias = await showGlowConfirmation<String>(context: context, title: c.text('renameStripTitle'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Text(strip.name),
        TextFormField(initialValue: value, maxLength: maxStripAlias,
          decoration: InputDecoration(labelText: c.text('stripAlias')),
          onChanged: (text) => value = text),
        Text(c.text('stripAliasHint'), style: Theme.of(context).textTheme.bodySmall),
      ]),
      cancelLabel: c.text('cancel'), confirmLabel: c.text('saveStripAlias'), confirmValue: () => value,
    );
    if (mounted && alias != null) c.renameStrip(strip.id, alias);
  }

  Future<void> _forget(RememberedStrip strip) async {
    final confirmed = await showGlowConfirmation<bool>(context: context, title: c.text('forgetStrip'),
      content: Text(c.text('forgetStripConfirm', {'name': strip.label})),
      cancelLabel: c.text('cancel'), confirmLabel: c.text('forgetStripAction'), confirmValue: () => true,
    );
    if (mounted && confirmed == true) await c.forgetStrip(strip.id);
  }
}
