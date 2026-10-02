import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/auth_provider.dart';
import '../state/sync_status.dart';
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
  SyncStatusController? status,
  void Function(String? calendarMode, num? rate, String? currency)?
      onRemoteSettings,
  ({String calendarMode, double rate, String currency}) Function()?
      localSettings,
  int Function()? settingsRevision,
}) async {
  if (auth.isGuest || !auth.phoneVerified) {
    status?.setOff();
    return null;
  }

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
    status?.setOff();
    return null;
  }

  final service =
      FirestoreSyncService(uid: uid, repo: repo, prefs: prefs, status: status);
  service.onRemoteSettings = onRemoteSettings;
  // Settings revision at the moment sync starts — to tell, further down,
  // whether the owner changed a setting while we were reconciling.
  final revisionAtStart = settingsRevision?.call();
  repo.sync = service;
  await service.reconcile();

  // The owner signed out (or sync was torn down) while reconciling: this
  // service is dead. Attaching listeners to it would leave them running
  // against a signed-out session with nothing left to cancel them.
  bool alive() => repo.sync == service && auth.phoneVerified;
  if (!alive()) {
    await service.detach();
    return null;
  }

  // Owner settings (calendar mode + currency + escalation rate), settled
  // BEFORE the listeners attach. The cloud wins if it has any value —
  // unless the owner changed a setting on this device while sync was
  // starting, in which case that newer choice wins and is pushed. (Doing this
  // after attaching let the settings listener's first snapshot overwrite the
  // local change before it could be pushed.)
  try {
    final remote = await service.fetchSettings();
    if (!alive()) {
      await service.detach();
      return null;
    }
    final hasRemote = remote != null &&
        (remote['calendarMode'] != null ||
            remote['annualRaisePercent'] != null ||
            remote['currency'] != null);
    final changedLocally =
        revisionAtStart != null && settingsRevision!() != revisionAtStart;
    if (hasRemote && !changedLocally) {
      onRemoteSettings?.call(
        remote['calendarMode'] as String?,
        remote['annualRaisePercent'] as num?,
        remote['currency'] as String?,
      );
    } else if (localSettings != null) {
      final s = localSettings();
      service.pushSettings(s.calendarMode, s.rate, s.currency);
    }
  } catch (e) {
    // Settings are a convenience; failing to read them must not leave the
    // ledger without its listeners.
    debugPrint('Sync: could not read owner settings: $e');
  }

  service.attachListeners(onApply);
  return service;
}

/// Tears sync down on sign-out: detach listeners, stop pushing, and end the
/// Firebase session so a different owner can sign in cleanly.
Future<void> stopSync(LedgerRepository repo, {SyncStatusController? status}) async {
  final service = repo.sync;
  repo.sync = null;
  await service?.detach();
  status?.setOff();
  try {
    await FirebaseAuth.instance.signOut();
  } catch (e) {
    debugPrint('Sync: signOut failed: $e');
  }
}
