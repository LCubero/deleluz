// Keeps docs/EFFECTS.md in step with the in-app effect catalog.
import 'dart:io';

import 'package:deleluz/model/effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('docs/EFFECTS.md lists every built-in effect in app order', () {
    final rows = File('../docs/EFFECTS.md').readAsLinesSync()
        .map(RegExp(r'^\| (\d+) \| (.+) \|$').firstMatch)
        .whereType<RegExpMatch>()
        .map((m) => (int.parse(m.group(1)!), m.group(2)!))
        .toList();
    expect(rows, hasLength(210));
    for (var i = 0; i < rows.length; i++) {
      expect(rows[i], (i + 1, effectName(i + 1)));
    }
  });
}
