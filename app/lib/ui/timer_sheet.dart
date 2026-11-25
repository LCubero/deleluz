import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/timer.dart';
import 'glow_glass.dart';
import 'glow_sheet.dart';
import 'notice.dart';

class TimerSheet extends StatefulWidget {
  const TimerSheet({super.key, required this.controller});
  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) =>
      GlowSheet.open<void>(context, showDragHandle: true,
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
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                if (c.message == 'timerOffFailed') ...[
                  Notice(c.text('timerOffFailed'), kind: NoticeKind.error, live: true),
                  OutlinedButton(onPressed: c.canRetryTimerOff ? c.retryTimerOff : null,
                    child: Text(c.text('retryTimerOff'))),
                ],
                if (remaining != null && end != null) ...[
                  LayoutBuilder(builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(24) / 24;
                    final diameter = (112 * scale + 32).clamp(144.0, math.max(144.0, constraints.maxWidth)).toDouble();
                    return Center(child: SizedBox.square(dimension: diameter, child: CustomPaint(
                      painter: _CountdownRing(c.timerFraction),
                      child: Padding(padding: const EdgeInsets.all(20), child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(formatCountdown(remaining), style: style.headlineSmall, textAlign: TextAlign.center),
                          Text(c.text('timerRemaining'), style: style.bodySmall, textAlign: TextAlign.center),
                        ])),
                    )));
                  }),
                  const SizedBox(height: 8),
                  Text(c.text('timerEndsAt', {'time': _clockTime(end)}), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
                    for (final minutes in [5, 15])
                      OutlinedButton(onPressed: c.canExtendTimer(minutes * 60)
                           ? () => c.extendTimer(minutes * 60) : null,
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
                    child: Notice(c.text('invalidTimer'), kind: NoticeKind.error, live: true)),
                  const SizedBox(height: 8),
                  Material(color: glowGlass, shape: RoundedRectangleBorder(
                    side: const BorderSide(color: glowLine), borderRadius: BorderRadius.circular(16)),
                    child: SwitchListTile(title: Text(c.text('fade')), value: _fade,
                      onChanged: (value) => setState(() => _fade = value))),
                  const SizedBox(height: 8),
                  if (!c.ready) Notice(c.text('connectFirst'), kind: NoticeKind.warning),
                  GlowPrimaryButton(onPressed: c.canSend ? _start : null, label: Text(c.text('startTimer'))),
                ],
                const SizedBox(height: 8),
                Notice(c.text('timerNote')),
              ],
            ),
          )),
      );
    });

  GlowChoice _choice(int? duration, String label) => GlowChoice(choiceKey: Key('timer-$label'),
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
    final radius = size.shortestSide / 2 - 6;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xff1b1436));
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 10;
    canvas.drawCircle(center, radius, stroke..color = glowMuted.withValues(alpha: .35));
    stroke.strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * fraction.clamp(0, 1);
    if (sweep <= 0) return;
    stroke.shader = SweepGradient(colors: glowProgressGradient.colors, endAngle: sweep,
      transform: const GradientRotation(-math.pi / 2)).createShader(bounds);
    canvas.drawArc(bounds, -math.pi / 2, sweep, false, stroke);
  }

  @override
  bool shouldRepaint(_CountdownRing oldDelegate) => oldDelegate.fraction != fraction;
}
