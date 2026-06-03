// Resolves the drift QueryExecutor backend at compile time: the native
// SQLCipher file on the Dart VM (mobile/desktop), or the sqlite3 WASM build on
// web. `database.dart` calls `openLedgerExecutor()` without caring which.
export 'native.dart' if (dart.library.js_interop) 'web.dart';
