import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';
import '../../protocol.dart' show chipOrders;
import '../../version.dart';
import '../glow_glass.dart';
import '../notice.dart';
import '../glow_icon.dart';
import '../strip_selector.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppController get c => widget.controller;
  String? _deviceId;
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
    c.addListener(_deviceChanged);
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_deviceChanged);
      _sending = false;
      _load();
      c.addListener(_deviceChanged);
    }
  }

  void _deviceChanged() {
    if (_deviceId != c.setupDevice?.id) _load();
  }

  void _load() {
    _deviceId = c.setupDevice?.id;
    final saved = c.models.loadStripSettings(deviceId: _deviceId);
    _order = saved.order;
    _perMeter = saved.density != null;
    _total.text = '${saved.pixels}';
    _density.text = '${saved.density ?? 30}';
    _meters.text = '${saved.meters ?? 5}';
    if (_perMeter) _syncTotal();
  }

  @override
  void dispose() {
    c.removeListener(_deviceChanged);
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
    final id = _deviceId;
    if (id == null) return;
    final saved = await controller.models.saveStripSettings(
      deviceId: id, order: _order, pixels: pixels,
      density: _perMeter ? _number(_density) : null,
      meters: _perMeter ? _number(_meters) : null,
    );
    if (!saved && mounted && c == controller) _notice('appStorageFailed');
  }

  void _notice(String key) => showGlowNotice(context, _text(key), kind: switch (key) {
    'aboutLinkCopied' => NoticeKind.info,
    'deviceSetupConnect' => NoticeKind.warning,
    _ => NoticeKind.error,
  });

  Future<void> _confirm() async {
    final controller = c;
    final id = controller.link.strip?.id;
    final pixels = _pixels;
    final order = _order;
    final density = _perMeter ? _number(_density) : null;
    final meters = _perMeter ? _number(_meters) : null;
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
        _notice('deviceSetupConnect');
        return;
      }
      final sent = await controller.setChipConfig(order, pixels,
        density: density, meters: meters);
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
          _stripsRow(),
          _section('stripSettings', _deviceId == null ? [
            Notice(_text('deviceSetupEmpty')),
          ] : [
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
            if (_pixels == null) Notice(_text('stripError'), kind: NoticeKind.error, live: true),
            FilledButton(key: const Key('stripSend'),
              onPressed: _pixels != null && c.ready && !_sending ? _confirm : null,
              child: Text(_text('stripSend'), textAlign: TextAlign.center)),
            if (!c.ready) Notice(_text('deviceSetupConnect'), kind: NoticeKind.warning),
            Semantics(liveRegion: true, child: Text(lastLabel, style: theme.bodyMedium)),
            Notice(_text('stripFactory')),
          ], subtitle: c.setupDevice?.label),
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
          _section('privacyTitle', [Notice(_text('privacyText')), Notice(_text('privacyTimer'))]),
          _about(theme),
        ]),
      )),
    ));
  });

  static const _repository = 'github.com/LCubero/deleluz';

  Future<void> _copyRepository() async {
    await Clipboard.setData(const ClipboardData(text: 'https://$_repository'));
    if (mounted) _notice('aboutLinkCopied');
  }

  Widget _about(TextTheme theme) => _section('about', [
    Row(spacing: 8, children: [
      const GlowIcon(GlowGlyph.wave),
      Flexible(child: Text('DeleLuz', style: theme.titleMedium)),
    ]),
    Text(_text('aboutDescription')),
    Text(c.text('aboutVersion', {'version': appVersion}), style: theme.bodySmall),
    Column(children: [
      _aboutRow('aboutAuthor', 'LCubero'),
      _aboutRow('aboutLicense', 'MIT'),
      InkWell(onTap: _copyRepository, child: _aboutRow('aboutRepository', _repository, copy: true)),
    ]),
    Center(child: ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(colors: [glowViolet, glowPink]).createShader(bounds),
      child: Text('¡Dele, enciéndala, mae!', textAlign: TextAlign.center, style: theme.titleMedium),
    )),
  ]);

  Widget _aboutRow(String key, String value, {bool copy = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
      Expanded(flex: 2, child: Text(_text(key))),
      Expanded(flex: 3, child: Text(value)),
      SizedBox(width: 18, child: copy ? const Icon(Icons.copy, size: 18) : null),
    ]),
  );

  Widget _stripsRow() {
    final alias = c.remembered?.alias;
    return _row(ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: glassInset + 1),
      title: Text(_text('strips'), style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: glowInk)),
      subtitle: alias == null ? null : Text(alias, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => StripSelector.open(context, c, backLabel: 'backToSettings'),
    ));
  }

  Widget _row(Widget child) => Material(color: glowGlass,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: glowLine)),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _section(String key, List<Widget> children, {String? subtitle}) => _row(
    GlowDisclosure(titleKey: ValueKey('settings-$key'), title: _text(key), smallChevron: true,
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      padding: const EdgeInsets.symmetric(horizontal: glassInset + 1),
      children: [Padding(padding: const EdgeInsets.fromLTRB(glassInset + 1, 0, glassInset + 1, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children))],
    ),
  );

  Widget _symptom(String key, List<String> steps) => GlowDisclosure(
    title: _text(key), smallChevron: true,
    children: [Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      for (final (index, step) in steps.indexed) Notice('${index + 1}. ${_text(step)}'),
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
