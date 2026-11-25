part of 'scenes_screen.dart';

class _SceneEditor extends StatefulWidget {
  const _SceneEditor({required this.transport, this.item});
  final SceneTransport transport;
  final Fields? item;

  @override
  State<_SceneEditor> createState() => _SceneEditorState();
}

class _Frame {
  _Frame(this.rgb);
  List<int> rgb;
}

class _SceneEditorState extends State<_SceneEditor> {
  AppController get c => widget.transport.controller;
  late final String? _id = widget.item?['id'] as String?;
  late final Fields _initial = widget.item ?? createSequence(c.models.loadSequences(),
    nameFor: (n) => c.text('sequenceName', {'number': n})).last;
  late final List<_Frame> _frames = (_initial['colors'] as List<List<int>>).map(_Frame.new).toList();
  late _Frame _selected = _frames.first;
  late int _speed = speedPercent(_interval);
  late int _interval = _initial['interval'] as int;
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
    final error = sequenceNameError(items, _id, name);
    if (error != null) {
      setState(() { _error = error; _renaming = true; });
      return;
    }
    final draft = <String, Object?>{
      'name': name, 'colors': [for (final frame in _frames) frame.rgb],
      'interval': _interval, 'bri': _intensity,
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
    setState(() { _busy = true; _error = null; });
    final ok = await c.models.saveSequences(removeSequence(c.models.loadSequences(), _id!));
    if (ok) {
      c.stopSequence(_id);
      c.updateShortcuts(c.shortcuts);
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() { _busy = false; _error = 'sequenceDeleteFailed'; });
    }
  }

  void _reorder(_Frame from, _Frame to) {
    final index = _frames.indexOf(to);
    setState(() { _frames.remove(from); _frames.insert(index, from); });
  }

  Widget _square(int index, _Frame frame) {
    final description = c.text('sequenceFrame', {'number': index + 1, 'hex': rgbHex(frame.rgb)});
    final selected = frame == _selected;
    Widget paint({required bool outline}) => Container(width: 48, height: 48,
      decoration: BoxDecoration(color: _rgb(frame.rgb), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline ? glowInk : glowLine, width: outline ? 3 : 1)),
    );
    return DragTarget<_Frame>(key: ObjectKey(frame),
      onWillAcceptWithDetails: (details) => !_busy && details.data != frame,
      onAcceptWithDetails: (details) => _reorder(details.data, frame),
      builder: (context, candidate, _) => LongPressDraggable<_Frame>(
        maxSimultaneousDrags: _busy ? 0 : 1, data: frame,
        feedback: paint(outline: true),
        child: Semantics(button: true, selected: selected, label: description,
          child: Tooltip(message: description, triggerMode: TooltipTriggerMode.manual,
            child: InkWell(key: Key('scene-frame-$index'), borderRadius: BorderRadius.circular(10),
              onTap: _busy ? null : () => setState(() => _selected = frame),
              child: paint(outline: selected || candidate.isNotEmpty),
            ),
          ),
        ),
      ),
    );
  }

  void _setColor(List<int> rgb) => setState(() => _selected.rgb = rgb);

  Widget _wheel() {
    final hue = HSVColor.fromColor(_rgb(_selected.rgb)).hue;
    void select(double next) {
      final argb = HSVColor.fromAHSV(1, next, 1, 1).toColor().toARGB32();
      _setColor([(argb >> 16) & 255, (argb >> 8) & 255, argb & 255]);
    }
    String degrees(double value) => '${value.round()}°';
    return Semantics(slider: true, label: c.text('hue'), value: degrees(hue),
      increasedValue: degrees((hue + 15) % 360), decreasedValue: degrees((hue - 15) % 360),
      onIncrease: _busy ? null : () => select((hue + 15) % 360),
      onDecrease: _busy ? null : () => select((hue - 15) % 360),
      child: ExcludeSemantics(child: IgnorePointer(ignoring: _busy,
        child: HueWheel(hue: hue, label: c.text('hue'), onChanged: select))),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.transport,
    builder: (context, _) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SizedBox(width: 410, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_renaming ? c.text('sequenceNameLabel') : _name.text,
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_renaming) TextField(key: const Key('scene-name'), controller: _name, enabled: !_busy,
          decoration: InputDecoration(hintText: c.text('sequenceNameLabel')),
          onChanged: (_) { if (_error != null) setState(() => _error = null); }),
        if (!_renaming) Align(alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(key: const Key('scene-rename'),
            onPressed: _busy ? null : () => setState(() => _renaming = true),
            icon: const Icon(Icons.edit_outlined), label: Text(c.text('renameSequence')))),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(
          c.text(_error!, {'max': maxSequenceName}), style: TextStyle(color: Theme.of(context).colorScheme.error),
        )),
        const SizedBox(height: 12),
        Text(c.text('sequenceFrames'), style: Theme.of(context).textTheme.titleMedium),
        Text(c.text('sequenceEditHint')),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final (index, frame) in _frames.indexed) _square(index, frame),
        ]),
        const SizedBox(height: 8),
        Text(c.text('sequenceReorderHint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
          OutlinedButton(key: const Key('scene-add-color'),
            onPressed: _busy || _frames.length >= maxColors ? null : () => setState(() {
              _selected = _Frame(_frames.last.rgb);
              _frames.add(_selected);
            }), child: Text(c.text('addColor'))),
          OutlinedButton(key: const Key('scene-remove-color'),
            onPressed: _busy || _frames.length <= 1 ? null : () => setState(() {
              final index = _frames.indexOf(_selected);
              _frames.removeAt(index);
              _selected = _frames[index.clamp(0, _frames.length - 1)];
            }), child: Text(c.text('removeColor'))),
        ]),
        const SizedBox(height: 14),
        _wheel(),
        const SizedBox(height: 8),
        ExpansionTile(title: Text(c.text('favorites')), tilePadding: EdgeInsets.zero, children: [
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final hex in c.models.loadPalette())
              IconButton.outlined(tooltip: c.text('paletteColorHex', {'hex': hex.toUpperCase()}),
                onPressed: _busy ? null : () => _setColor([
                  for (var i = 1; i < 7; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
                ]), icon: Icon(Icons.circle, color: Color(0xff000000 | int.parse(hex.substring(1), radix: 16)))),
          ]),
        ]),
        const SizedBox(height: 14),
        _SceneSlider(controller: c, id: 'scene-speed', label: 'speed', value: _speed,
          onChanged: (value) => setState(() { _speed = value; _interval = intervalFromSpeed(value); })),
        _SceneSlider(controller: c, id: 'scene-intensity', label: 'intensity', min: 1,
          value: _intensity, onChanged: (value) => setState(() => _intensity = value)),
        const SizedBox(height: 8),
        Text(c.text('foregroundPlaybackHint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _LastSent(transport: widget.transport),
        if (widget.transport.failed) Text(c.text('commandFailed')),
        if (_id != null) Align(alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(key: const Key('scene-delete'), onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline), label: Text(c.text('deleteSequence')))),
      ]))),
      Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 10), child: Wrap(
        alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
        TextButton(key: const Key('scene-close'), onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(c.text('close'))),
        TextButton(key: const Key('scene-start'), onPressed: !_busy && widget.transport.ready ? () {
          List<List<int>> colors() => [for (final frame in _frames) frame.rgb];
          unawaited(widget.transport.playColors(colors(), _interval, _intensity,
            draft: () => (colors: colors(), interval: _interval, intensity: _intensity)));
        } : null, child: Text(c.text('playSequence'))),
        TextButton(key: const Key('scene-stop'), onPressed: widget.transport.previewing
          ? widget.transport.stopPreview : null, child: Text(c.text('stopSequence'))),
        FilledButton(key: const Key('scene-save'), onPressed: _busy ? null : _save,
          child: Text(c.text('saveSequence'))),
      ])),
      ])),
    ));
}
