import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../sheets/edit_unit_sheet.dart';
import '../sheets/unit_detail_sheet.dart';
import '../util/sms_reminder.dart';
import '../widgets/glass.dart';
import '../widgets/sponsored_carousel.dart';
import '../widgets/sync_badge.dart';
import '../widgets/tap_target.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => context.read<LedgerProvider>().refresh(),
        color: sys.tint,
        backgroundColor: sys.card,
        child: CustomScrollView(
          // Stay scrollable even when content is short, so pull-to-refresh
          // works on an empty ledger.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Each section selects only the slice it needs, so typing in the
            // search box (or a mark-paid refresh) rebuilds just the list below
            // — not the header or summary above.
            SliverToBoxAdapter(
              child: Selector<LedgerProvider, BsMonth>(
                selector: (_, l) => l.month,
                builder: (_, month, _) => _Header(month: month),
              ),
            ),
            SliverToBoxAdapter(
              child: Selector<LedgerProvider, MonthSummary>(
                selector: (_, l) => l.summary,
                builder: (_, summary, _) => _SummaryCard(summary: summary),
              ),
            ),
            SliverToBoxAdapter(
              child: _SearchAndFilter(controller: _searchCtrl),
            ),
            // List / empty / loading — its own Consumer so search, filter, and
            // refresh rebuild only this region.
            Consumer<LedgerProvider>(
              builder: (context, ledger, _) {
                final sys = Sys.of(context);
                if (ledger.loading) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final rows = ledger.visibleRows; // read once (was O(N²) below)
                if (rows.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _Empty(noUnits: ledger.totalCount == 0),
                  );
                }
                // One grouped card of rows: the card colour is painted behind
                // the lazy sliver, so a long ledger still builds on demand.
                return SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 10),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: sys.card,
                      borderRadius: BorderRadius.circular(Sys.radiusCard),
                    ),
                    sliver: SliverList.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          const Hairline(inset: 16 + 44 + 12),
                      itemBuilder: (context, i) => _UnitTile(
                        row: rows[i],
                        borderRadius: _rowRadius(i, rows.length),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Sponsored carousel — outside the list, shown even when empty.
            const SliverToBoxAdapter(child: SponsoredCarousel()),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
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

class _Header extends StatelessWidget {
  final BsMonth month;
  const _Header({required this.month});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final mode = context.watch<SettingsProvider>().calendar;
    // Nav callbacks only — read (not watch) so the header rebuilds solely on
    // the `month` the parent Selector feeds it.
    final ledger = context.read<LedgerProvider>();
    // The real current BS month, for the "jump to today" chip.
    final today = bsYearMonth(DateTime.now());
    final currentMonth = BsMonth(today.year, today.month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 14, Sys.gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Large Title row: the selected month, with the month arrows and the
          // primary action as toolbar buttons at the trailing end.
          Row(
            children: [
              // Long month names ("September", "Baishakh") scale down rather
              // than truncate when the toolbar needs the room.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    month.monthNameIn(mode),
                    maxLines: 1,
                    style: Type.largeTitle.colored(sys.label),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Icons.chevron_left,
                semanticLabel: 'Previous month',
                onTap: ledger.previousMonth,
              ),
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.chevron_right,
                semanticLabel: 'Next month',
                onTap: ledger.nextMonth,
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
          // Subhead: the year in the active calendar and the app name, the
          // cloud-sync state (hidden when not signed in / local-only), and
          // today's date — tap to jump back to the current month.
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${month.yearIn(mode)} · Rent Bee',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.subhead.colored(sys.secondaryLabel).tabular,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SyncBadge(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TodayChip(
                mode: mode,
                isCurrent: month == currentMonth,
                onTap: () => ledger.setMonth(currentMonth),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small chip in the header showing today's date in the active calendar.
/// Tapping it jumps the ledger back to the current month; when the selected
/// month differs from today, the chip takes the tinted "return to today" look.
class _TodayChip extends StatelessWidget {
  final CalendarMode mode;
  final bool isCurrent;
  final VoidCallback onTap;
  const _TodayChip({
    required this.mode,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = !isCurrent; // viewing another month → actionable accent
    return AppButton(
      label: todayLabel(mode),
      icon: accent ? Icons.undo_rounded : Icons.today,
      kind: accent ? ButtonKind.tinted : ButtonKind.plain,
      compact: true,
      onTap: onTap,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MonthSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final currency = context.watch<SettingsProvider>().currency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 8),
      child: GroupedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collected this month',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.title3.semibold.colored(sys.label),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.percent}%',
                  style: Type.subhead.semibold.colored(sys.tintText).tabular,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Money.format(summary.collected, currency),
              style: Type.largeTitle.tabular.colored(sys.label),
            ),
            const SizedBox(height: 2),
            Text(
              'of ${Money.format(summary.expected, currency)} expected',
              style: Type.footnote.colored(sys.secondaryLabel).tabular,
            ),
            const SizedBox(height: 14),
            ProgressBar(value: summary.progress),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatChip(
                  icon: Icons.check_circle,
                  iconColor: sys.greenText,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${summary.paidCount}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: '/${summary.activeCount} paid'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.schedule,
                  iconColor: sys.orangeText,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: Money.format(summary.pending, currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: ' pending'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two stat wells under the progress bar: an icon in a status
/// colour and a footnote line.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Widget child;
  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Expanded(
      child: Well(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: DefaultTextStyle.merge(
                style: Type.footnote.colored(sys.label).tabular,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  const _SearchAndFilter({required this.controller});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // Scoped to its own widget so the query/filter watch rebuilds only this
    // bar, not the header or summary above.
    final ledger = context.watch<LedgerProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 8),
      child: Column(
        children: [
          // Search capsule (kit): tertiarySystemFill, no border, 16 pt text.
          Container(
            constraints: const BoxConstraints(minHeight: Sys.minTapTarget),
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: sys.tertiaryFill,
              borderRadius: BorderRadius.circular(Sys.radiusCapsule),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: sys.secondaryLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: ledger.setQuery,
                    style: Type.callout.colored(sys.label),
                    decoration: InputDecoration(
                      isDense: true,
                      // The capsule already carries the fill — opt out of the
                      // theme's filled field background and borders.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      hintText: 'Search tenant or unit…',
                      hintStyle: Type.callout.colored(sys.tertiaryLabel),
                    ),
                  ),
                ),
                if (ledger.query.isNotEmpty)
                  TapTarget(
                    onTap: () {
                      controller.clear();
                      ledger.setQuery('');
                    },
                    child: Icon(Icons.close, size: 18, color: sys.secondaryLabel),
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SegmentedControl<LedgerFilter>(
            values: LedgerFilter.values,
            selected: ledger.filter,
            label: (f) => switch (f) {
              LedgerFilter.all => 'All',
              LedgerFilter.pending => 'Pending',
              LedgerFilter.paid => 'Paid',
            },
            onChanged: ledger.setFilter,
          ),
        ],
      ),
    );
  }
}

/// One row of the ledger's grouped card: avatar, tenant, what's due and the
/// row's actions. Tap anywhere on the row for the unit's detail sheet.
class _UnitTile extends StatelessWidget {
  final UnitRow row;
  final BorderRadius borderRadius;
  const _UnitTile({required this.row, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final s = row.unit;
    final paid = row.isPaid;
    final currency = context.watch<SettingsProvider>().currency;
    // A transparent Material of its own, so the press ink paints above the
    // card colour that DecoratedSliver draws behind the list.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => UnitDetailSheet.show(context, s.id),
        borderRadius: borderRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sys.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Sys.gutter, vertical: 12),
            child: Row(
              children: [
                CodeAvatar(code: s.code, paid: paid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.tenantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.body.semibold.colored(sys.label),
                      ),
                      Text(
                        s.businessType.isEmpty ? '—' : s.businessType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.footnote.colored(sys.secondaryLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // What's due this month — rent plus utility charges, less
                    // any deduction for goods taken from the shop — so the row
                    // matches the Collect action.
                    Text(
                      Money.format(row.totalDue, currency),
                      style: Type.subhead.semibold.tabular.colored(sys.label),
                    ),
                    if (row.charges > 0 || row.deduction > 0)
                      Text(
                        [
                          if (row.charges > 0)
                            '+ ${Money.format(row.charges, currency)} charges',
                          if (row.deduction > 0)
                            '− ${Money.format(row.deduction, currency)} deducted',
                        ].join(' · '),
                        style:
                            Type.caption2.colored(sys.secondaryLabel).tabular,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A vacated unit is display-only: no rent reminder to
                        // a former tenant, no mark-paid — just a Vacant badge.
                        // (Late back-payments can still be recorded from the
                        // detail sheet.)
                        if (!s.isActive)
                          const _VacantPill()
                        else ...[
                          // Quick rent reminder — only when a phone is on file.
                          if (s.phone != null && s.phone!.isNotEmpty) ...[
                            _CardSmsButton(
                              onTap: () => sendRentReminder(
                                context,
                                s,
                                context.read<LedgerProvider>().month,
                                paid: paid,
                                amount: row.totalDue,
                                currency: currency,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          switch (row.status) {
                            PayStatus.paid => const StatusPill(paid: true),
                            PayStatus.partial => _PartialPill(
                                remaining: row.remaining, currency: currency),
                            // Nothing to collect (rent not set) → no pill.
                            PayStatus.pending when row.totalDue == 0 =>
                              const SizedBox.shrink(),
                            PayStatus.pending => _MarkPaidPill(
                              onTap: () =>
                                  context.read<LedgerProvider>().markPaid(s),
                            ),
                          },
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact SMS-reminder button on a unit row. Its own tap target, so it fires
/// the reminder without opening the detail sheet behind it.
class _CardSmsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CardSmsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // Drawn at 30 pt; TapTarget pads the hit area out to the HIG's 44 pt.
    return TapTarget(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sys.well,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(Icons.sms_outlined, size: 16, color: sys.tintText),
      ),
    );
  }
}

/// Muted badge marking a vacated unit — visible for reference, no actions.
class _VacantPill extends StatelessWidget {
  const _VacantPill();
  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return StatusBadge(
      label: 'Vacant',
      color: sys.secondaryLabel,
      textColor: sys.secondaryLabel,
    );
  }
}

/// Orange badge for a partially-paid unit, showing the remaining balance.
class _PartialPill extends StatelessWidget {
  final int remaining;
  final Currency currency;
  const _PartialPill({required this.remaining, required this.currency});
  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return StatusBadge(
      label: '${Money.format(remaining, currency)} left',
      color: sys.orange,
      textColor: sys.orangeText,
    );
  }
}

/// "Mark paid" as a compact tinted button — secondary to the row itself.
class _MarkPaidPill extends StatelessWidget {
  final VoidCallback onTap;
  const _MarkPaidPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Mark paid',
      kind: ButtonKind.tinted,
      compact: true,
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  /// True when the ledger has no units at all (vs a search/filter with no hits).
  final bool noUnits;
  const _Empty({required this.noUnits});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    // A search/filter that matched nothing — keep it plain.
    if (!noUnits) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            'No units match.',
            style: Type.subhead.colored(sys.secondaryLabel),
          ),
        ),
      );
    }

    // A genuinely empty ledger — invite the owner to add their first unit.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 10),
      child: GroupedCard(
        padding: const EdgeInsets.fromLTRB(Sys.gutter, 28, Sys.gutter, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 44, color: sys.tertiaryLabel),
            const SizedBox(height: 14),
            Text('No units yet', style: Type.headline.colored(sys.label)),
            const SizedBox(height: 6),
            Text(
              'Add your shutters or shops to start tracking rent each month.',
              textAlign: TextAlign.center,
              style: Type.footnote.colored(sys.secondaryLabel),
            ),
            const SizedBox(height: 20),
            _AddFirstUnitButton(onTap: () => EditUnitSheet.show(context)),
          ],
        ),
      ),
    );
  }
}

/// Primary call-to-action on the empty ledger — opens the new-unit sheet.
class _AddFirstUnitButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddFirstUnitButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Add your first unit',
      icon: Icons.add,
      kind: ButtonKind.prominent,
      onTap: onTap,
    );
  }
}
