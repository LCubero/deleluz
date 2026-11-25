import 'dart:io';

import 'package:deleluz/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app version matches the pubspec version name', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:[ \t]*([^+\s]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(version?.group(1), appVersion);
  });
}
