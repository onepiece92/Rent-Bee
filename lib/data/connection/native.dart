import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native backend: a plain on-disk SQLite file in the app documents directory.
///
/// Not encrypted at rest and uses no platform keychain — access is controlled
/// by the device/app sandbox plus the PIN UI lock (see `AuthProvider`). If
/// at-rest encryption is needed later, reintroduce a cipher build keyed from a
/// secure store.
Future<QueryExecutor> openLedgerExecutor() async {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'unit_ledger.sqlite'));
    return NativeDatabase(file);
  });
}
