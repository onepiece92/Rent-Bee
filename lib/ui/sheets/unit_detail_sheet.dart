import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../util/sms_reminder.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/sheet_scaffold.dart';
import '../widgets/tap_target.dart';
import 'charges_section.dart';
import 'deposit_cell.dart';
import 'edit_unit_sheet.dart';
import 'sheet_buttons.dart';

/// Bottom sheet: unit details, Collect/Undo for the selected month,
/// edit/delete, and a 6-month history strip.
class UnitDetailSheet extends StatelessWidget {
  final int unitId;
  const UnitDetailSheet({super.key, required this.unitId});

  static Future<void> show(BuildContext context, int unitId) {
    return showSheet(
      context,
      (_) => UnitDetailSheet(unitId: unitId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final ledger = context.watch<LedgerProvider>();
    final settings = context.watch<SettingsProvider>();
    final mode = settings.calendar;
    final currency = settings.currency;
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
                      style: Type.title3.semibold.colored(sys.label)),
                  Text(s.businessType.isEmpty ? s.code : s.businessType,
                      style: Type.subhead.colored(sys.secondaryLabel)),
                ],
              ),
            ),
            _IconBtn(
                icon: Icons.edit_outlined,
                onTap: () => EditUnitSheet.show(context, unit: s)),
            _IconBtn(
                icon: Icons.delete_outline,
                destructive: true,
                onTap: () => _confirmDelete(context, ledger, s)),
          ],
        ),
        const SizedBox(height: 18),

        // detail grid
        Row(
          children: [
            _DetailCell(
                label: 'Monthly rent',
                value: Money.format(s.monthlyRent, currency)),
            const SizedBox(width: 11),
            _DetailCell(
              label: 'Contact',
              value: (s.phone == null || s.phone!.isEmpty) ? '—' : s.phone!,
              icon: Icons.phone,
              // Tap to text the tenant; only when a number is on file.
              // `isPaid` (settled in full) — a partial payment must still send
              // the reminder, not the thank-you.
              onTap: (s.phone == null || s.phone!.isEmpty)
                  ? null
                  : () => sendRentReminder(context, s, ledger.month,
                      paid: row.isPaid,
                      amount: row.totalDue,
                      currency: currency),
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
        const SizedBox(height: 11),
        Row(children: [DepositCell(unit: s)]),
        const SizedBox(height: 16),

        // big Collect / Undo button
        _BigToggleButton(row: row, month: ledger.month),

        const SizedBox(height: 20),
        // Charges + deduction sections, fed by a single charges-row load.
        UnitMonthAdjustments(
            unitId: s.id, monthlyRent: s.monthlyRent, month: ledger.month),

        const SizedBox(height: 20),
        const SectionTitle('Recent months',
            padding: EdgeInsets.only(bottom: 8)),
        _HistoryStrip(unitId: s.id),
      ],
    );
  }


  Future<void> _confirmDelete(
      BuildContext context, LedgerProvider ledger, Unit s) async {
    final ok = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Delete Unit?',
        content: Text(
            'This removes ${s.code} (${s.tenantName}) and all its payment history.'),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction('Delete',
              destructive: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) {
      await ledger.deleteUnit(s.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// "Rs 15,000 rent + Rs 800 charges − Rs 500 deducted" — the month's due
/// spelled out, with zero parts omitted. Shown wherever the due differs from
/// the headline rent so the math stays transparent.
String _dueBreakdown(UnitRow row, Currency currency) => [
      '${Money.format(row.unit.monthlyRent, currency)} rent',
      if (row.charges > 0) '+ ${Money.format(row.charges, currency)} charges',
      if (row.deduction > 0)
        '− ${Money.format(row.deduction, currency)} deducted',
    ].join(' ');

class _BigToggleButton extends StatelessWidget {
  final UnitRow row;
  final BsMonth month;
  const _BigToggleButton({required this.row, required this.month});

  Unit get unit => row.unit;
  Payment? get payment => row.payment;

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final ledger = context.read<LedgerProvider>();
    final settings = context.watch<SettingsProvider>();
    final mode = settings.calendar;
    final currency = settings.currency;
    // Everything here is against the month's *due* — rent plus utility
    // charges, less any deduction for goods taken from the shop — not the
    // headline rent.
    final due = row.totalDue;
    final paidAmount = row.paidAmount;

    switch (row.status) {
      case PayStatus.paid:
        if (payment == null) {
          // The deduction alone covered the rent — no cash to collect or undo.
          return const AppButton(
            label: 'Covered by deduction · nothing to collect',
            onTap: null,
            kind: ButtonKind.gray,
            expand: true,
          );
        }
        final paidOn = payment!.paidOn;
        final on = paidOn != null ? dateLabel(paidOn, mode) : '—';
        return _PaidCapsule(
          label: 'Paid $on · tap to undo',
          onTap: () => ledger.undo(unit.id),
        );

      case PayStatus.partial:
        final remaining = row.remaining;
        return Column(
          children: [
            Text(
                '${Money.format(paidAmount, currency)} of '
                '${Money.format(due, currency)} paid',
                textAlign: TextAlign.center,
                style: Type.footnote.colored(sys.secondaryLabel).tabular),
            const SizedBox(height: 6),
            AppButton(
              label: 'Collect remaining '
                  '${Money.format(remaining, currency)}',
              onTap: () => ledger.markPaid(unit), // settle the rest in full
              kind: ButtonKind.prominent,
              expand: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit amount',
                    onTap: () => _recordPartial(context, ledger),
                    expand: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    icon: Icons.close,
                    label: 'Undo',
                    onTap: () => ledger.undo(unit.id),
                    kind: ButtonKind.gray,
                    compact: true,
                    expand: true,
                  ),
                ),
              ],
            ),
          ],
        );

      case PayStatus.pending:
        if (due == 0) {
          // Rent 0, no charges and nothing deducted: there is nothing to
          // collect, and a Collect tap would only write an empty payment row.
          return const AppButton(
            label: 'No rent set for this unit',
            onTap: null,
            kind: ButtonKind.gray,
            expand: true,
          );
        }
        return Column(
          children: [
            AppButton(
              label: 'Collect ${Money.format(due, currency)} for '
                  '${month.monthNameIn(mode)}',
              icon: Icons.arrow_downward,
              onTap: () => ledger.markPaid(unit),
              kind: ButtonKind.prominent,
              expand: true,
            ),
            if (row.charges > 0 || row.deduction > 0) ...[
              const SizedBox(height: 6),
              Text(_dueBreakdown(row, currency),
                  textAlign: TextAlign.center,
                  style: Type.footnote.colored(sys.secondaryLabel).tabular),
            ],
            const SizedBox(height: 10),
            SecondaryButton(
              icon: Icons.pie_chart_outline,
              label: 'Record partial amount',
              onTap: () => _recordPartial(context, ledger),
              expand: true,
            ),
          ],
        );
    }
  }

  /// Prompts for the total amount received this month and records it. An empty
  /// or zero value clears the month (undo); anything >= the due settles it
  /// fully.
  Future<void> _recordPartial(
      BuildContext context, LedgerProvider ledger) async {
    final currency = context.read<SettingsProvider>().currency;
    final ctrl = TextEditingController(
        text: payment == null ? '' : payment!.amount.toString());
    final result = await showGlassDialog<int>(
      context,
      (ctx) => GlassDialog(
        title: 'Amount received',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.charges > 0 || row.deduction > 0
                  ? 'Due is ${Money.format(row.totalDue, currency)} '
                      '(${_dueBreakdown(row, currency)}). Enter the '
                      'total received for ${month.monthName} ${month.year}.'
                  : 'Rent is ${Money.format(unit.monthlyRent, currency)}. '
                      'Enter the total received for ${month.monthName} '
                      '${month.year}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: currency.symbol,
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          GlassDialogAction('Cancel', onPressed: () => Navigator.pop(ctx)),
          GlassDialogAction(
            'Save',
            primary: true,
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
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

/// The settled state of the Collect button: a full-width green-washed capsule
/// with a check, tappable to undo. Same 44 pt minimum and press state as
/// [AppButton]; only the colours are the paid ones.
class _PaidCapsule extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PaidCapsule({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Pressable(
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Sys.wash(sys.green),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sys.minTapTarget),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, size: 18, color: sys.greenText),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.body.semibold.colored(sys.greenText)),
                    ),
                  ],
                ),
              ),
            ),
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

  Future<List<HistoryEntry>> _load() => _ledger.historyFor(widget.unitId,
      months: 6,
      // Price each month at the rent in effect then, not today's rent.
      percent: context.read<SettingsProvider>().annualRaisePercent);

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
            for (final e in entries) _HistoryCell(entry: e, mode: mode),
          ],
        );
      },
    );
  }
}

/// One month in the history strip: a status chip above its short month label.
class _HistoryCell extends StatelessWidget {
  final HistoryEntry entry;
  final CalendarMode mode;
  const _HistoryCell({required this.entry, required this.mode});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Column(
      children: [
        _HistoryChip(entry: entry),
        const SizedBox(height: 6),
        Text(BsMonth(entry.year, entry.month).shortMonthNameIn(mode),
            style: Type.caption2.colored(sys.secondaryLabel)),
      ],
    );
  }
}

/// Status chip: full = green wash + check, partial = green filled from the
/// left in proportion to the fraction paid, unpaid = faint with a dash.
class _HistoryChip extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryChip({required this.entry});

  static const _size = 36.0;
  static const _radius = BorderRadius.all(Radius.circular(11));

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    if (entry.isPaid) {
      return Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Sys.wash(sys.green),
          borderRadius: _radius,
        ),
        child: Icon(Icons.check, size: 16, color: sys.greenText),
      );
    }
    if (entry.isPartial) {
      return SizedBox(
        width: _size,
        height: _size,
        child: ClipRRect(
          borderRadius: _radius,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: sys.fill)),
              // Green fill from the left, proportional to the fraction paid.
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: entry.progress,
                  heightFactor: 1,
                  child: ColoredBox(color: sys.green),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // unpaid
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sys.fill,
        borderRadius: _radius,
      ),
      child: Text('–',
          style: Type.subhead.semibold.colored(sys.secondaryLabel)),
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
    final sys = Sys.of(context);
    return Expanded(
      child: Well(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Type.caption1.colored(sys.secondaryLabel)),
            const SizedBox(height: 3),
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: sys.secondaryLabel),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.body.semibold.colored(sys.label).tabular),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 6),
                  Icon(trailingIcon, size: 16, color: sys.tintText),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  const _IconBtn(
      {required this.icon, required this.onTap, this.destructive = false});
  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // Drawn at 36 pt; TapTarget pads the hit area out to the HIG's 44 pt.
    return TapTarget(
      onTap: onTap,
      child: Well(
        padding: EdgeInsets.zero,
        child: SizedBox.square(
          dimension: 36,
          child: Icon(icon,
              size: 18, color: destructive ? sys.redText : sys.label),
        ),
      ),
    );
  }
}
