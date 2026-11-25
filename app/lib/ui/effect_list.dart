import 'package:material_ui/material_ui.dart';

import '../model/effects.dart';
import 'notice.dart';

/// Shared catalog; the caller decides what selecting an effect does.
class EffectList extends StatefulWidget {
  const EffectList({super.key, required this.favorites, required this.text,
    required this.onFavorite, this.selected, this.onSelected});

  final Set<int> favorites;
  final String Function(String, [Map<String, Object?>]) text;
  final ValueChanged<int> onFavorite;
  final int? selected;
  final ValueChanged<int>? onSelected;

  @override
  State<EffectList> createState() => _EffectListState();
}

class _EffectListState extends State<EffectList> {
  final _scroll = ScrollController();
  String _query = '';

  static final _accents = {
    RegExp('[àáâãäåāăą]'): 'a', RegExp('[çćĉċč]'): 'c',
    RegExp('[èéêëēĕėęě]'): 'e', RegExp('[ìíîïĩīĭį]'): 'i',
    RegExp('[ñńņň]'): 'n', RegExp('[òóôõöøōŏő]'): 'o',
    RegExp('[ùúûüũūŭůűų]'): 'u', RegExp('[ýÿŷ]'): 'y',
    RegExp(r'[\u0300-\u036f]'): '',
  };
  static String _fold(String value) => _accents.entries.fold(value.toLowerCase(),
    (text, accent) => text.replaceAll(accent.key, accent.value));
  static final _names = effectNames.map(_fold).toList();
  static String _number(int id) => '$id'.padLeft(2, '0');

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starred = <int>[];
    final others = <int>[];
    for (var id = 1; id <= _names.length; id++) {
      if (_names[id - 1].contains(_query) || _number(id).contains(_query)) {
        (widget.favorites.contains(id) ? starred : others).add(id);
      }
    }
    final entries = <Object>[
      if (starred.isNotEmpty) ...['favorites', ...starred],
      if (others.isNotEmpty) ...['effectCatalogAll', ...others],
    ];
    final style = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.text('effectCatalog'), style: style.titleMedium),
      const SizedBox(height: 8),
      TextField(key: const Key('effect-search'), textInputAction: TextInputAction.search,
        decoration: InputDecoration(border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search), labelText: widget.text('effectSearch')),
        onChanged: (value) {
          if (_scroll.hasClients) _scroll.jumpTo(0);
          setState(() => _query = _fold(value.trim()));
        }),
      const SizedBox(height: 8),
      if (entries.isEmpty) Notice(widget.text('effectSearchEmpty')) else
        SizedBox(height: 270, child: Scrollbar(controller: _scroll,
          child: ListView.builder(controller: _scroll, padding: EdgeInsets.zero,
            itemCount: entries.length, itemBuilder: (context, index) {
              final entry = entries[index];
              if (entry is String) {
                return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(header: true, child: Text(widget.text(entry), style: style.titleSmall)));
              }
              final id = entry as int;
              final name = effectNames[id - 1];
              final favorite = widget.favorites.contains(id);
              return ListTile(key: Key('effect-row-$id'), contentPadding: EdgeInsets.zero,
                selected: widget.selected == id,
                title: Text('${_number(id)} · $name'),
                onTap: widget.onSelected == null ? null : () {
                  FocusScope.of(context).unfocus();
                  widget.onSelected!(id);
                },
                trailing: Semantics(toggled: favorite, child: SizedBox.square(dimension: 48,
                  child: IconButton(key: Key('effect-star-$id'),
                    tooltip: widget.text('effectFavorite', {'name': name}),
                    icon: Icon(favorite ? Icons.star : Icons.star_border),
                    onPressed: () => widget.onFavorite(id)),
                )),
              );
            }),
        )),
    ]);
  }
}
