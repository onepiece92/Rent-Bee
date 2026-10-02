import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/version.dart';
import '../../data/ledger_repository.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../../state/auth_provider.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../util/csv_share.dart';
import '../widgets/glass.dart';
import '../widgets/sync_badge.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/toast.dart';
import '../widgets/typed_confirm_dialog.dart';

/// Hairline inset for rows led by a 28 pt [IconTile]: gutter + tile + gap, so
/// the line starts under the title like iOS Settings.
const double _rowInset = Sys.gutter + 28 + 12;

/// Space between one section's card and the next section's title.
const double _sectionGap = 16;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // Only the three ledger facts this screen shows — not every Ledger
    // notification (search keystrokes, filter, each mark-paid) while the tab
    // sits off-screen.
    final (unitCount, ledgerMonth, cloudSyncActive) = context.select<
        LedgerProvider,
        (int, BsMonth, bool)>((l) => (l.totalCount, l.month, l.cloudSyncActive));
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final rate = settings.annualRaisePercent;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sys.gutter, 16, Sys.gutter, 120),
        children: [
          Text('Settings', style: Type.largeTitle.colored(sys.label)),
          const SizedBox(height: 16),
          const SectionTitle('Calendar'),
          GroupedCard(
            child: _ChoiceBody(
              label: 'Display dates in',
              child: SegmentedControl<CalendarMode>(
                values: CalendarMode.values,
                selected: settings.calendar,
                label: (m) => m == CalendarMode.bs
                    ? 'Bikram Sambat (BS)'
                    : 'Gregorian (AD)',
                onChanged: settings.setCalendar,
              ),
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Currency'),
          GroupedCard(
            child: _ChoiceBody(
              label: 'Track rent in',
              child: SegmentedControl<Currency>(
                values: Currency.values,
                selected: settings.currency,
                label: (c) => c == Currency.npr
                    ? 'Nepali Rupee (Rs)'
                    : r'US Dollar ($)',
                onChanged: settings.setCurrency,
              ),
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Appearance'),
          GroupedCard(
            child: SegmentedControl<ThemeMode>(
              values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
              selected: settings.appearance,
              label: (m) => switch (m) {
                ThemeMode.system => 'Automatic',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              },
              onChanged: settings.setAppearance,
            ),
          ),
          // Section footer, like iOS: explains the first segment.
          Padding(
            padding: const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 0),
            child: Text('Automatic follows the system setting.',
                style: Type.footnote.colored(sys.secondaryLabel)),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Security'),
          GroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListRow(
                  leading: IconTile(
                      icon: Icons.password_rounded, color: sys.secondaryLabel),
                  title: 'Change PIN',
                  subtitle: 'Update your unlock code',
                  chevron: true,
                  onTap: () => _changePin(context),
                ),
                const Hairline(inset: _rowInset),
                ListRow(
                  leading: IconTile(
                      icon: Icons.lock_outline, color: sys.secondaryLabel),
                  title: 'Lock now',
                  subtitle: 'Return to the PIN screen',
                  chevron: true,
                  onTap: () => context.read<AuthProvider>().lock(),
                ),
                const Hairline(inset: _rowInset),
                ListRow(
                  leading: IconTile(icon: Icons.logout_rounded, color: sys.red),
                  title: 'Sign out',
                  subtitle: auth.phone == null
                      ? 'Remove this device and re-verify your phone'
                      : 'Signed in as ${auth.phone} · tap to re-verify',
                  destructive: true,
                  chevron: true,
                  onTap: () => _signOut(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Rent'),
          GroupedCard(
            padding: EdgeInsets.zero,
            child: ListRow(
              leading:
                  IconTile(icon: Icons.trending_up_rounded, color: sys.orange),
              title: 'Annual Lease Escalation Rate',
              subtitle: rate == 0
                  ? 'Off — tap to auto-raise rent every year'
                  : 'Applied automatically on each unit\'s anniversary month',
              trailing: Text(rate == 0 ? 'Off' : '${fmtPercent(rate)}%',
                  style: Type.subhead.colored(sys.secondaryLabel).tabular),
              chevron: true,
              onTap: () => _editRaisePercent(context),
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Backup'),
          GroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Sys.gutter, 14, Sys.gutter, 14),
                  child: SyncStatusLine(),
                ),
                const Hairline(inset: _rowInset),
                if (cloudSyncActive) ...[
                  ListRow(
                    leading: IconTile(
                        icon: Icons.cloud_upload_outlined, color: sys.tint),
                    title: 'Back up to cloud now',
                    subtitle: 'Force a full re-sync of everything',
                    onTap: () => _backupToCloud(context),
                  ),
                  const Hairline(inset: _rowInset),
                ],
                ListRow(
                  leading: IconTile(icon: Icons.save_alt, color: sys.green),
                  title: 'Back up to file',
                  subtitle: 'Full snapshot — units, payments, charges, deposits',
                  chevron: true,
                  onTap: () => _backup(context),
                ),
                const Hairline(inset: _rowInset),
                ListRow(
                  leading: IconTile(icon: Icons.restore_rounded, color: sys.red),
                  title: 'Restore from backup',
                  subtitle: 'Replace all data with a backup file',
                  destructive: true,
                  chevron: true,
                  onTap: () => _restoreBackup(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('Data'),
          GroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListRow(
                  leading: IconTile(
                      icon: Icons.file_download_outlined, color: sys.green),
                  title: 'Import CSV',
                  subtitle: 'Merge units & payments from a CSV',
                  chevron: true,
                  onTap: () => _importCsv(context),
                ),
                const Hairline(inset: _rowInset),
                ListRow(
                  leading: IconTile(icon: Icons.ios_share, color: sys.tint),
                  title: 'Export CSV',
                  subtitle: 'Rent collection sheet for this BS year',
                  chevron: true,
                  onTap: () => _exportCsv(context),
                ),
                const Hairline(inset: _rowInset),
                // Demo data is a review/testing tool: only the store-review
                // test login and the debug guest session see it. A real
                // owner's account never does (it would replace their ledger).
                if (auth.canGenerateDemoData) ...[
                  ListRow(
                    leading: IconTile(
                        icon: Icons.auto_awesome, color: sys.secondaryLabel),
                    title: 'Generate demo data',
                    subtitle: 'Replace with 3 years of sample history',
                    chevron: true,
                    onTap: () => _generateDemo(context),
                  ),
                  const Hairline(inset: _rowInset),
                ],
                ListRow(
                  leading: IconTile(
                      icon: Icons.delete_sweep_outlined, color: sys.red),
                  title: 'Erase all data',
                  // "All your devices" only when the cloud mirror is live —
                  // a guest or local-only session erases this device alone.
                  subtitle: cloudSyncActive
                      ? 'Delete every unit and payment, on all your devices'
                      : 'Delete every unit and payment',
                  destructive: true,
                  chevron: true,
                  onTap: () =>
                      _eraseAll(context, synced: cloudSyncActive),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          const SectionTitle('About'),
          GroupedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Sys.radiusInset),
                      child: Image.asset(
                        'assets/icon/rent_bee.png',
                        width: 36,
                        height: 36,
                        // Source is 512² — decode to ~2x the display size.
                        cacheWidth: 72,
                        cacheHeight: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rent Bee',
                              style: Type.callout.semibold.colored(sys.label)),
                          Text('Version $appVersion',
                              style:
                                  Type.caption1.colored(sys.secondaryLabel)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tracking $unitCount units in '
                  '${ledgerMonth.labelIn(settings.calendar)}. '
                  // Not "offline": with sync on, the ledger is also in the cloud.
                  '${cloudSyncActive ? 'Data is stored on this device and synced to your account.' : 'Data is stored on this device.'}',
                  style: Type.caption1.colored(sys.secondaryLabel).tabular,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final saved = await showGlassDialog<bool>(
        context, (_) => const _ChangePinDialog());
    if (saved == true && context.mounted) {
      showToast(context, 'PIN updated');
    }
  }

  /// Picks a CSV file (Rent Bee export format) and merges it into the ledger.
  /// Units are upserted by code; paid/partial rows become payments in the
  /// currently selected BS year (the export omits the year).
  Future<void> _importCsv(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    final year = ledger.month.year;

    final ok = await _confirm(
      context,
      title: 'Import CSV?',
      message:
          'This merges units & payments from the file. Units matched by code '
          'have their tenant and rent updated, and recorded payments for the '
          'same months are overwritten. Rows without a year column are filed '
          'under the open year ($year). This can\'t be undone.',
      confirmLabel: 'Choose file',
    );
    if (ok != true) return;

    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
    } catch (e) {
      showToastOn(overlay, 'Could not open file picker: $e', error: true);
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      showToastOn(overlay, 'Could not read file', error: true);
      return;
    }

    try {
      final content = LedgerRepository.decodeCsv(bytes);
      final res = await ledger.importCsv(content);
      final nothing =
          res.unitsAdded == 0 && res.unitsUpdated == 0 && res.payments == 0;
      showToastOn(
        overlay,
        nothing
            ? 'Nothing imported — check the file has a code column and matching headers'
            : 'Imported · ${res.unitsAdded} new, ${res.unitsUpdated} updated, '
                '${res.payments} payments (year $year)',
        error: nothing,
      );
    } on FormatException catch (e) {
      showToastOn(overlay, 'Nothing imported. ${e.message}', error: true);
    } catch (e) {
      showToastOn(overlay, 'Nothing imported: $e', error: true);
    }
  }

  /// Exports a full, lossless JSON backup (everything) and opens the system
  /// share sheet so the owner can save it to Files/Drive. Restore with
  /// [_restoreBackup].
  Future<void> _backup(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final currency = context.read<SettingsProvider>().currency;
    final overlay = Overlay.of(context, rootOverlay: true);
    final origin = shareOriginFor(context);
    final stamp = DateTime.now().toIso8601String().split('T').first;
    try {
      final json = await ledger.exportBackupJson(currency: currency.name);
      await shareJson(json, 'rent-bee-backup-$stamp.json', origin: origin);
    } catch (e) {
      showToastOn(overlay, 'Backup failed: $e', error: true);
    }
  }

  /// Forces a full re-push of the local ledger to the cloud mirror.
  Future<void> _backupToCloud(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ledger.resyncToCloud();
      showToastOn(overlay, 'Backing up to cloud…');
    } catch (e) {
      showToastOn(overlay, 'Cloud backup failed: $e', error: true);
    }
  }

  /// Picks a JSON backup file and REPLACES all current data with it (after a
  /// destructive confirm). The inverse of [_backup].
  /// Restore replaces the whole ledger (and the cloud copy on every signed-in
  /// device), so it is confirmed like Erase — by typing a word — and only
  /// *after* the file has been read, when the dialog can say what the backup
  /// holds. The old flow asked first, sight unseen, and a backup with no
  /// units in it wiped everything on one tap (buglog B13).
  Future<void> _restoreBackup(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    // Captured before any await: the file picker can keep the app in the
    // background long enough to auto-lock, which unmounts this screen — and
    // the backup's currency must still be applied afterwards.
    final settings = context.read<SettingsProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);

    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
      );
    } catch (e) {
      showToastOn(overlay, 'Could not open file picker: $e', error: true);
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      showToastOn(overlay, 'Could not read file', error: true);
      return;
    }

    final String content;
    final ({int units, int payments, int charges, DateTime? exportedAt}) info;
    try {
      content = utf8.decode(bytes); // strict: a mangled file is refused
      info = LedgerRepository.inspectBackup(content);
    } on FormatException catch (e) {
      showToastOn(overlay, 'Not a usable backup: ${e.message}', error: true);
      return;
    } catch (e) {
      showToastOn(overlay, 'Could not read the backup: $e', error: true);
      return;
    }
    if (info.units == 0) {
      // Restoring it would simply erase the ledger; that is what Erase is for.
      showToastOn(overlay, 'That backup has no units in it — nothing restored',
          error: true);
      return;
    }
    if (!context.mounted) return; // locked while the picker was open

    final mode = settings.calendar;
    final when = info.exportedAt == null
        ? ''
        : ', saved ${dateLabel(info.exportedAt!, mode)}';
    final where = ledger.cloudSyncActive
        ? ' on this device and every other device signed in to your account'
        : '';
    final ok = await showGlassDialog<bool>(
      context,
      (_) => TypedConfirmDialog(
        title: 'Restore from backup?',
        message: 'The backup holds ${info.units} unit'
            '${info.units == 1 ? '' : 's'}, ${info.payments} payment'
            '${info.payments == 1 ? '' : 's'} and ${info.charges} charge '
            'record${info.charges == 1 ? '' : 's'}$when. Restoring replaces '
            'ALL current units, payments and charges$where. What you have now '
            'will be overwritten and can\'t be recovered.',
        word: 'RESTORE',
        confirmLabel: 'Restore',
      ),
    );
    if (ok != true) return;

    try {
      final res = await ledger.restoreBackup(content);
      // Re-apply the backup's currency, if it carried one, so a restore from
      // a USD backup doesn't silently read back as NPR.
      Currency? restoredCurrency;
      for (final c in Currency.values) {
        if (c.name == res.currency) restoredCurrency = c;
      }
      if (restoredCurrency != null) {
        await settings.setCurrency(restoredCurrency);
      }
      showToastOn(
          overlay,
          'Restored · ${res.units} units, ${res.payments} payments, '
          '${res.charges} charges');
    } catch (e) {
      showToastOn(overlay, 'Restore failed: $e', error: true);
    }
  }

  /// Exports the full current BS year (Baishakh–Chaitra) as CSV and opens the
  /// system share sheet. Matches the Reports screen's year export.
  Future<void> _exportCsv(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    final year = ledger.month.year;
    final origin = shareOriginFor(context);
    try {
      final csv = await ledger.repo.exportCsvRange(year, 1, 12);
      final name = 'rent-bee-$year-full.csv';
      await shareCsv(csv, name, origin: origin);
    } catch (e) {
      showToastOn(overlay, 'Export failed: $e', error: true);
    }
  }

  /// Demo data REPLACES the whole ledger — and, with cloud sync on, the cloud
  /// copy on every signed-in device. When there is (or may be) real data to
  /// lose, a tap isn't enough: the dialog says what will be deleted and the
  /// owner has to type REPLACE before the button enables. The plain confirm
  /// stays only when nothing can be overwritten: an empty ledger *and* no
  /// cloud mirror — with sync on, an empty local ledger proves nothing (the
  /// cloud copy may simply not have been pulled yet).
  Future<void> _generateDemo(BuildContext context) async {
    // Second line of defence behind the hidden row.
    if (!context.read<AuthProvider>().canGenerateDemoData) return;
    final ledger = context.read<LedgerProvider>();
    // Grow demo rents at the configured rate (fall back handled in the repo).
    final pct = context.read<SettingsProvider>().annualRaisePercent;
    final overlay = Overlay.of(context, rootOverlay: true);
    final units = ledger.totalCount;
    final synced = ledger.cloudSyncActive;
    final bool? ok;
    if (units == 0 && !synced) {
      ok = await _confirm(
        context,
        title: 'Generate demo data?',
        message: 'This fills the ledger with 3 years of sample history (rents '
            'grow each anniversary).',
        confirmLabel: 'Generate',
      );
    } else {
      final where = synced
          ? ' from this device and every other device signed in to your '
              'account'
          : '';
      final what = units > 0
          ? 'You have $units unit${units == 1 ? '' : 's'} with payment '
              'history. Generating demo data permanently deletes all of it'
          : 'Generating demo data permanently deletes everything in this '
              'account';
      ok = await showGlassDialog<bool>(
        context,
        (_) => TypedConfirmDialog(
          title: 'Replace your data with demo data?',
          message: '$what$where and puts 3 years of sample history in its '
              'place. This cannot be undone — back up to a file first if you '
              'might want it back.',
          word: 'REPLACE',
          confirmLabel: 'Replace',
        ),
      );
    }
    if (ok != true) return;
    await ledger.generateDemoData(pct);
    showToastOn(overlay, '3 years of demo data generated');
  }

  /// The one irreversible, account-wide action: a tap isn't enough, the owner
  /// has to type ERASE before the button enables.
  Future<void> _eraseAll(BuildContext context, {required bool synced}) async {
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    final ok = await showGlassDialog<bool>(
      context,
      (_) => TypedConfirmDialog(
        title: 'Erase all data?',
        message: synced
            ? 'This permanently deletes every unit and all payment history '
                'from this device and every other device signed in to your '
                'account. This cannot be undone.'
            : 'This permanently deletes every unit and all payment history. '
                'This cannot be undone.',
        word: 'ERASE',
        confirmLabel: 'Erase',
      ),
    );
    if (ok != true) return;
    await ledger.eraseAllData();
    showToastOn(overlay, 'All data erased');
  }

  /// Signs out: clears the verified phone identity and the PIN, sending the
  /// owner back through phone OTP onboarding. Local ledger data is untouched.
  Future<void> _signOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await _confirm(
      context,
      title: 'Sign out?',
      message:
          'You\'ll need to verify your phone number and set a new PIN to get '
          'back in. Your units and payment history stay on this device.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok != true) return;
    await auth.resetIdentity(); // go_router redirects to phone onboarding.
  }

  /// Bulk annual lease escalation: raises every unit's monthly rent by [percent]%.
  /// Past recorded payments are captured per record, so history is unchanged.
  /// Sets the automatic annual lease escalation rate (0 = off) and immediately
  /// catches up any now-due anniversary raises at the new rate.
  Future<void> _editRaisePercent(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    final sampleRent = ledger.totalCount > 0
        ? ledger.allUnitsByCode.first.unit.monthlyRent
        : 18000;
    final percent = await showGlassDialog<double>(
      context,
      (_) => _RaisePercentDialog(
        initial: settings.annualRaisePercent,
        sampleRent: sampleRent,
        currency: settings.currency,
      ),
    );
    if (percent == null) return;
    await settings.setAnnualRaisePercent(percent);
    final raised = percent > 0 ? await ledger.applyDueRaises(percent) : 0;
    final msg = percent == 0
        ? 'Annual Lease Escalation Rate turned off'
        : 'Annual Lease Escalation Rate set to ${fmtPercent(percent)}%'
            '${raised > 0 ? ' · raised $raised unit${raised == 1 ? '' : 's'} now' : ''}';
    showToastOn(overlay, msg);
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: title,
        content: Text(message),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction(
            confirmLabel,
            primary: !destructive,
            destructive: destructive,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }
}

/// A segmented choice inside a card, under a short secondary caption.
class _ChoiceBody extends StatelessWidget {
  final String label;
  final Widget child;
  const _ChoiceBody({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Type.footnote.semibold.colored(sys.secondaryLabel)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// Formats a percentage without a trailing ".0" — 8.0 → "8", 7.5 → "7.5".
String fmtPercent(double p) =>
    p == p.truncateToDouble() ? p.toInt().toString() : p.toString();

/// Dialog to set the automatic annual lease escalation rate. Quick presets
/// plus a free-form field that accepts any rate, including fractions like 7.5.
/// Pops the chosen percent (0 = off) or null on cancel.
class _RaisePercentDialog extends StatefulWidget {
  final double initial;
  final int sampleRent;
  final Currency currency;
  const _RaisePercentDialog(
      {required this.initial,
      required this.sampleRent,
      required this.currency});

  @override
  State<_RaisePercentDialog> createState() => _RaisePercentDialogState();
}

class _RaisePercentDialogState extends State<_RaisePercentDialog> {
  static const _presets = [0.0, 5.0, 10.0, 15.0];
  late final TextEditingController _controller =
      TextEditingController(text: fmtPercent(widget.initial));

  double? get _percent {
    final v = double.tryParse(_controller.text.trim());
    if (v == null || v < 0 || v > 1000) return null;
    return v;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final pct = _percent;
    final String preview;
    if (pct == null) {
      preview = 'Enter any percentage (decimals allowed), e.g. 7.5.';
    } else if (pct == 0) {
      preview = 'Rents will not change automatically.';
    } else {
      final next = ((widget.sampleRent * (100 + pct)) / 100).round();
      preview = 'Each active unit\'s rent rises ${fmtPercent(pct)}% on its '
          'anniversary month, every year — e.g. '
          '${Money.format(widget.sampleRent, widget.currency)} → '
          '${Money.format(next, widget.currency)} after a year (rounded to '
          'whole units). Recorded payments stay unchanged.';
    }

    return GlassDialog(
      title: 'Annual Lease Escalation Rate',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text(p == 0 ? 'Off' : '${fmtPercent(p)}%'),
                  selected: pct == p,
                  onSelected: (_) => _controller.text = fmtPercent(p),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // digits + a single decimal point
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: 'Escalation rate %  (0 = off, decimals allowed)',
              suffixText: '%',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(preview,
              style: Type.footnote.colored(sys.secondaryLabel).tabular),
        ],
      ),
      actions: [
        GlassDialogAction('Cancel', onPressed: () => Navigator.pop(context)),
        GlassDialogAction(
          pct == null
              ? 'Save'
              : pct == 0
                  ? 'Turn off'
                  : 'Set ${fmtPercent(pct)}%',
          primary: true,
          onPressed: pct == null ? null : () => Navigator.pop(context, pct),
        ),
      ],
    );
  }
}

/// Change PIN: current, new, confirm. A widget of its own so the three text
/// controllers live exactly as long as the dialog (they used to be created
/// in a method and never disposed).
class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Deriving the PIN hash takes a moment; a second tap on Save in that time
  // must not run the whole change again.
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    _busy = true;
    try {
      if (!await auth.unlock(_current.text.trim())) {
        if (mounted) {
          final wait = auth.lockoutRemaining;
          showToast(
              context,
              wait > Duration.zero
                  ? 'Too many wrong PINs. Try again in '
                      '${wait.inMinutes > 0 ? '${wait.inMinutes + 1} min' : '${wait.inSeconds + 1} s'}.'
                  : 'Current PIN is incorrect',
              error: true);
        }
        return;
      }
      await auth.setPin(_next.text.trim());
      if (mounted) Navigator.pop(context, true);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'Change PIN',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinInput(controller: _current, label: 'Current PIN'),
            const SizedBox(height: 10),
            _PinInput(
              controller: _next,
              label: 'New PIN',
              validator: (v) =>
                  (v == null || v.trim().length != 4) ? 'Enter 4 digits' : null,
            ),
            const SizedBox(height: 10),
            _PinInput(
              controller: _confirm,
              label: 'Confirm new PIN',
              validator: (v) =>
                  v?.trim() != _next.text.trim() ? 'Does not match' : null,
            ),
          ],
        ),
      ),
      actions: [
        GlassDialogAction('Cancel',
            onPressed: () => Navigator.pop(context, false)),
        GlassDialogAction('Save', primary: true, onPressed: _save),
      ],
    );
  }
}

class _PinInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  const _PinInput(
      {required this.controller, required this.label, this.validator});
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 4,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
      ),
    );
  }
}
