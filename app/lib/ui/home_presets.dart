// Foreground page scenes from lab/web/presets.js, not controller effects.
typedef HomePreset = ({int interval, List<List<int>> colors});
const _red = [255, 0, 0], _green = [0, 255, 0], _blue = [0, 0, 255];
const _black = [0, 0, 0], _white = [255, 255, 255], _warm = [255, 200, 128];

List<List<int>> _cycle(List<List<int>> anchors, int steps) => [
  for (var i = 0; i < anchors.length; i++)
    for (var step = 0; step < steps; step++)
      List.generate(3, (channel) {
        final from = anchors[i][channel];
        final to = anchors[(i + 1) % anchors.length][channel];
        return (from + (to - from) * step / steps).round();
      }),
];

// Presentation-only stops from PRESET_SW in webapp/app.js; playback uses the frames below.
List<List<int>> presetPreviewColors(String id) => switch (id) {
  'christmas-moving' => const [[239, 68, 68], [34, 197, 94], [255, 247, 230]],
  'police' => const [[239, 68, 68], [59, 130, 246]],
  'rasta' => const [[34, 197, 94], [250, 204, 21], [239, 68, 68]],
  'flashing' => const [[255, 255, 255]],
  _ => const [[239, 68, 68], [79, 70, 229]],
};

final homePresets = <String, HomePreset>{
  'christmas-moving': (interval: 200, colors: _cycle([_red, _green, _warm], 8)),
  'christmas-glow': (interval: 300, colors: _cycle([
    [64, 0, 0], _red, [64, 0, 0], [0, 64, 0], _green, [0, 64, 0],
  ], 6)),
  'police': (interval: 180, colors: [_red, _black, _red, _blue, _black, _blue, _black]),
  'siren': (interval: 150, colors: _cycle([_red, _blue], 12)),
  'rasta': (interval: 650, colors: [_green, [255, 255, 0], _red]),
  'flashing': (interval: 500, colors: [_white, _black]),
};
