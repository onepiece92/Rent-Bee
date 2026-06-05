import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../widgets/glass_dialog.dart';
import 'sheet_buttons.dart';

/// Variable per-month charges (electricity / water / service) for the unit,
/// tracked separately from rent. Loads the selected month's row and offers an
/// edit dialog. Reloads when the ledger changes or the month switches.
class ChargesSection extends StatefulWidget {
  final int unitId;
  final BsMonth month;
  const ChargesSection({super.key, required this.unitId, required this.month});

  @override
  State<ChargesSection> createState() => _ChargesSectionState();
}

class _ChargesSectionState extends State<ChargesSection> {
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
  void didUpdateWidget(covariant ChargesSection old) {
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
    final mode = context.watch<SettingsProvider>().calendar;
    return FutureBuilder<Charge?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done) _last = snap.data;
        final c = snap.hasData ? snap.data : _last;
        final e = c?.electricity ?? 0;
        final w = c?.water ?? 0;
        final s = c?.service ?? 0;
        final total = e + w + s;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Charges · ${widget.month.monthNameIn(mode)}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Brand.muted,
                          letterSpacing: 0.2)),
                ),
                SecondaryButton(
                  icon: Icons.edit_outlined,
                  label: total == 0 ? 'Add' : 'Edit',
                  onTap: () => _edit(c),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Brand.glassBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Brand.glassBorder),
              ),
              child: Column(
                children: [
                  _ChargeRow(
                      icon: Icons.bolt_outlined,
                      label: 'Electricity',
                      amount: e),
                  const _Hair(),
                  _ChargeRow(
                      icon: Icons.water_drop_outlined,
                      label: 'Water',
                      amount: w),
                  const _Hair(),
                  _ChargeRow(
                      icon: Icons.handyman_outlined,
                      label: 'Service / other',
                      amount: s),
                  const _Hair(),
                  _ChargeRow(label: 'Total', amount: total, bold: true),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(Charge? c) async {
    String pre(int v) => v == 0 ? '' : v.toString();
    final eCtrl = TextEditingController(text: pre(c?.electricity ?? 0));
    final wCtrl = TextEditingController(text: pre(c?.water ?? 0));
    final sCtrl = TextEditingController(text: pre(c?.service ?? 0));

    final saved = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: 'Charges · ${widget.month.monthName} ${widget.month.year}',
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
    await _ledger.setCharges(
      widget.unitId,
      electricity: int.tryParse(eCtrl.text.trim()) ?? 0,
      water: int.tryParse(wCtrl.text.trim()) ?? 0,
      service: int.tryParse(sCtrl.text.trim()) ?? 0,
    );
  }
}

class _ChargeRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final int amount;
  final bool bold;
  const _ChargeRow({
    this.icon,
    required this.label,
    required this.amount,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? Brand.text : Brand.muted,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(amount == 0 && !bold ? '—' : Money.format(amount),
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
