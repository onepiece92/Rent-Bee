import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../../state/auth_provider.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../util/csv_share.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/toast.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final settings = context.watch<SettingsProvider>();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
        children: [
          Text('Settings',
              style: display(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          const _SectionLabel('Calendar'),
          GlassPanel(
            child: _CalendarToggle(
              mode: settings.calendar,
              onChanged: settings.setCalendar,
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Security'),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.password_rounded,
                  title: 'Change PIN',
                  subtitle: 'Update your unlock code',
                  onTap: () => _changePin(context),
                ),
                const _Divider(),
                _SettingTile(
                  icon: Icons.lock_outline,
                  title: 'Lock now',
                  subtitle: 'Return to the PIN screen',
                  onTap: () => context.read<AuthProvider>().lock(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Rent'),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: _SettingTile(
              icon: Icons.trending_up_rounded,
              title: settings.annualRaisePercent == 0
                  ? 'Annual increase'
                  : 'Annual increase · ${fmtPercent(settings.annualRaisePercent)}%',
              subtitle: settings.annualRaisePercent == 0
                  ? 'Off — tap to auto-raise rent every year'
                  : 'Applied automatically on each unit\'s anniversary month',
              onTap: () => _editRaisePercent(context),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Data'),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.file_download_outlined,
                  title: 'Import CSV',
                  subtitle: 'Merge units & payments from a file',
                  onTap: () => _importCsv(context),
                ),
                const _Divider(),
                _SettingTile(
                  icon: Icons.ios_share,
                  title: 'Export CSV',
                  subtitle: 'Share this BS year\'s ledger',
                  onTap: () => _exportCsv(context),
                ),
                const _Divider(),
                _SettingTile(
                  icon: Icons.auto_awesome,
                  title: 'Generate demo data',
                  subtitle: 'Replace with 3 years of sample history',
                  onTap: () => _generateDemo(context),
                ),
                const _Divider(),
                _SettingTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Erase all data',
                  subtitle: 'Delete every unit and payment',
                  iconColor: Colors.redAccent,
                  onTap: () => _eraseAll(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('About'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.asset(
                        'assets/icon/rent_bee.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rent Bee',
                            style: display(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Text('v1.0.0 · offline',
                            style:
                                TextStyle(color: Brand.muted, fontSize: 12.5)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tracking ${ledger.totalCount} units in '
                  '${ledger.month.labelIn(settings.calendar)}. '
                  'Data is stored on this device.',
                  style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Change PIN',
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PinInput(controller: current, label: 'Current PIN'),
              const SizedBox(height: 10),
              _PinInput(
                controller: next,
                label: 'New PIN',
                validator: (v) =>
                    (v == null || v.trim().length != 4) ? 'Enter 4 digits' : null,
              ),
              const SizedBox(height: 10),
              _PinInput(
                controller: confirm,
                label: 'Confirm new PIN',
                validator: (v) =>
                    v?.trim() != next.text.trim() ? 'Does not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction(
            'Save',
            primary: true,
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (!await auth.unlock(current.text.trim())) {
                if (ctx.mounted) {
                  showToast(ctx, 'Current PIN is incorrect', error: true);
                }
                return;
              }
              await auth.setPin(next.text.trim());
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );

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

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return; // cancelled

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      showToastOn(overlay, 'Could not read file', error: true);
      return;
    }

    try {
      final content = utf8.decode(bytes, allowMalformed: true);
      final res = await ledger.importCsv(content);
      showToastOn(
          overlay,
          'Imported · ${res.unitsAdded} new, ${res.unitsUpdated} updated, '
          '${res.payments} payments (year $year)');
    } catch (e) {
      showToastOn(overlay, 'Import failed: $e', error: true);
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

  Future<void> _generateDemo(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    // Grow demo rents at the configured rate (fall back handled in the repo).
    final pct = context.read<SettingsProvider>().annualRaisePercent;
    final overlay = Overlay.of(context, rootOverlay: true);
    final ok = await _confirm(
      context,
      title: 'Generate demo data?',
      message: 'This replaces all current units and payments with 3 years of '
          'sample history (rents grow each anniversary).',
      confirmLabel: 'Generate',
    );
    if (ok != true) return;
    await ledger.generateDemoData(pct);
    showToastOn(overlay, '3 years of demo data generated');
  }

  Future<void> _eraseAll(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final overlay = Overlay.of(context, rootOverlay: true);
    final ok = await _confirm(
      context,
      title: 'Erase all data?',
      message:
          'This permanently deletes every unit and all payment history. '
          'This cannot be undone.',
      confirmLabel: 'Erase',
      destructive: true,
    );
    if (ok != true) return;
    await ledger.eraseAllData();
    showToastOn(overlay, 'All data erased');
  }

  /// Bulk annual rent increase: raises every unit's monthly rent by [percent]%.
  /// Past recorded payments are captured per record, so history is unchanged.
  /// Sets the automatic annual-increase percentage (0 = off) and immediately
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
      ),
    );
    if (percent == null) return;
    await settings.setAnnualRaisePercent(percent);
    final raised = percent > 0 ? await ledger.applyDueRaises(percent) : 0;
    final msg = percent == 0
        ? 'Automatic rent increase turned off'
        : 'Annual increase set to ${fmtPercent(percent)}%'
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

/// Segmented BS | AD switch for the app-wide date calendar.
class _CalendarToggle extends StatelessWidget {
  final CalendarMode mode;
  final ValueChanged<CalendarMode> onChanged;
  const _CalendarToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Display dates in',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Brand.muted)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in CalendarMode.values) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(m),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: m == mode ? Brand.orangeGradient : null,
                      color: m == mode ? null : Brand.glassBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: m == mode
                              ? Colors.transparent
                              : Brand.glassBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      m == CalendarMode.bs
                          ? 'Bikram Sambat (BS)'
                          : 'Gregorian (AD)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: m == mode ? Colors.white : Brand.muted,
                      ),
                    ),
                  ),
                ),
              ),
              if (m == CalendarMode.bs) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

/// Formats a percentage without a trailing ".0" — 8.0 → "8", 7.5 → "7.5".
String fmtPercent(double p) =>
    p == p.truncateToDouble() ? p.toInt().toString() : p.toString();

/// Dialog to set the automatic annual rent-increase percentage. Quick presets
/// plus a free-form field that accepts any rate, including fractions like 7.5.
/// Pops the chosen percent (0 = off) or null on cancel.
class _RaisePercentDialog extends StatefulWidget {
  final double initial;
  final int sampleRent;
  const _RaisePercentDialog({required this.initial, required this.sampleRent});

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
    final pct = _percent;
    final String preview;
    if (pct == null) {
      preview = 'Enter any percentage (decimals allowed), e.g. 7.5.';
    } else if (pct == 0) {
      preview = 'Rents will not change automatically.';
    } else {
      final next = ((widget.sampleRent * (100 + pct)) / 100).round();
      preview =
          'Each active unit\'s rent rises ${fmtPercent(pct)}% on its anniversary '
          'month, every year — e.g. ${Money.format(widget.sampleRent)} → '
          '${Money.format(next)} after a year (rounded to whole rupees). '
          'Recorded payments stay unchanged.';
    }

    return GlassDialog(
      title: 'Annual rent increase',
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
              labelText: 'Increase %  (0 = off, decimals allowed)',
              suffixText: '%',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(preview,
              style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Brand.muted)),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? Brand.orangeSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Brand.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Brand.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}
