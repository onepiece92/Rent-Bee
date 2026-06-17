import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/auth_provider.dart';
import 'firestore_sync_service.dart';
import 'ledger_repository.dart';
import 'phone_auth_service.dart';

/// Brings cloud sync online for a signed-in owner, *after* unlock and off the
/// cold-start path (so a PIN-only launch stays fast). Returns the live service,
/// or null when sync should not run (guest session, or no restored Firebase
/// session — in which case the app keeps working local-only).
///
/// Firestore security rules require a real authenticated user, so we must wait
/// for FirebaseAuth to restore the persisted session before issuing any reads.
Future<FirestoreSyncService?> startSync({
  required LedgerRepository repo,
  required SharedPreferences prefs,
  required AuthProvider auth,
  required VoidCallback onApply,
}) async {
  if (auth.isGuest || !auth.phoneVerified) return null;

  await PhoneAuthService.ensureInitialized();
  final fbAuth = FirebaseAuth.instance;
  var user = fbAuth.currentUser;
  // After initializeApp the persisted session restores asynchronously; wait
  // for it. The cached AuthProvider.uid is NOT a substitute — Firestore rules
  // need request.auth, which only a real currentUser provides.
  user ??= await fbAuth
      .authStateChanges()
      .firstWhere((u) => u != null, orElse: () => null)
      .timeout(const Duration(seconds: 8), onTimeout: () => null);
  final uid = user?.uid;
  if (uid == null) {
    debugPrint('Sync: no Firebase session restored; running local-only.');
    return null;
  }

  final service = FirestoreSyncService(uid: uid, repo: repo, prefs: prefs);
  repo.sync = service;
  await service.reconcile();
  service.attachListeners(onApply);
  return service;
}

/// Tears sync down on sign-out: detach listeners, stop pushing, and end the
/// Firebase session so a different owner can sign in cleanly.
Future<void> stopSync(LedgerRepository repo) async {
  final service = repo.sync;
  repo.sync = null;
  await service?.detach();
  try {
    await FirebaseAuth.instance.signOut();
  } catch (e) {
    debugPrint('Sync: signOut failed: $e');
  }
}
