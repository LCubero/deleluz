import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/effects.dart';
import '../../model/models.dart';
import '../glow_glass.dart';

class AppAutoCard extends StatelessWidget {
  const AppAutoCard({super.key, required this.controller, required this.onStart});

  final AppController controller;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = Theme.of(context).textTheme;
    final playing = c.appAutoPlaying;
    final hasFavorites = c.effectFavorites.isNotEmpty;
    final id = c.appAutoEffect;
    final current = id == null ? null : '${'$id'.padLeft(2, '0')} · ${effectName(id)}';
    final progress = c.appAutoProgress;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(c.text('appAuto'), style: style.titleMedium)),
      if (current != null) ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, label: c.text('appAutoCurrent', {'effect': current}),
          excludeSemantics: true, child: Text(current, key: const Key('app-auto-current'),
            style: style.titleLarge)),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(key: ValueKey(c.appAutoStep),
          tween: Tween(begin: progress, end: 1.0),
          duration: Duration(milliseconds: ((1 - progress) * c.appAutoSeconds * 1000).round()),
          builder: (context, value, _) => LinearProgressIndicator(value: value,
            semanticsLabel: c.text('appAutoProgress'),
            semanticsValue: c.text('percent', {'value': (value * 100).round()}))),
      ],
      const SizedBox(height: 8),
      Text(c.text('appAutoDuration')),
      Wrap(spacing: 8, children: [
        for (final seconds in Models.appAutoDurations)
          ChoiceChip(key: Key('app-auto-$seconds'),
            label: Text(seconds < 60
                ? c.text('durationShortSeconds', {'value': seconds})
                : c.text('durationShortMinutes', {'value': seconds ~/ 60})),
            selected: c.appAutoSeconds == seconds,
            onSelected: playing ? null : (_) => c.setAppAutoOptions(seconds: seconds)),
      ]),
      const SizedBox(height: 8),
      Text(c.text('appAutoList')),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: Text(c.text('appAutoAll')), selected: !c.appAutoFavorites,
          onSelected: playing ? null : (_) => c.setAppAutoOptions(favorites: false)),
        ChoiceChip(key: const Key('app-auto-favorites'), label: Text(c.text('favorites')),
          selected: c.appAutoFavorites,
          onSelected: playing || !hasFavorites ? null : (_) => c.setAppAutoOptions(favorites: true)),
      ]),
      if (!hasFavorites) Text(c.text('appAutoFavoritesHint'), style: style.bodySmall),
      const SizedBox(height: 8),
      FilledButton.icon(key: const Key('app-auto-toggle'),
        onPressed: playing ? c.stopAppAuto : (c.canSend && (!c.appAutoFavorites || hasFavorites)) ? () {
          FocusScope.of(context).unfocus();
          onStart();
          unawaited(c.startAppAuto());
        } : null,
        icon: Icon(playing ? Icons.stop : Icons.play_arrow),
        label: Text(c.text(playing ? 'appAutoStop' : 'appAutoStart'))),
      const SizedBox(height: 4),
      Text(c.text('appAutoNote'), style: style.bodySmall),
    ]));
  }
}
