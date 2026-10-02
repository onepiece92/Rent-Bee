import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native backend: a plain on-disk SQLite file in the app documents directory,
/// driven from a background isolate so no query — a month refresh, opening a
/// unit sheet, a year report — ever stalls the UI thread.
///
/// Not encrypted at rest and uses no platform keychain — access is controlled
/// by the device/app sandbox plus the PIN UI lock (see `AuthProvider`). If
/// at-rest encryption is needed later, reintroduce a cipher build keyed from a
/// secure store.
Future<QueryExecutor> openLedgerExecutor() async {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'unit_ledger.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      // WAL + synchronous=NORMAL: commits no longer pay a full fsync each (the
      // default rollback journal does), and reads don't wait on a write. WAL
      // is still durable across an app crash; NORMAL can lose only the last
      // commits on a power cut, and never corrupts the file.
      setup: (db) {
        db.execute('PRAGMA journal_mode = WAL;');
        db.execute('PRAGMA synchronous = NORMAL;');
      },
    );
  });
}
