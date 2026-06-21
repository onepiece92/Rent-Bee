import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/sync_status.dart';

/// Visual mapping for a [SyncState]: icon, colour, and a short label.
({IconData icon, Color color, String label}) _look(SyncState s) =>
    switch (s) {
      SyncState.off => (
          icon: Icons.cloud_off_rounded,
          color: Brand.muted,
          label: 'Not syncing',
        ),
      SyncState.syncing => (
          icon: Icons.cloud_sync_rounded,
          color: Brand.orangeSoft,
          label: 'Syncing…',
        ),
      SyncState.synced => (
          icon: Icons.cloud_done_rounded,
          color: Brand.paidText,
          label: 'Backed up',
        ),
      SyncState.error => (
          icon: Icons.cloud_off_rounded,
          color: Colors.redAccent,
          label: 'Sync failed',
        ),
    };

String _relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Compact app-bar/header badge — a single cloud icon coloured by sync state.
/// Hidden entirely when sync is off (guest / local-only), so it's only present
/// when there's a cloud session to report on.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncStatusController>();
    if (ctrl.state == SyncState.off) return const SizedBox.shrink();
    final look = _look(ctrl.state);
    final synced = ctrl.lastSyncedAt;
    final tip = ctrl.state == SyncState.error
        ? 'Sync failed — changes are saved on this device and will retry'
        : ctrl.state == SyncState.synced && synced != null
            ? 'Backed up to cloud ${_relativeTime(synced)}'
            : look.label;
    return Tooltip(
      message: tip,
      child: Icon(look.icon, size: 16, color: look.color),
    );
  }
}

/// Full status line for the Settings "Backup" section: icon + label + when it
/// last synced (or the error). Always visible, including the `off` state, so a
/// guest/local-only user understands cloud backup isn't running.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SyncStatusController>();
    final look = _look(ctrl.state);
    final synced = ctrl.lastSyncedAt;
    final detail = switch (ctrl.state) {
      SyncState.off => 'Sign in with your phone to back up automatically',
      SyncState.syncing => 'Mirroring your latest changes to the cloud',
      SyncState.synced => synced != null
          ? 'Last backed up ${_relativeTime(synced)}'
          : 'Up to date',
      SyncState.error => ctrl.lastError == null
          ? 'Will retry automatically'
          : 'Will retry — ${ctrl.lastError}',
    };
    return Row(
      children: [
        Icon(look.icon, size: 20, color: look.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(look.label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
