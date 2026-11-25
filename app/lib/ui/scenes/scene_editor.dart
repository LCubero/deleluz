part of 'scenes_screen.dart';

class SceneEditor extends StatefulWidget {
  const SceneEditor._({required this.transport, this.item});

  static Future<void> create(BuildContext context, AppController controller) async {
    final transport = SceneTransport(controller);
    try {
      await showDialog<void>(context: context, builder: (_) => SceneEditor._(transport: transport));
    } finally {
      transport.stopPreview();
      transport.dispose();
    }
  }
  final SceneTransport transport;
  final Fields? item;

  @override
  State<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<SceneEditor> {
  AppController get c => widget.transport.controller;
  late final String? _id = widget.item?['id'] as String?;
  late final Fields _initial = widget.item ?? createSequence(c.models.loadSequences(),
    nameFor: (n) => c.text('sequenceName', {'number': n})).last;
  late final List<Fields> _steps = sceneSteps(_initial);
  late int _intensity = _initial['bri'] as int;
  late final TextEditingController _name = TextEditingController(text: _initial['name'] as String);
  late bool _renaming = _id == null;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final items = c.models.loadSequences();
    final error = _id == null && items.length >= maxSequences
        ? 'scenesLimit' : sequenceNameError(items, _id, name);
    if (error != null) {
      setState(() { _error = error; _renaming = true; });
      return;
    }
    final draft = <String, Object?>{
      'name': name, 'steps': _steps, 'bri': _intensity,
    };
    final random = Random.secure();
    final next = _id == null ? [...items, {
      ...draft, 'id': List.generate(4, (_) => random.nextInt(1 << 32)).join('-'),
    }] : updateSequence(items, _id, draft);
    setState(() { _busy = true; _error = null; });
    final ok = !identical(next, items) && await c.models.saveSequences(next);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() { _busy = false; _error = 'sequenceSaveFailed'; });
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(c.text('confirmDeleteSequence')),
      actions: [
        TextButton(key: const Key('scene-cancel-delete'), onPressed: () => Navigator.pop(context, false),
          child: Text(c.text('cancelDelete'))),
        FilledButton(key: const Key('scene-confirm-delete'), onPressed: () => Navigator.pop(context, true),
          child: Text(c.text('deleteScene'))),
      ],
    ));
    if (yes != true || !mounted) return;
    final id = _id;
    if (id == null) {
      Navigator.pop(context);
      return;
    }
    setState(() { _busy = true; _error = null; });
    final ok = await c.models.saveSequences(removeSequence(c.models.loadSequences(), id));
    if (ok) {
      c.stopSequence(id);
      await c.updateShortcuts(c.shortcuts);
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() { _busy = false; _error = 'sequenceDeleteFailed'; });
    }
  }

  String _duration(int ms) => glowSeconds(ms, c.language);

  Future<void> _pick({required bool effect, int? index}) async {
    final step = await GlowSheet.open<Fields>(context,
      builder: (context) => _StepPicker(controller: c, effect: effect,
        initial: index == null ? null : _steps[index]));
    if (step == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps.add(step);
      } else {
        _steps[index] = step;
      }
    });
  }

  Widget _row(int index, Fields step) {
    final rgb = step['rgb'] as List<int>?;
    final label = rgb == null ? effectName(step['effect'] as int)! : rgbHex(rgb);
    final marker = rgb == null ? const Icon(Icons.auto_awesome) :
        Icon(Icons.circle, color: _rgb(rgb));
    return DragTarget<Fields>(key: ObjectKey(step),
      onWillAcceptWithDetails: (details) => !_busy && details.data != step,
      onAcceptWithDetails: (details) => setState(() {
        _steps.remove(details.data);
        _steps.insert(index, details.data);
      }),
      builder: (context, candidates, _) => LongPressDraggable<Fields>(
        data: step, maxSimultaneousDrags: _busy ? 0 : 1,
        feedback: Material(shape: const CircleBorder(), child: Padding(
          padding: const EdgeInsets.all(12), child: marker)),
        child: ListTile(key: Key('scene-frame-$index'), contentPadding: EdgeInsets.zero,
          selected: candidates.isNotEmpty, leading: marker,
          title: Text(label),
          subtitle: Text('${c.text(rgb == null ? 'sceneEffectStep' : 'sceneColorStep')} · '
            '${_duration(step['durationMs'] as int)}'),
          onTap: _busy ? null : () => _pick(effect: rgb == null, index: index),
          trailing: IconButton(key: Key('scene-remove-step-$index'),
            tooltip: c.text('sceneRemoveStep'), icon: const Icon(Icons.remove_circle_outline),
            onPressed: _busy || _steps.length == 1 ? null : () => setState(() => _steps.removeAt(index))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.transport,
    builder: (context, _) => Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: glowLine)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: GlowBackdrop(child: SizedBox(width: 410, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: ScrollHint(shrinkWrap: true,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_renaming ? c.text('sequenceNameLabel') : _name.text,
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_renaming) ...[
          TextField(key: const Key('scene-name'), controller: _name, enabled: !_busy,
            decoration: InputDecoration(hintText: c.text('sequenceNameLabel')),
            onChanged: (_) { if (_error != null) setState(() => _error = null); }),
          ValueListenableBuilder(valueListenable: _name, builder: (context, value, _) => Text(
            c.text('sceneNameCount', {'count': value.text.trim().length, 'max': maxSequenceName}),
            style: Theme.of(context).textTheme.bodySmall)),
        ],
        if (!_renaming) Align(alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(key: const Key('scene-rename'),
            onPressed: _busy ? null : () => setState(() => _renaming = true),
            icon: const Icon(Icons.edit_outlined), label: Text(c.text('renameSequence')))),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Notice(
          c.text(_error!, {'max': _error == 'scenesLimit' ? maxSequences : maxSequenceName}),
          kind: NoticeKind.error, live: true,
        )),
        const SizedBox(height: 12),
        Text(c.text('sceneSteps'), style: Theme.of(context).textTheme.titleMedium),
        Text(c.text('sceneTotal', {'duration': _duration(
          _steps.fold(0, (sum, step) => sum + (step['durationMs'] as int)))})),
        SliderZone(child: Column(children: [
          for (final (index, step) in _steps.indexed) ...[_row(index, step), const Divider(height: 1)],
        ])),
        const SizedBox(height: 8),
        Notice(c.text('sequenceReorderHint')),
        if (_steps.length >= maxColors)
          Notice(c.text('sceneStepsLimit', {'max': maxColors}), kind: NoticeKind.warning),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
          OutlinedButton(key: const Key('scene-add-color'),
            onPressed: _busy || _steps.length >= maxColors ? null : () => _pick(effect: false),
            child: Text(c.text('sceneAddColor'))),
          OutlinedButton(key: const Key('scene-add-effect'),
            onPressed: _busy || _steps.length >= maxColors ? null : () => _pick(effect: true),
            child: Text(c.text('sceneAddEffect'))),
        ]),
        const SizedBox(height: 14),
        SliderZone(child: _SceneSlider(controller: c, id: 'scene-intensity', label: 'brightness', min: 1,
          icon: const GlowIcon(GlowGlyph.sun, size: 20), value: _intensity, onChanged: (value) {
            setState(() => _intensity = value);
            c.setDraftPreviewBrightness(value);
          })),
        const SizedBox(height: 8),
        Notice(c.text('foregroundPlaybackHint')),
        const SizedBox(height: 8),
        _LastSent(transport: widget.transport),
        if (widget.transport.failed) Notice(c.text('commandFailed'), kind: NoticeKind.error, live: true),
        const SizedBox(height: 18),
        Center(
          child: OutlinedButton.icon(key: const Key('scene-delete'), onPressed: _busy ? null : _delete,
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: .45))),
            icon: const Icon(Icons.delete_outline), label: Text(c.text('deleteSequence')))),
      ])))),
      Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 10), child: Wrap(
        alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
        TextButton(key: const Key('scene-close'), onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(c.text('close'))),
        TextButton(key: const Key('scene-start'), onPressed: !_busy && widget.transport.ready ? () {
          unawaited(c.playSteps(_steps, _intensity, draft: () => (steps: _steps, intensity: _intensity)));
        } : null, child: Text(c.text('playSequence'))),
        TextButton(key: const Key('scene-stop'), onPressed: widget.transport.previewing
          ? widget.transport.stopPreview : null, child: Text(c.text('stopSequence'))),
        FilledButton(key: const Key('scene-save'), onPressed: _busy ? null : _save,
          child: Text(c.text('saveSequence'))),
      ])),
      ]))),
    ));
}

class _StepPicker extends StatefulWidget {
  const _StepPicker({required this.controller, required this.effect, this.initial});

  final AppController controller;
  final bool effect;
  final Fields? initial;

  @override
  State<_StepPicker> createState() => _StepPickerState();
}

class _StepPickerState extends State<_StepPicker> {
  AppController get c => widget.controller;
  late List<int> _color = (widget.initial?['rgb'] as List<int>?) ?? [255, 255, 255];
  late int? _effect = widget.initial?['effect'] as int?;
  late int? _duration = widget.initial?['durationMs'] as int? ?? (widget.effect ? 30000 : 500);
  late final String _initialDuration = widget.effect
      ? (_duration! % 1000 == 0 ? '${_duration! ~/ 1000}' : '${_duration! / 1000}')
      : '$_duration';

  void _changeDuration(String text) {
    final value = widget.effect && RegExp(r'^\d{1,3}([.,]\d{1,3})?$').hasMatch(text)
        ? (double.parse(text.replaceAll(',', '.')) * 1000).round()
        : widget.effect ? null : int.tryParse(text);
    final min = widget.effect ? 1000 : 150;
    final max = widget.effect ? 600000 : 2000;
    setState(() => _duration = value != null && value >= min && value <= max ? value : null);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _duration != null && (!widget.effect || _effect != null);
    return Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          if (widget.effect) ...[
            ListenableBuilder(listenable: c, builder: (context, _) => EffectList(
              favorites: c.effectFavorites, text: c.text, onFavorite: c.toggleEffectFavorite,
              selected: _effect, onSelected: (id) => setState(() => _effect = id))),
            if (_effect != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(c.text('quickPreview', {'name': effectName(_effect!)!}))),
          ] else
            SharedColorPicker(controller: c, rgb: _color,
              onChanged: (rgb, _) => setState(() => _color = rgb)),
          TextFormField(key: const Key('scene-step-duration'), initialValue: _initialDuration,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.effect),
            decoration: InputDecoration(
              labelText: c.text(widget.effect ? 'sceneDurationSeconds' : 'sceneDurationMillis'),
              helperText: widget.effect ? '1–600 s' : '150–2000 ms',
              errorText: _duration == null ? c.text('sceneInvalidDuration') : null),
            onChanged: _changeDuration),
          FilledButton(key: const Key('scene-apply-step'), onPressed: !enabled ? null : () {
            Navigator.pop(context, <String, Object?>{
              if (widget.effect) 'effect': _effect else 'rgb': _color,
              'durationMs': _duration,
            });
          }, child: Text(c.text(widget.initial == null ? 'sceneAddStep' : 'sceneUpdateStep'))),
        ]),
      )),
    );
  }
}
