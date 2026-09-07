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
import '../widgets/glass_dialog.dart';
import 'sheet_buttons.dart';

/// Heading style shared by the per-month sections on the unit sheet.
const _sectionTitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: Brand.muted,
    letterSpacing: 0.2);

/// Loads the (unit, month) charges row once and feeds it to both
/// [ChargesSection] and [DeductionSection] — one query per ledger change
/// instead of one per section. Reloads when the ledger notifies or the
/// month/unit switches, keeping the last row on screen while a reload is in
/// flight so nothing flashes.
class UnitMonthAdjustments extends StatefulWidget {
  final int unitId;
  final int monthlyRent;
  final BsMonth month;
  const UnitMonthAdjustments({
    super.key,
    required this.unitId,
    required this.monthlyRent,
    required this.month,
  });

  @override
  State<UnitMonthAdjustments> createState() => _UnitMonthAdjustmentsState();
}

class _UnitMonthAdjustmentsState extends State<UnitMonthAdjustments> {
  late final LedgerProvider _ledger;
  late Future<Charge?> _future;
  Charge? _last;

  @override
  void initState() {
    super.initState();
    _ledger = context.read<LedgerProvider>();
    _future = _ledger.chargesFor(widget.unitId);
    _ledger.addListener(_reload);
  }

  void _reload() {
    if (mounted) {
      setState(() => _future = _ledger.chargesFor(widget.unitId));
    }
  }

  @override
  void didUpdateWidget(covariant UnitMonthAdjustments old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month || old.unitId != widget.unitId) _reload();
  }

  @override
  void dispose() {
    _ledger.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Charge?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done) _last = snap.data;
        final c = snap.hasData ? snap.data : _last;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChargesSection(unitId: widget.unitId, month: widget.month, charge: c),
            const SizedBox(height: 20),
            DeductionSection(
              unitId: widget.unitId,
              monthlyRent: widget.monthlyRent,
              month: widget.month,
              charge: c,
            ),
          ],
        );
      },
    );
  }
}

/// Variable per-month charges (electricity / water / service) for the unit,
/// tracked separately from rent. Shows the month's [charge] row and offers an
/// edit dialog.
class ChargesSection extends StatelessWidget {
  final int unitId;
  final BsMonth month;
  final Charge? charge; // null = nothing recorded this month
  const ChargesSection({
    super.key,
    required this.unitId,
    required this.month,
    required this.charge,
  });

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsProvider>().calendar;
    final e = charge?.electricity ?? 0;
    final w = charge?.water ?? 0;
    final s = charge?.service ?? 0;
    final total = e + w + s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Charges · ${month.monthNameIn(mode)}',
                  style: _sectionTitle),
            ),
            SecondaryButton(
              icon: Icons.edit_outlined,
              label: total == 0 ? 'Add' : 'Edit',
              onTap: () => _edit(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Card(
          children: [
            _ChargeRow(
                icon: Icons.bolt_outlined, label: 'Electricity', amount: e),
            const _Hair(),
            _ChargeRow(
                icon: Icons.water_drop_outlined, label: 'Water', amount: w),
            const _Hair(),
            _ChargeRow(
                icon: Icons.handyman_outlined,
                label: 'Service / other',
                amount: s),
            const _Hair(),
            _ChargeRow(label: 'Total', amount: total, bold: true),
          ],
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    String pre(int v) => v == 0 ? '' : v.toString();
    final eCtrl = TextEditingController(text: pre(charge?.electricity ?? 0));
    final wCtrl = TextEditingController(text: pre(charge?.water ?? 0));
    final sCtrl = TextEditingController(text: pre(charge?.service ?? 0));

    final saved = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Charges · ${month.monthName} ${month.year}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChargeField(controller: eCtrl, label: 'Electricity'),
            const SizedBox(height: 10),
            _ChargeField(controller: wCtrl, label: 'Water'),
            const SizedBox(height: 10),
            _ChargeField(controller: sCtrl, label: 'Service / other'),
          ],
        ),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction('Save',
              primary: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (saved != true) return;
    await ledger.setCharges(
      unitId,
      electricity: int.tryParse(eCtrl.text.trim()) ?? 0,
      water: int.tryParse(wCtrl.text.trim()) ?? 0,
      service: int.tryParse(sCtrl.text.trim()) ?? 0,
    );
  }
}

/// The landlord's deduction from this month's rent — e.g. goods bought from
/// the tenant's shop and settled against rent instead of cash. Reads the same
/// (unit, month) [charge] row as [ChargesSection]; the amount comes off the
/// month's due everywhere (Collect button, paid status, summaries, reports).
class DeductionSection extends StatelessWidget {
  final int unitId;
  final int monthlyRent;
  final BsMonth month;
  final Charge? charge; // null = nothing recorded this month
  const DeductionSection({
    super.key,
    required this.unitId,
    required this.monthlyRent,
    required this.month,
    required this.charge,
  });

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsProvider>().calendar;
    final d = charge?.deduction ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Deduction · ${month.monthNameIn(mode)}',
                  style: _sectionTitle),
            ),
            SecondaryButton(
              icon: Icons.edit_outlined,
              label: d == 0 ? 'Add' : 'Edit',
              onTap: () => _edit(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Card(
          children: [
            _ChargeRow(
                icon: Icons.storefront_outlined,
                label: 'Bought from this unit',
                note: charge?.deductionNote,
                amount: d,
                negative: true),
            const _Hair(),
            _ChargeRow(
                label: 'Rent due after deduction',
                amount: netDue(monthlyRent, d),
                bold: true),
          ],
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final ledger = context.read<LedgerProvider>();
    final d = charge?.deduction ?? 0;
    final amountCtrl = TextEditingController(text: d == 0 ? '' : d.toString());
    final noteCtrl = TextEditingController(text: charge?.deductionNote ?? '');

    final saved = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Deduction · ${month.monthName} ${month.year}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Taken off the ${Money.format(monthlyRent)} rent — e.g. goods '
              'or services you took from this shop. Leave blank to clear.',
              style: const TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _ChargeField(controller: amountCtrl, label: 'Deduct'),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for (optional)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction('Save',
              primary: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (saved != true) return;
    await ledger.setDeduction(
      unitId,
      amount: int.tryParse(amountCtrl.text.trim()) ?? 0,
      note: noteCtrl.text,
    );
  }
}

/// Glass card holding a section's rows.
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Brand.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.glassBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? note; // muted second line, e.g. what a deduction was for
  final int amount;
  final bool bold;
  final bool negative; // show a non-zero amount as "− Rs x"
  const _ChargeRow({
    this.icon,
    required this.label,
    this.note,
    required this.amount,
    this.bold = false,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = note != null && note!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Brand.muted),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 23),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: bold ? Brand.text : Brand.muted,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
                if (hasNote)
                  Text(note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: Brand.muted)),
              ],
            ),
          ),
          Text(
              amount == 0 && !bold
                  ? '—'
                  : '${negative ? '− ' : ''}${Money.format(amount)}',
              style: display(
                  fontSize: bold ? 15 : 14,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  fontFeatures: tabularNums)),
        ],
      ),
    );
  }
}

class _Hair extends StatelessWidget {
  const _Hair();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: Brand.glassBorder);
}

class _ChargeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _ChargeField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'Rs ',
        isDense: true,
      ),
    );
  }
}
