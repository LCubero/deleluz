import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';
import '../../protocol.dart' show chipOrders;
import '../glow_glass.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppController get c => widget.controller;
  late String _order;
  late bool _perMeter;
  final _total = TextEditingController();
  final _density = TextEditingController();
  final _meters = TextEditingController();
  bool _sending = false;

  String _text(String key) => c.text(key);

  num? _number(TextEditingController field) =>
      num.tryParse(field.text.trim().replaceAll(',', '.'));
  int? get _pixels => _perMeter
      ? stripPixels(_number(_density), _number(_meters))
      : validPixels(_number(_total));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      _sending = false;
      _load();
    }
  }

  void _load() {
    final saved = c.models.loadStripSettings();
    _order = saved.order;
    _perMeter = saved.density != null;
    _total.text = '${saved.pixels}';
    _density.text = '${saved.density ?? 30}';
    _meters.text = '${saved.meters ?? 5}';
    if (_perMeter) _syncTotal();
  }

  @override
  void dispose() {
    _total.dispose();
    _density.dispose();
    _meters.dispose();
    super.dispose();
  }

  void _syncTotal() => _total.text = _pixels?.toString() ?? '';

  void _changed() {
    if (_perMeter) _syncTotal();
    setState(() {});
    final pixels = _pixels;
    if (pixels != null) unawaited(_save(pixels));
  }

  Future<void> _save(int pixels) async {
    final controller = c;
    final saved = await controller.models.saveStripSettings(
      order: _order, pixels: pixels,
      density: _perMeter ? _number(_density) : null,
      meters: _perMeter ? _number(_meters) : null,
    );
    if (!saved && mounted && c == controller) _notice('appStorageFailed');
  }

  void _notice(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_text(key))),
  );

  Future<void> _confirm() async {
    final controller = c;
    final id = controller.link.strip?.id;
    final pixels = _pixels;
    final order = _order;
    if (!controller.ready || id == null || pixels == null || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    var sameConnection = true;
    void trackConnection() {
      if (!controller.link.ready || controller.link.strip?.id != id) {
        sameConnection = false;
      }
    }

    controller.addListener(trackConnection);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(_text('stripSend')),
        content: Text('$order · $pixels LEDs\n\n${_text('stripConfirm')}'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(dialog, false), child: Text(_text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(_text('send'))),
        ],
      ));
      if (confirmed != true || !mounted || c != controller) return;
      if (!sameConnection || !controller.ready) {
        _notice('connectFirst');
        return;
      }
      final sent = await controller.setChipConfig(order, pixels,
        density: _perMeter ? _number(_density) : null,
        meters: _perMeter ? _number(_meters) : null);
      if (!sent && mounted && c == controller && c.message == 'commandFailed') {
        _notice('commandFailed');
      }
    } catch (_) {
      if (mounted && c == controller) _notice('commandFailed');
    } finally {
      controller.removeListener(trackConnection);
      if (mounted && c == controller) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
    final theme = Theme.of(context).textTheme;
    final lastLabel = c.lastCommand == 'chipConfig'
        ? c.text('lastSent', {'command': c.lastSentLabel})
        : _text('stripNotSent');
    return SafeArea(child: SingleChildScrollView(
      padding: glowScreenPadding,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          GlowHeader(title: _text('settings'), controller: c),
          _section('stripSettings', [
            Text(_text('stripOrder')),
            DropdownButton<String>(
              key: const Key('stripOrder'), isExpanded: true, value: _order,
              items: [for (final order in chipOrders) DropdownMenuItem(value: order, child: Text(order))],
              onChanged: (order) {
                if (order == null) return;
                _order = order;
                _changed();
              },
            ),
            _segments('stripCount', ['stripModeTotal', 'stripModeMeter'], _perMeter ? 1 : 0, (choice) {
              _perMeter = choice == 1;
              _changed();
            }),
            if (_perMeter) ...[
              _field('stripDensity', _density, decimal: true),
              _field('stripMeters', _meters, decimal: true),
            ],
            _field('stripTotal', _total, readOnly: _perMeter),
            if (_pixels == null) Semantics(liveRegion: true, child: Text(_text('stripError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
            FilledButton(key: const Key('stripSend'),
              onPressed: _pixels != null && c.ready && !_sending ? _confirm : null,
              child: Text(_text('stripSend'), textAlign: TextAlign.center)),
            if (!c.ready) Text(_text('connectFirst'), style: theme.bodySmall),
            Semantics(liveRegion: true, child: Text(lastLabel, style: theme.bodyMedium)),
            Text(_text('stripFactory'), style: theme.bodySmall),
          ]),
          _section('settingsLanguage', [
            _segments('settingsLanguage', ['spanish', 'english'], c.language == 'en' ? 1 : 0,
              (choice) => c.setLanguage(choice == 1 ? 'en' : 'es')),
          ]),
          _section('help', [
            Text(_text('troubleshoot'), style: theme.titleMedium),
            _symptom('missingStrip', ['closeLamp', 'enableBluetooth', 'standNear']),
            _symptom('frequentDrops', ['steadyPower', 'closeOtherApps']),
            _symptom('noResponse', ['checkPower', 'tryWhite']),
            _symptom('sceneStopped', ['keepForeground', 'applyAgain']),
          ]),
          _section('privacyTitle', [Text(_text('privacyText')), Text(_text('privacyTimer'))]),
        ]),
      )),
    ));
  });

  Widget _section(String key, List<Widget> children) => Material(color: glowGlass,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: glowLine)),
    clipBehavior: Clip.antiAlias,
    child: GlowDisclosure(titleKey: ValueKey('settings-$key'), title: _text(key),
      padding: const EdgeInsets.symmetric(horizontal: glassInset + 1),
      children: [Padding(padding: const EdgeInsets.fromLTRB(glassInset + 1, 0, glassInset + 1, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children))],
    ),
  );

  Widget _symptom(String key, List<String> steps) => GlowDisclosure(
    title: _text(key),
    children: [Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      for (final (index, step) in steps.indexed) Text('${index + 1}. ${_text(step)}'),
    ])],
  );

  Widget _field(String key, TextEditingController field, {bool readOnly = false, bool decimal = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
        ExcludeSemantics(child: Text(_text(key))),
        Semantics(label: _text(key), child: TextField(
          key: Key(key), controller: field, readOnly: readOnly,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => _changed(),
        )),
      ]);

  Widget _segments(String label, List<String> keys, int selected, ValueChanged<int> onSelect) =>
      Semantics(container: true, label: _text(label), child: GlowSegments<int>(
        segments: [for (final (index, key) in keys.indexed)
          ButtonSegment(value: index, label: Text(_text(key), textAlign: TextAlign.center))],
        selected: selected,
        onSelected: onSelect,
      ));
}
