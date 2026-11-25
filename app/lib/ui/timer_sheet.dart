import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/timer.dart';
import 'glow_glass.dart';

class TimerSheet extends StatefulWidget {
  const TimerSheet({super.key, required this.controller});
  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) =>
      showModalBottomSheet<void>(context: context, isScrollControlled: true,
        useSafeArea: true, showDragHandle: true, clipBehavior: Clip.antiAlias,
        builder: (_) => TimerSheet(controller: controller));

  @override
  State<TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<TimerSheet> {
  static const _presets = {900: 'minutes15', 1800: 'minutes30',
    3600: 'hour1', 7200: 'hours2'};
  AppController get c => widget.controller;
  late int? _preset;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  bool _fade = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    final duration = c.lastTimerDuration;
    _preset = _presets.containsKey(duration) ? duration : null;
    _minutes = TextEditingController(text: _preset == null ? '${duration ~/ 60}' : '');
    _seconds = TextEditingController(text: _preset == null ? '${duration % 60}' : '');
  }

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _start() {
    final duration = _preset ?? parseTimerDuration(_minutes.text, _seconds.text);
    if (duration == null) {
      setState(() => _invalid = true);
      return;
    }
    FocusScope.of(context).unfocus();
    c.startTimer(duration, fade: _fade);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c,
    builder: (context, _) {
      final style = Theme.of(context).textTheme;
      final remaining = c.remaining;
      final end = c.timerEndTime;
      return Ink(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xff201840), Color(0xff120e26)])),
        child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(top: false, child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text(c.text('offTimer'), style: style.titleLarge, softWrap: true)),
                  IconButton(tooltip: c.text('close'), icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 12),
                if (remaining != null && end != null) ...[
                  Center(child: SizedBox.square(dimension: 144, child: CustomPaint(
                    painter: _CountdownRing(c.timerFraction),
                    child: Padding(padding: const EdgeInsets.all(17), child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, children: [
                        FittedBox(fit: BoxFit.scaleDown,
                          child: Text(formatCountdown(remaining), style: style.headlineSmall)),
                        FittedBox(fit: BoxFit.scaleDown,
                          child: Text(c.text('timerRemaining'), style: style.bodySmall)),
                      ])),
                  ))),
                  const SizedBox(height: 8),
                  Text(c.text('timerEndsAt', {'time': _clockTime(end)}), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
                    for (final minutes in [5, 15])
                      OutlinedButton(onPressed: () => c.extendTimer(minutes * 60),
                        child: Text(c.text('timerAddMinutes', {'minutes': minutes}))),
                    TextButton(onPressed: () => c.cancelTimer(restoreBrightness: true),
                      child: Text(c.text('cancelTimer'))),
                  ]),
                ] else ...[
                  Text(c.text('timerDuration'), style: style.titleSmall),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final MapEntry(key: duration, value: label) in _presets.entries)
                      _choice(duration, label),
                    _choice(null, 'custom'),
                  ]),
                  if (_preset == null) ...[
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _field('minutes', _minutes)),
                      const SizedBox(width: 8),
                      Expanded(child: _field('seconds', _seconds)),
                    ]),
                  ],
                  if (_invalid) Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text(c.text('invalidTimer'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 8),
                  Material(color: glowGlass, shape: RoundedRectangleBorder(
                    side: const BorderSide(color: glowLine), borderRadius: BorderRadius.circular(16)),
                    child: SwitchListTile(title: Text(c.text('fade')), value: _fade,
                      onChanged: (value) => setState(() => _fade = value))),
                  const SizedBox(height: 8),
                  if (!c.ready) Text(c.text('connectFirst'), style: style.bodySmall),
                  FilledButton(onPressed: c.canSend ? _start : null, child: Text(c.text('startTimer'))),
                ],
                const SizedBox(height: 8),
                Text(c.text('timerNote'), style: style.bodySmall),
              ],
            ),
          )),
        ),
      );
    });

  ChoiceChip _choice(int? duration, String label) => ChoiceChip(
    label: Text(c.text(label)), selected: _preset == duration,
    onSelected: (_) => setState(() { _preset = duration; _invalid = false; }),
  );

  TextField _field(String label, TextEditingController controller) => TextField(
    controller: controller, decoration: InputDecoration(labelText: c.text(label)),
    keyboardType: TextInputType.number,
    onChanged: (_) { if (_invalid) setState(() => _invalid = false); },
  );
}

String _clockTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class _CountdownRing extends CustomPainter {
  const _CountdownRing(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xff1b1436));
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 7;
    canvas.drawCircle(center, radius, stroke..color = glowLine);
    stroke.shader = const SweepGradient(colors: [glowViolet, glowPink],
      transform: GradientRotation(-math.pi / 2)).createShader(bounds);
    canvas.drawArc(bounds, -math.pi / 2, 2 * math.pi * fraction.clamp(0, 1), false, stroke);
  }

  @override
  bool shouldRepaint(_CountdownRing oldDelegate) => oldDelegate.fraction != fraction;
}
