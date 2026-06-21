import 'package:flutter/foundation.dart';

/// Coarse cloud-sync state surfaced to the UI.
enum SyncState {
  /// Cloud sync isn't running (guest session, or phone not verified).
  off,

  /// A push (or the sign-in reconcile) is in flight.
  syncing,

  /// Everything local has been mirrored to the cloud.
  synced,

  /// The last sync attempt failed (offline or a Firestore error).
  error,
}

/// A stable, always-present holder for cloud-sync state. It outlives the
/// [FirestoreSyncService] (which is created on sign-in and torn down on
/// sign-out), so the UI can watch one object regardless of whether sync is
/// currently active. The service feeds it; the UI reads it.
class SyncStatusController extends ChangeNotifier {
  SyncState _state = SyncState.off;
  String? _lastError;
  DateTime? _lastSyncedAt;

  SyncState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// True when cloud sync is active for this session (anything but [off]).
  bool get active => _state != SyncState.off;

  void setOff() => _set(SyncState.off);
  void setSyncing() {
    _lastError = null;
    _set(SyncState.syncing);
  }

  void setSynced() {
    _lastError = null;
    _lastSyncedAt = DateTime.now();
    _set(SyncState.synced);
  }

  void setError(String message) {
    _lastError = message;
    _set(SyncState.error);
  }

  void _set(SyncState s) {
    // `synced` always notifies so the timestamp refreshes; others dedupe.
    if (s == _state && s != SyncState.synced) return;
    _state = s;
    notifyListeners();
  }
}
