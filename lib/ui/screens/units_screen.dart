import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../sheets/unit_detail_sheet.dart';
import '../widgets/glass.dart';

/// Directory of all units (active + inactive), independent of the month's
/// paid/pending state. Tap a unit to open its detail/edit sheet.
class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final units = ledger.allUnitsByCode;
    final activeRent = units
        .where((r) => r.unit.isActive)
        .fold<int>(0, (a, r) => a + r.unit.monthlyRent);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Units',
                      style: display(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${units.length} total · ${ledger.activeUnitCount} active · '
                    '${Money.format(activeRent)}/mo expected',
                    style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
          if (units.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No units yet — tap ＋ to add one.',
                    style: TextStyle(color: Brand.muted)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 120),
              sliver: SliverList.separated(
                itemCount: units.length,
                separatorBuilder: (_, i) => const SizedBox(height: 9),
                itemBuilder: (context, i) {
                  final s = units[i].unit;
                  return GlassPanel(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => UnitDetailSheet.show(context, s.id),
                    child: Row(
                      children: [
                        CodeAvatar(code: s.code, paid: false),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.tenantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 1),
                              Text(
                                s.businessType.isEmpty ? '—' : s.businessType,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Brand.muted, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money.format(s.monthlyRent),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: tabularNums)),
                            const SizedBox(height: 6),
                            _ActiveBadge(active: s.isActive),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final bool active;
  const _ActiveBadge({required this.active});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
            color: active ? Brand.glassBorder : Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(active ? 'Active' : 'Vacant',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Brand.muted : const Color(0x80FFFFFF))),
    );
  }
}
