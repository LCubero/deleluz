// Controller ID order, as recorded in webapp/effects.js.
const effectNames = [
  'Forward Dreaming',
  'Backward Dreaming',
  'Forward 7 Colors',
  'Backward 7 Colors',
  'Forward RD/GN/BU',
  'Backward RD/GN/BU',
  'Forward YE/CN/VT',
  'Backward YE/CN/VT',
  'Forward 6 Colors RD',
  'Backward 6 Colors RD',
  'Forward 6 Colors GN',
  'Backward 6 Colors GN',
  'Forward 6 Colors BU',
  'Backward 6 Colors BU',
  'Forward 6 Colors CN',
  'Backward 6 Colors CN',
  'Forward 6 Colors YE',
  'Backward 6 Colors YE',
  'Forward 6 Colors VT',
  'Backward 6 Colors VT',
  'Forward 6 Colors WH',
  'Backward 6 Colors WH',
  'Forward Trailing 7 Colors',
  'Backward Trailing 7 Colors',
  'Forward Trailing RD',
  'Backward Trailing RD',
  'Forward Trailing GN',
  'Backward Trailing GN',
  'Forward Trailing BU',
  'Backward Trailing BU',
  'Forward Trailing YE',
  'Backward Trailing YE',
  'Forward Trailing CN',
  'Backward Trailing CN',
  'Forward Trailing VT',
  'Backward Trailing VT',
  'Forward Trailing WH',
  'Backward Trailing WH',
  'Forward Streaming 7 Colors',
  'Backward Streaming 7 Colors',
  'Forward Streaming RD/GN/BU',
  'Backward Streaming RD/GN/BU',
  'Forward Streaming YE/CN/VT',
  'Backward Streaming YE/CN/VT',
  'Forward Streaming RD/GN',
  'Backward Streaming RD/GN',
  'Forward Streaming GN/BU',
  'Backward Streaming GN/BU',
  'Forward Streaming YE/BU',
  'Backward Streaming YE/BU',
  'Forward Streaming YE/CN',
  'Backward Streaming YE/CN',
  'Forward Streaming CN/VT',
  'Backward Streaming CN/VT',
  'Forward Streaming BK/WH',
  'Backward Streaming BK/WH',
  'Open Curtain 7 Colors',
  'Close Curtain 7 Colors',
  'Open Curtain RD/GN/BU',
  'Close Curtain RD/GN/BU',
  'Open Curtain YE/CN/VT',
  'Close Curtain YE/CN/VT',
  'Forward Follow Spot 7 Colors',
  'Backward Follow Spot 7 Colors',
  'Forward Follow Spot RD/GN/BU',
  'Backward Follow Spot RD/GN/BU',
  'Forward Follow Spot YE/CN/VT',
  'Backward Follow Spot YE/CN/VT',
  'Forward Flutter 7 Colors',
  'Backward Flutter 7 Colors',
  'Forward Flutter RD/GN/BU',
  'Backward Flutter RD/GN/BU',
  'Forward Flutter BU/YE/CN',
  'Backward Flutter BU/YE/CN',
  'Forward Flutter CN/VT/WH',
  'Backward Flutter CN/VT/WH',
  'Hop 7 Colors',
  'Hop RD/GN/BU',
  'Hop YE/CN/VT',
  'Strobe White',
  'Forward Horse Race 7 Colors',
  'Backward Horse Race 7 Colors',
  'Forward Horse Race RD/GN/BU',
  'Backward Horse Race RD/GN/BU',
  'Forward Horse Race YE/CN/VT',
  'Backward Horse Race YE/CN/VT',
  'Forward Horse Race YE',
  'Backward Horse Race YE',
  'Forward Horse Race CN',
  'Backward Horse Race CN',
  'Forward Horse Race VT',
  'Backward Horse Race VT',
  'Forward Horse Race WH',
  'Backward Horse Race WH',
  'Forward Run 7 Colors',
  'Backward Run 7 Colors',
  'Forward Run RD',
  'Backward Run RD',
  'Forward Run GN',
  'Backward Run GN',
  'Forward Run BU',
  'Backward Run BU',
  'Forward Run YE',
  'Backward Run YE',
  'Forward Run CN',
  'Backward Run CN',
  'Forward Run VT',
  'Backward Run VT',
  'Forward Run WH',
  'Backward Run WH',
  'Forward Run RD/GN',
  'Backward Run RD/GN',
  'Forward Run GN/BU',
  'Backward Run GN/BU',
  'Forward Run BU/YE',
  'Backward Run BU/YE',
  'Forward Run YE/CN',
  'Backward Run YE/CN',
  'Forward Run CN/VT',
  'Backward Run CN/VT',
  'Forward Run VT/WH',
  'Backward Run VT/WH',
  'Forward Flow 7 Colors',
  'Backward Flow 7 Colors',
  'Forward Flow RD/GN/RD',
  'Backward Flow RD/GN/RD',
  'Forward Flow BU/GN/BU',
  'Backward Flow BU/GN/BU',
  'Forward Flow YE/GN/YE',
  'Backward Flow YE/GN/YE',
  'Forward Flow YE/CN/YE',
  'Backward Flow YE/CN/YE',
  'Forward Flow VT/CN/VT',
  'Backward Flow VT/CN/VT',
  'Forward Flow WH/VT/WH',
  'Backward Flow WH/VT/WH',
  'Forward Run 7 Colors ON WH',
  'Backward Run 7 Colors ON WH',
  'Forward Run RD ON WH',
  'Backward Run RD ON WH',
  'Forward Run GN ON WH',
  'Backward Run GN ON WH',
  'Forward Run BU ON WH',
  'Backward Run BU ON WH',
  'Forward Run YE ON GN',
  'Backward Run YE ON GN',
  'Forward Run CN ON RD',
  'Backward Run CN ON RD',
  'Forward Run VT ON BU',
  'Backward Run VT ON BU',
  'Forward Run YE ON WH',
  'Backward Run YE ON WH',
  'Close Curtain 7 COLOR',
  'Open Curtain 7 COLOR',
  'Close Curtain RD',
  'Open Curtain RD',
  'Close Curtain GN',
  'Open Curtain GN',
  'Close Curtain BU',
  'Open Curtain BU',
  'Close Curtain YE',
  'Open Curtain YE',
  'Close Curtain CN',
  'Open Curtain CN',
  'Close Curtain VT',
  'Open Curtain VT',
  'Close Curtain WH',
  'Open Curtain WH',
  'Close Curtain 7 Colors ON YE',
  'Open Curtain 7 Colors ON YE',
  'Close Curtain RD/GN/BU ON CN',
  'Open Curtain RD/GN/BU ON CN',
  'Close Curtain YE/CN/VT ON VT',
  'Open Curtain YE/CN/VT ON VT',
  'Forward Flow RD/GN/BU/YE',
  'Backward Flow RD/GN/BU/YE',
  'Forward Flow GN/BU/YE/CN',
  'Backward Flow GN/BU/YE/CN',
  'Forward Flow BU/YE/CN/VT',
  'Backward Flow BU/YE/CN/VT',
  'Forward Flow YE/CN/VT/WH',
  'Backward Flow YE/CN/VT/WH',
  'Forward Swab 7 COLORS',
  'Backward Swab 7 COLORS',
  'Forward Swab RD/GN/BU',
  'Backward Swab RD/GN/BU',
  'Forward Swab YE/CN/VT',
  'Backward Swab YE/CN/VT',
  'Forward Swab RD',
  'Backward Swab RD',
  'Forward Swab GN',
  'Backward Swab GN',
  'Forward Swab BU',
  'Backward Swab BU',
  'Forward Swab YE',
  'Backward Swab YE',
  'Forward Swab CN',
  'Forward Swab CN',
  'Forward Swab VT',
  'Forward Swab VT',
  'Forward Swab WH',
  'Forward Swab WH',
  'Open Curtain Swab 7 COLORS',
  'Close Curtain Swab 7 COLORS',
  'Open Curtain Swab RD/GN/BU',
  'Close Curtain Swab RD/GN/BU',
  'Open Curtain Swab BU/YE',
  'Close Curtain Swab BU/YE',
  'Open Curtain Swab CN/VT',
  'Close Curtain Swab CN/VT',
];

String? effectName(Object? id, {String language = 'en'}) =>
    id is num && id >= 1 && id <= effectNames.length && id == id.truncate()
    ? (language == 'es' ? _spanishNames : effectNames)[id.toInt() - 1]
    : null;

const _spanishOverrides = {
  1: 'Sueño hacia adelante',
  2: 'Sueño hacia atrás',
  80: 'Estrobo blanco',
  // The controller catalog repeats these labels (or only changes casing).
  // Distinguish the IDs without assuming how the animations differ.
  153: 'Cierre de 7 colores (2)',
  154: 'Apertura de 7 colores (2)',
  198: 'Barrido cian directo (2)',
  200: 'Barrido violeta directo (2)',
  202: 'Barrido blanco directo (2)',
};

const _motion = {
  'TRAILING': 'Estela',
  'STREAMING': 'Corriente',
  'FOLLOW SPOT': 'Foco móvil',
  'FLUTTER': 'Aleteo',
  'HORSE RACE': 'Galope',
  'RUN': 'Carrera',
  'FLOW': 'Flujo',
  'SWAB': 'Barrido',
};

const _colors = {
  'RD': 'rojo', 'GN': 'verde', 'BU': 'azul', 'YE': 'amarillo',
  'CN': 'cian', 'VT': 'violeta', 'WH': 'blanco', 'BK': 'negro',
};

final _spanishNames = List.generate(effectNames.length, (index) =>
    _spanishOverrides[index + 1] ?? _translateEffect(effectNames[index]));

String _translateEffect(String name) {
  var rest = name.toUpperCase();
  var suffix = '';
  var title = '';
  for (final (prefix, direction) in [('FORWARD ', 'directo'), ('BACKWARD ', 'inverso')]) {
    if (rest.startsWith(prefix)) {
      rest = rest.substring(prefix.length);
      for (final entry in _motion.entries) {
        if (rest.startsWith('${entry.key} ')) {
          title = entry.value;
          rest = rest.substring(entry.key.length + 1);
          break;
        }
      }
      if (title.isEmpty) title = 'Ciclo';
      final feminine = const {'Estela', 'Corriente', 'Carrera'}.contains(title);
      suffix = ' ${feminine ? '${direction.substring(0, direction.length - 1)}a' : direction}';
      break;
    }
  }
  if (title.isEmpty) {
    for (final (prefix, label) in [
      ('OPEN CURTAIN SWAB ', 'Barrido de apertura'),
      ('CLOSE CURTAIN SWAB ', 'Barrido de cierre'),
      ('OPEN CURTAIN ', 'Apertura'),
      ('CLOSE CURTAIN ', 'Cierre'),
      ('HOP ', 'Saltos'),
    ]) {
      if (rest.startsWith(prefix)) {
        title = label;
        rest = rest.substring(prefix.length);
        break;
      }
    }
  }
  final palette = rest.split(' ON ');
  final foreground = palette.first;
  final shades = switch (foreground) {
    '7 COLORS' || '7 COLOR' => 'de 7 colores',
    _ when foreground.startsWith('6 COLORS ') =>
      'de 6 colores (${_colors[foreground.substring('6 COLORS '.length)]!})',
    _ => foreground.split('/').map((code) => _colors[code]!).join(' / '),
  };
  final background = palette.length == 2 ? ' sobre ${_colors[palette.last]!}' : '';
  return '$title $shades$suffix$background';
}
