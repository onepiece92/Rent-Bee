import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web backend: sqlite3 compiled to WASM, persisted by the browser (OPFS where
/// available, falling back to IndexedDB). Requires `sqlite3.wasm` and
/// `drift_worker.js` to be served from the web root (see `web/`).
///
/// Like the native backend, the web ledger is not encrypted at rest; browser
/// storage is protected by the origin sandbox.
Future<QueryExecutor> openLedgerExecutor() async {
  final result = await WasmDatabase.open(
    databaseName: 'unit_ledger',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  // Surface fallbacks (e.g. no OPFS / shared-worker support) during dev so a
  // silently slower or non-persistent store doesn't go unnoticed.
  if (result.missingFeatures.isNotEmpty) {
    // ignore: avoid_print
    print('drift/wasm: degraded storage, missing: ${result.missingFeatures}');
  }
  return result.resolvedExecutor;
}
