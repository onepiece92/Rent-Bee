import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../state/sync_status.dart';

/// Visual mapping for a [SyncState]: icon, the status colour for fills, its
/// text-safe variant, and a short label — resolved for the current appearance.
({IconData icon, Color color, Color textColor, String label}) _look(
        Sys sys, SyncState s) =>
    switch (s) {
      SyncState.off => (
          icon: Icons.cloud_off_rounded,
          color: sys.secondaryLabel,
          textColor: sys.secondaryLabel,
          label: 'Not syncing',
        ),
      SyncState.syncing => (
          icon: Icons.cloud_sync_rounded,
          color: sys.tint,
          textColor: sys.tintText,
          label: 'Syncing…',
        ),
      SyncState.synced => (
          icon: Icons.cloud_done_rounded,
          color: sys.green,
          textColor: sys.greenText,
          label: 'Backed up',
        ),
      SyncState.error => (
          icon: Icons.cloud_off_rounded,
          color: sys.red,
          textColor: sys.redText,
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

/// Compact header badge — a status capsule (kit: the state colour at 15%
/// behind an icon and a footnote label, never colour alone) for the sync
/// state. Hidden entirely when sync is off (guest / local-only), so it's only
/// present when there's a cloud session to report on.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final ctrl = context.watch<SyncStatusController>();
    if (ctrl.state == SyncState.off) return const SizedBox.shrink();
    final look = _look(sys, ctrl.state);
    final synced = ctrl.lastSyncedAt;
    final tip = ctrl.state == SyncState.error
        ? 'Sync failed — changes are saved on this device and will retry'
        : ctrl.state == SyncState.synced && synced != null
            ? 'Backed up to cloud ${_relativeTime(synced)}'
            : look.label;
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Sys.wash(look.color),
          borderRadius: BorderRadius.circular(Sys.radiusCapsule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(look.icon, size: 14, color: look.textColor),
            const SizedBox(width: 6),
            Text(look.label,
                style: Type.footnote.semibold.colored(look.textColor)),
          ],
        ),
      ),
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
    final sys = Sys.of(context);
    final ctrl = context.watch<SyncStatusController>();
    final look = _look(sys, ctrl.state);
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
        Icon(look.icon, size: 20, color: look.textColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(look.label,
                  style: Type.subhead.semibold.colored(sys.label)),
              const SizedBox(height: 2),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption1.colored(sys.secondaryLabel)),
            ],
          ),
        ),
      ],
    );
  }
}
