import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../widgets/glass.dart';
import '../widgets/sheet_scaffold.dart';
import '../widgets/toast.dart';
import 'edit_unit_sheet.dart';

/// Bottom sheet: unit details, Collect/Undo for the selected month,
/// edit/delete, and a 6-month history strip.
class UnitDetailSheet extends StatelessWidget {
  final int unitId;
  const UnitDetailSheet({super.key, required this.unitId});

  static Future<void> show(BuildContext context, int unitId) {
    return showGlassSheet(
      context,
      (_) => UnitDetailSheet(unitId: unitId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final mode = context.watch<SettingsProvider>().calendar;
    final row = ledger.rowFor(unitId);
    if (row == null) return const SizedBox.shrink();
    final s = row.unit;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // head
        Row(
          children: [
            CodeAvatar(code: s.code, paid: true, size: 52),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.tenantName,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1)),
                  Text(s.businessType.isEmpty ? s.code : s.businessType,
                      style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                ],
              ),
            ),
            _IconBtn(
                icon: Icons.edit_outlined,
                onTap: () => EditUnitSheet.show(context, unit: s)),
            const SizedBox(width: 8),
            _IconBtn(
                icon: Icons.delete_outline,
                onTap: () => _confirmDelete(context, ledger, s)),
          ],
        ),
        const SizedBox(height: 18),

        // detail grid
        Row(
          children: [
            _DetailCell(label: 'Monthly rent', value: Money.format(s.monthlyRent)),
            const SizedBox(width: 11),
            _DetailCell(
              label: 'Contact',
              value: (s.phone == null || s.phone!.isEmpty) ? '—' : s.phone!,
              icon: Icons.phone,
              // Tap to text the tenant; only when a number is on file.
              onTap: (s.phone == null || s.phone!.isEmpty)
                  ? null
                  : () => _sendSms(context, s.phone!,
                      body: _reminderText(s, ledger.month,
                          paid: row.payment != null)),
              trailingIcon: (s.phone == null || s.phone!.isEmpty)
                  ? null
                  : Icons.sms_outlined,
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            _DetailCell(
              label: 'Rent started',
              value: s.startedOn == null
                  ? 'Not set'
                  : dateLabel(s.startedOn!, mode),
              icon: Icons.event_outlined,
            ),
            const SizedBox(width: 11),
            _DetailCell(
              label: 'Status',
              value: s.isActive ? 'Active' : 'Vacant',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // big Collect / Undo button
        _BigToggleButton(unit: s, payment: row.payment, month: ledger.month),

        const SizedBox(height: 20),
        const Text('Recent months',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Brand.muted,
                letterSpacing: 0.2)),
        const SizedBox(height: 10),
        _HistoryStrip(unitId: s.id),
      ],
    );
  }

  /// The message pre-filled into the SMS composer. A polite due-reminder when
  /// the month is unpaid, a thank-you when it's already collected.
  String _reminderText(Unit s, BsMonth m, {required bool paid}) {
    final amount = Money.format(s.monthlyRent);
    if (paid) {
      return 'Hi ${s.tenantName}, thank you — we have received your '
          '${m.monthName} ${m.year} rent of $amount.';
    }
    return 'Hi ${s.tenantName}, gentle reminder: rent of $amount for '
        '${m.monthName} ${m.year} is due. Thank you!';
  }

  /// Opens the system Messages composer pre-addressed to [phone], with [body]
  /// pre-filled when provided.
  Future<void> _sendSms(BuildContext context, String phone,
      {String? body}) async {
    // Strip spaces/dashes the user may have typed; keep digits and a lead '+'.
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri uri;
    if (body == null || body.isEmpty) {
      uri = Uri(scheme: 'sms', path: cleaned);
    } else {
      // iOS expects the body after '&', Android/others after '?'.
      final sep =
          defaultTargetPlatform == TargetPlatform.iOS ? '&' : '?';
      uri = Uri.parse('sms:$cleaned${sep}body=${Uri.encodeComponent(body)}');
    }
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      showToast(context, 'Could not open Messages for $phone', error: true);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, LedgerProvider ledger, Unit s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.navy,
        title: const Text('Delete Unit?'),
        content: Text(
            'This removes ${s.code} (${s.tenantName}) and all its payment history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ledger.deleteUnit(s.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _BigToggleButton extends StatelessWidget {
  final Unit unit;
  final Payment? payment;
  final BsMonth month;
  const _BigToggleButton(
      {required this.unit, required this.payment, required this.month});

  @override
  Widget build(BuildContext context) {
    final ledger = context.read<LedgerProvider>();
    final mode = context.watch<SettingsProvider>().calendar;
    final rent = unit.monthlyRent;
    final paidAmount = payment?.amount ?? 0;
    final status = paidAmount <= 0
        ? PayStatus.pending
        : paidAmount >= rent
            ? PayStatus.paid
            : PayStatus.partial;

    switch (status) {
      case PayStatus.paid:
        final paidOn = payment!.paidOn;
        final on = paidOn != null ? dateLabel(paidOn, mode) : '—';
        return _BaseBigButton(
          onTap: () => ledger.undo(unit.id),
          bg: Brand.paid.withValues(alpha: 0.12),
          border: Brand.paidPillBorder,
          child: Text('Paid $on · tap to undo',
              style: const TextStyle(
                  color: Brand.paidText,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700)),
        );

      case PayStatus.partial:
        final remaining = (rent - paidAmount).clamp(0, rent);
        return Column(
          children: [
            _BaseBigButton(
              onTap: () => ledger.markPaid(unit), // settle the rest in full
              gradient: Brand.orangeGradient,
              border: Colors.white.withValues(alpha: 0.3),
              glow: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${Money.format(paidAmount)} of ${Money.format(rent)} paid',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('Collect remaining ${Money.format(remaining)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SecondaryButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit amount',
                    onTap: () => _recordPartial(context, ledger),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SecondaryButton(
                    icon: Icons.close,
                    label: 'Undo',
                    onTap: () => ledger.undo(unit.id),
                  ),
                ),
              ],
            ),
          ],
        );

      case PayStatus.pending:
        return Column(
          children: [
            _BaseBigButton(
              onTap: () => ledger.markPaid(unit),
              gradient: Brand.orangeGradient,
              border: Colors.white.withValues(alpha: 0.3),
              glow: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_downward,
                      size: 17, color: Colors.white),
                  const SizedBox(width: 7),
                  Text(
                      'Collect ${Money.format(rent)} for ${month.monthNameIn(mode)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
              icon: Icons.pie_chart_outline,
              label: 'Record partial amount',
              onTap: () => _recordPartial(context, ledger),
            ),
          ],
        );
    }
  }

  /// Prompts for the total amount received this month and records it. An empty
  /// or zero value clears the month (undo); anything >= rent settles it fully.
  Future<void> _recordPartial(
      BuildContext context, LedgerProvider ledger) async {
    final ctrl = TextEditingController(
        text: payment == null ? '' : payment!.amount.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.navy,
        title: const Text('Amount received'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rent is ${Money.format(unit.monthlyRent)}. Enter the total '
              'received for ${month.monthName} ${month.year}.',
              style: const TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                prefixText: 'Rs ',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.orange),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    if (result <= 0) {
      await ledger.undo(unit.id);
    } else {
      await ledger.markPaid(unit, amount: result);
    }
  }
}

/// Ghost button for secondary actions inside the sheet.
class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Brand.glassBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Brand.orangeSoft),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Brand.orangeSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _BaseBigButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final Color? bg;
  final Gradient? gradient;
  final Color border;
  final bool glow;
  const _BaseBigButton({
    required this.onTap,
    required this.child,
    required this.border,
    this.bg,
    this.gradient,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: bg,
              gradient: gradient,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: border),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: Brand.orange.withValues(alpha: 0.45),
                        blurRadius: 26,
                        offset: const Offset(0, 8),
                      )
                    ]
                  : null,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _HistoryStrip extends StatefulWidget {
  final int unitId;
  const _HistoryStrip({required this.unitId});

  @override
  State<_HistoryStrip> createState() => _HistoryStripState();
}

class _HistoryStripState extends State<_HistoryStrip> {
  late final LedgerProvider _ledger;
  late Future<List<HistoryEntry>> _future;
  // Last loaded entries, kept on-screen while a refresh is in flight so the
  // strip doesn't flash its spinner every time the sheet rebuilds (e.g. after
  // marking the current month paid).
  List<HistoryEntry>? _last;

  @override
  void initState() {
    super.initState();
    _ledger = context.read<LedgerProvider>();
    _future = _load();
    _ledger.addListener(_reload);
  }

  Future<List<HistoryEntry>> _load() =>
      _ledger.historyFor(widget.unitId, months: 6);

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  void dispose() {
    _ledger.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsProvider>().calendar;
    return FutureBuilder<List<HistoryEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) _last = snap.data;
        final data = snap.data ?? _last;
        if (data == null) {
          return const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        // repo returns newest-first; reverse so oldest is left, current right.
        final entries = data.reversed.toList();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final e in entries)
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.paid
                          ? Brand.paid.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: e.paid
                              ? Colors.transparent
                              : Brand.glassBorder),
                    ),
                    child: e.paid
                        ? const Icon(Icons.check,
                            size: 14, color: Color(0xFF053026))
                        : const Text('–',
                            style: TextStyle(
                                color: Brand.muted,
                                fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  Text(BsMonth(e.year, e.month).shortMonthNameIn(mode),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Brand.muted,
                          fontWeight: FontWeight.w600)),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  const _DetailCell({
    required this.label,
    required this.value,
    this.icon,
    this.trailingIcon,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: Brand.muted,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: Brand.text),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(
                        fontSize: icon != null ? 15 : 18,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularNums)),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(trailingIcon, size: 15, color: Brand.orange),
              ],
            ],
          ),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? cell
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: cell,
              ),
            ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
          width: 38, height: 38, child: Icon(icon, size: 16, color: Brand.text)),
    );
  }
}
