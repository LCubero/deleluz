import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/models.dart';
import 'color/favorites.dart';
import 'color_disc.dart';
import 'glow_glass.dart';
import 'notice.dart';

/// Selects a color without deciding whether to preview, save, or send it.
class SharedColorPicker extends StatelessWidget {
  const SharedColorPicker({super.key = const Key('shared-color-picker'),
    required this.controller, required this.rgb, required this.onChanged,
    this.showDiscHint = true});

  final AppController controller;
  final List<int> rgb;
  final bool showDiscHint;
  final void Function(List<int> rgb, String? name) onChanged;

  static const neutral = [255, 228, 196];
  static const _whites = [
    ('whiteWarmTone', 'warmWhite', [255, 200, 128]),
    ('whiteNeutralTone', 'whiteNeutralTone', neutral),
    ('whiteCoolTone', 'coolWhite', [255, 255, 255]),
  ];

  static Color _color(List<int> rgb) => Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);

  static String? _favoriteName(String hex) {
    for (final (_, name, rgb) in _whites) {
      if (rgbHex(rgb).toLowerCase() == hex) return name;
    }
    // Keep the label for existing palette entries without offering a preset.
    if (hex == '#200400') return 'night';
    final name = colorName(hex);
    return name == 'solid' ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final current = rgbHex(rgb).toLowerCase();
    Widget chip((String, String, List<int>) preset) {
      final (label, name, tone) = preset;
      return GlowChoice(
        avatar: CircleAvatar(backgroundColor: _color(tone)),
        label: Text(controller.text(label)),
        selected: current == rgbHex(tone).toLowerCase(),
        onSelected: (_) => onChanged(tone, name),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ColorDisc(color: _color(rgb), label: controller.text('colorDiscLabel'),
        onChanged: (hsv) {
        final selected = hsv.toColor().toARGB32();
        onChanged([(selected >> 16) & 255, (selected >> 8) & 255, selected & 255], null);
      }),
      if (showDiscHint) Notice(controller.text('colorDiscHint'), compact: true),
      const SizedBox(height: 12),
      Semantics(container: true, explicitChildNodes: true, label: controller.text('whiteTones'),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
          for (final preset in _whites) chip(preset),
        ])),
      const SizedBox(height: 12),
      ColorFavorites(controller: controller, current: current, nameFor: _favoriteName,
        onColor: onChanged),
    ]);
  }
}
