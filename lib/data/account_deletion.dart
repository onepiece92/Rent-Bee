import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'ledger_repository.dart';

/// Deletes an owner's account and everything stored for it (App Store
/// guideline 5.1.1(v)): the cloud copy of the ledger, the sign-in account,
/// and the ledger on this device.
///
/// Firebase refuses to delete an account that has not signed in recently, so
/// the caller re-verifies the owner first (see `AuthProvider.deletingAccount`)
/// and then runs this right away, with the fresh session current.
class AccountDeletion {
  final LedgerRepository repo;
  final FirebaseFirestore firestore;

  /// Deletes the Firebase Auth user (`currentUser.delete()`); injectable for
  /// tests.
  final Future<void> Function() deleteUser;

  /// Revokes the Sign in with Apple token, when the owner used Apple; Apple
  /// requires this when an account is deleted. Null for other sign-ins.
  final Future<void> Function()? revokeApple;

  AccountDeletion({
    required this.repo,
    required this.firestore,
    required this.deleteUser,
    this.revokeApple,
  });

  /// The ledger subcollections under `users/{uid}` (see FirestoreSyncService).
  static const ledgerCollections = ['units', 'payments', 'charges'];

  /// Writes per batch; Firestore allows 500.
  static const _batchSize = 400;

  Future<void> run(String uid) async {
    // Stop sync first: nothing may push to the account while it is deleted,
    // and its listeners must not react to the deletes.
    final service = repo.sync;
    repo.sync = null;
    await service?.detach();

    final root = firestore.collection('users').doc(uid);
    for (final name in ledgerCollections) {
      await _deleteAll(root.collection(name));
    }
    await root.delete(); // the owner-settings document

    if (revokeApple != null) {
      try {
        await revokeApple!();
      } catch (e) {
        // The account is still deleted; the owner can also remove the app
        // from Settings → Apple ID → Sign in with Apple.
        debugPrint('Account deletion: Apple token revoke failed: $e');
      }
    }

    // Last of the cloud steps: once the user is gone, its data can no longer
    // be reached to delete it.
    await deleteUser();

    await repo.eraseAllLocal();
  }

  Future<void> _deleteAll(CollectionReference<Map<String, dynamic>> col) async {
    while (true) {
      final page = await col.limit(_batchSize).get();
      if (page.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (page.docs.length < _batchSize) return;
    }
  }
}
