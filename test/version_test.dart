import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/app/version.dart';

/// Settings shows `appVersion`; it used to be a hard-coded "v1.0.0 · offline"
/// that no release ever updated. (buglog B23.)
void main() {
  test('the version shown in Settings matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
            multiLine: true)
        .firstMatch(pubspec)!
        .group(1);
    expect(appVersion, declared,
        reason: 'bump lib/app/version.dart together with pubspec.yaml');
  });
}
