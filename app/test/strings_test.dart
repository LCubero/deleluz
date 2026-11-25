import 'package:deleluz/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Spanish and English dictionaries have identical nonempty entries', () {
    final es = dictionaries['es']!;
    final en = dictionaries['en']!;
    expect(es, isNotEmpty);
    expect(es.keys.toSet(), en.keys.toSet());
    for (final value in [...es.values, ...en.values]) {
      expect(value.trim(), isNotEmpty);
    }
  });

  test('interpolation is single-pass and leaves missing variables intact', () {
    expect(translate('en', 'effectNumber', {'id': 12}), 'Effect 12');
    expect(translate('es', 'effectNumber', {'id': 12}), 'Efecto 12');
    expect(translate('es', 'onLabel', {'label': 'Mi escena {id}'}),
        'Encendido · Mi escena {id}');
    expect(translate('en', 'effectNumber'), 'Effect {id}');
    expect(translate('en', '<img src=x> {id}'), '<img src=x> {id}');
    expect(translate('es', '__proto__'), '__proto__');
    expect(translate('es', 'percent', {'value': 10}), '10\u00a0%');
  });

  test('scene editor and palette messages are localized', () {
    expect(translate('es', 'renameSequence'), 'Cambiar nombre');
    expect(translate('en', 'renameSequence'), 'Rename');
    expect(translate('es', 'sequenceNameTooLong', {'max': 24}),
        'Usa un nombre de hasta 24 caracteres.');
    expect(translate('en', 'sequenceNameTooLong', {'max': 24}),
        'Use a name with up to 24 characters.');
    expect(translate('es', 'sequenceName', {'number': 2}), 'Secuencia 2');
    expect(translate('en', 'sequenceName', {'number': 2}), 'Sequence 2');
    expect(translate('en', 'sequenceFrame', {'number': 3, 'hex': '#00FF00'}),
        'Square 3: #00FF00');
    expect(translate('en', 'paletteFull'),
        'You already have 15 colors. Tap one to replace it.');
    expect(translate('es', 'paletteColorHex', {'hex': '#ABCDEF'}),
        'Color fijo #ABCDEF');
    expect(translate('en', 'paletteColorHex', {'hex': '#ABCDEF'}),
        'Solid color #ABCDEF');
  });
}
