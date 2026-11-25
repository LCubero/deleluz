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
