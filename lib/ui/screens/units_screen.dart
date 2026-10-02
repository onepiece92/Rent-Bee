import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../sheets/edit_unit_sheet.dart';
import '../sheets/unit_detail_sheet.dart';
import '../widgets/glass.dart';

/// Directory of all units (active + inactive), independent of the month's
/// paid/pending state. Tap a unit to open its detail/edit sheet.
class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // The directory depends on the loaded rows only — not on the Ledger's
    // search text or filter — so rebuild per data load, not per notification.
    context.select<LedgerProvider, int>((l) => l.dataRevision);
    final ledger = context.read<LedgerProvider>();
    final currency = context.watch<SettingsProvider>().currency;
    final units = ledger.allUnitsByCode;
    final activeRent = units
        .where((r) => r.unit.isActive)
        .fold<int>(0, (a, r) => a + r.unit.monthlyRent);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // Large Title row with the primary action at the trailing end, and
          // a one-line subhead of the directory's totals.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sys.gutter, 14, Sys.gutter, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Units',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.largeTitle.colored(sys.label)),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Add Unit',
                        icon: Icons.add,
                        kind: ButtonKind.prominentGlass,
                        compact: true,
                        onTap: () => EditUnitSheet.show(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${units.length} total · ${ledger.activeUnitCount} active · '
                    '${Money.format(activeRent, currency)}/mo expected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.subhead.colored(sys.secondaryLabel).tabular,
                  ),
                ],
              ),
            ),
          ),
          if (units.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No units yet — tap ＋ to add one.',
                    style: Type.subhead.colored(sys.secondaryLabel)),
              ),
            )
          else
            // One grouped card of rows: the card colour is painted behind the
            // lazy sliver, so a long directory still builds on demand.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 120),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: sys.card,
                  borderRadius: BorderRadius.circular(Sys.radiusCard),
                ),
                sliver: SliverList.separated(
                  itemCount: units.length,
                  separatorBuilder: (_, _) =>
                      const Hairline(inset: 16 + 44 + 12),
                  itemBuilder: (context, i) {
                    final s = units[i].unit;
                    // A transparent Material of its own, so the press ink
                    // paints above the card colour behind the list.
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => UnitDetailSheet.show(context, s.id),
                        borderRadius: _rowRadius(i, units.length),
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(minHeight: Sys.minTapTarget),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sys.gutter, vertical: 12),
                            child: SplitRow(
                              leading: CodeAvatar(code: s.code, paid: false),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.tenantName,
                                      maxLines: TextSize.large(context) ? 2 : 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Type.body.semibold
                                          .colored(sys.label)),
                                  Text(
                                    s.businessType.isEmpty
                                        ? '—'
                                        : s.businessType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Type.footnote
                                        .colored(sys.secondaryLabel),
                                  ),
                                ],
                              ),
                              trailing: (context, stacked) {
                                final rent = Text(
                                    Money.format(s.monthlyRent, currency),
                                    style: Type.subhead.semibold.tabular
                                        .colored(sys.label));
                                final badge = _ActiveBadge(active: s.isActive);
                                // Under the name at large text sizes; at the
                                // trailing edge otherwise.
                                return stacked
                                    ? Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 12,
                                        runSpacing: 6,
                                        children: [rent, badge],
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: rent),
                                          const SizedBox(height: 6),
                                          badge,
                                        ],
                                      );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ink shape for a row of the grouped list: the first and last rows follow the
/// card's rounded corners so a press never paints outside them.
BorderRadius _rowRadius(int i, int count) => BorderRadius.vertical(
      top: i == 0 ? const Radius.circular(Sys.radiusCard) : Radius.zero,
      bottom:
          i == count - 1 ? const Radius.circular(Sys.radiusCard) : Radius.zero,
    );

/// Active / vacant as a [StatusBadge] — a word, never colour alone.
class _ActiveBadge extends StatelessWidget {
  final bool active;
  const _ActiveBadge({required this.active});
  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return active
        ? StatusBadge(
            label: 'Active', color: sys.green, textColor: sys.greenText)
        : StatusBadge(
            label: 'Vacant',
            color: sys.secondaryLabel,
            textColor: sys.secondaryLabel);
  }
}
