import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';

/// Security-deposit cell: shows the held amount and whether it has been
/// refunded, with a button to flip between held and refunded. Hidden controls
/// when no deposit is on file (amount 0). Sits inside a `Row`.
class DepositCell extends StatelessWidget {
  final Unit unit;
  const DepositCell({super.key, required this.unit});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final ledger = context.read<LedgerProvider>();
    final settings = context.watch<SettingsProvider>();
    final mode = settings.calendar;
    final currency = settings.currency;
    final has = unit.depositAmount > 0;
    final refunded = unit.depositRefunded;
    final sub = !has
        ? null
        : refunded
            ? 'Refunded${unit.depositRefundedOn != null ? ' · ${dateLabel(unit.depositRefundedOn!, mode)}' : ''}'
            : 'Held';

    return Expanded(
      child: Well(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Security deposit',
                      style: Type.caption1.colored(sys.secondaryLabel)),
                  const SizedBox(height: 3),
                  Text(
                      has
                          ? Money.format(unit.depositAmount, currency)
                          : 'None',
                      style: Type.body.semibold.colored(sys.label).tabular),
                  if (sub != null) ...[
                    const SizedBox(height: 6),
                    // Held = green, refunded = neutral; the word carries the
                    // status, the colour only reinforces it.
                    StatusBadge(
                      label: sub,
                      color: refunded ? sys.secondaryLabel : sys.green,
                      textColor: refunded ? sys.secondaryLabel : sys.greenText,
                    ),
                  ],
                ],
              ),
            ),
            if (has) ...[
              const SizedBox(width: 8),
              AppButton(
                label: refunded ? 'Mark held' : 'Refund',
                onTap: () => _toggle(context, ledger),
                kind: ButtonKind.tinted,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, LedgerProvider ledger) async {
    final next = !unit.depositRefunded;
    final currency = context.read<SettingsProvider>().currency;
    final ok = await showGlassDialog<bool>(
      context,
      (ctx) => GlassDialog(
        title: next ? 'Refund deposit?' : 'Mark as held?',
        content: Text(next
            ? 'Mark the ${Money.format(unit.depositAmount, currency)} deposit '
                'as returned to ${unit.tenantName}.'
            : 'Mark the ${Money.format(unit.depositAmount, currency)} deposit '
                'as currently held again.'),
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
