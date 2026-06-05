import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../widgets/glass_dialog.dart';

/// Security-deposit cell: shows the held amount and whether it has been
/// refunded, with a chip to flip between held and refunded. Hidden controls
/// when no deposit is on file (amount 0). Sits inside a `Row`.
class DepositCell extends StatelessWidget {
  final Unit unit;
  const DepositCell({super.key, required this.unit});

  @override
  Widget build(BuildContext context) {
    final ledger = context.read<LedgerProvider>();
    final mode = context.watch<SettingsProvider>().calendar;
    final has = unit.depositAmount > 0;
    final refunded = unit.depositRefunded;
    final sub = !has
        ? null
        : refunded
            ? 'Refunded${unit.depositRefundedOn != null ? ' · ${dateLabel(unit.depositRefundedOn!, mode)}' : ''}'
            : 'Held';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Brand.glassBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.glassBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Security deposit',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Brand.muted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(has ? Money.format(unit.depositAmount) : 'None',
                      style: display(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularNums)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: refunded ? Brand.muted : Brand.paidText,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            if (has)
              InkWell(
                onTap: () => _toggle(context, ledger),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: Brand.glassBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.glassBorder),
                  ),
                  child: Text(refunded ? 'Mark held' : 'Refund',
                      style: const TextStyle(
                          color: Brand.orangeSoft,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, LedgerProvider ledger) async {
    final next = !unit.depositRefunded;
    final ok = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: next ? 'Refund deposit?' : 'Mark as held?',
        content: Text(next
            ? 'Mark the ${Money.format(unit.depositAmount)} deposit as '
                'returned to ${unit.tenantName}.'
            : 'Mark the ${Money.format(unit.depositAmount)} deposit as '
                'currently held again.'),
        actions: [
          GlassDialogAction('Cancel',
              onPressed: () => Navigator.pop(ctx, false)),
          GlassDialogAction(next ? 'Refund' : 'Mark held',
              primary: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) await ledger.setDepositRefunded(unit, next);
  }
}
