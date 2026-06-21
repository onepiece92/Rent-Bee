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
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => context.read<LedgerProvider>().refresh(),
        color: Brand.orange,
        backgroundColor: Brand.navy,
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
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 9),
                    itemBuilder: (context, i) => _UnitTile(row: rows[i]),
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

class _Header extends StatelessWidget {
  final BsMonth month;
  const _Header({required this.month});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsProvider>().calendar;
    // Nav callbacks only — read (not watch) so the header rebuilds solely on
    // the `month` the parent Selector feeds it.
    final ledger = context.read<LedgerProvider>();
    // The real current BS month, for the "jump to today" chip.
    final today = bsYearMonth(DateTime.now());
    final currentMonth = BsMonth(today.year, today.month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/icon/rent_bee.png',
                  width: 28,
                  height: 28,
                  // Source is 512² — decode to ~2x the display size, not full.
                  cacheWidth: 56,
                  cacheHeight: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'Rent Bee',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              // Cloud-sync state (hidden when not signed in / local-only).
              const SyncBadge(),
              const SizedBox(width: 10),
              // Today's date — tap to jump back to the current month.
              _TodayChip(
                mode: mode,
                isCurrent: month == currentMonth,
                onTap: () => ledger.setMonth(currentMonth),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Month switcher as a full-width glass nav bar.
          GlassPanel(
            padding: const EdgeInsets.all(6),
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                _NavBtn(icon: Icons.chevron_left, onTap: ledger.previousMonth),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        month.monthNameIn(mode),
                        style: display(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${month.yearIn(mode)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Brand.muted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                _NavBtn(icon: Icons.chevron_right, onTap: ledger.nextMonth),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill in the header showing today's date in the active calendar.
/// Tapping it jumps the ledger back to the current month; when the selected
/// month differs from today, the pill takes an orange "return to today" accent.
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent
                ? Brand.orange.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: accent
                  ? Brand.orange.withValues(alpha: 0.5)
                  : Brand.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(accent ? Icons.undo_rounded : Icons.today,
                  size: 13,
                  color: accent ? Brand.orangeWarm : Brand.orangeSoft),
              const SizedBox(width: 5),
              Text(
                todayLabel(mode),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: accent ? Brand.orangeWarm : Brand.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 20, color: Brand.text),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MonthSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: GlassPanel(
        sheen: true,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Collected this month',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Brand.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${summary.percent}%',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Brand.orangeWarm,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Money.format(summary.collected),
              style: display(
                fontSize: 37,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.7,
                fontFeatures: tabularNums,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'of ${Money.format(summary.expected)} expected',
              style: const TextStyle(fontSize: 12.5, color: Color(0xB3E2E6FF)),
            ),
            const SizedBox(height: 14),
            BrandProgressBar(value: summary.progress),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatChip(
                  icon: Icons.check_circle,
                  iconColor: Brand.paidText,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${summary.paidCount}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '/${summary.activeCount} paid'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.schedule,
                  iconColor: Brand.orangeWarm,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: Money.format(summary.pending),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularNums,
                          ),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 12.5, color: Brand.text),
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
    // Scoped to its own widget so the query/filter watch rebuilds only this
    // bar, not the header or summary above.
    final ledger = context.watch<LedgerProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        children: [
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                const Icon(Icons.search, size: 16, color: Brand.muted),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: ledger.setQuery,
                    style: const TextStyle(fontSize: 14.5, color: Brand.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      // The search box already sits in a GlassPanel — opt out of
                      // the global filled glass field background.
                      filled: false,
                      border: InputBorder.none,
                      hintText: 'Search tenant or unit…',
                      hintStyle: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
                if (ledger.query.isNotEmpty)
                  InkWell(
                    onTap: () {
                      controller.clear();
                      ledger.setQuery('');
                    },
                    child: const Icon(
                      Icons.close,
                      size: 15,
                      color: Brand.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (final f in LedgerFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: switch (f) {
                      LedgerFilter.all => 'All',
                      LedgerFilter.pending => 'Pending',
                      LedgerFilter.paid => 'Paid',
                    },
                    selected: ledger.filter == f,
                    onTap: () => ledger.setFilter(f),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Brand.orange : Brand.glassBg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? const Color(0xB3FF9A4D) : Brand.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xB3FFFFFF),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  final UnitRow row;
  const _UnitTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final s = row.unit;
    final paid = row.isPaid;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      borderRadius: BorderRadius.circular(18),
      blur: false, // list tile — avoid a live blur layer per row
      onTap: () => UnitDetailSheet.show(context, s.id),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  s.businessType.isEmpty ? '—' : s.businessType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(s.monthlyRent),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularNums,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quick rent reminder — only when a phone is on file.
                  if (s.phone != null && s.phone!.isNotEmpty) ...[
                    _CardSmsButton(
                      onTap: () => sendRentReminder(
                        context,
                        s,
                        context.read<LedgerProvider>().month,
                        paid: paid,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  switch (row.status) {
                    PayStatus.paid => const StatusPill(paid: true),
                    PayStatus.partial => _PartialPill(remaining: row.remaining),
                    PayStatus.pending => _MarkPaidPill(
                      onTap: () => context.read<LedgerProvider>().markPaid(s),
                    ),
                  },
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact SMS-reminder button on a unit card. Its own tap target, so it fires
/// the reminder without opening the detail sheet behind it.
class _CardSmsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CardSmsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Brand.glassBg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Brand.glassBorder),
          ),
          child: const Icon(Icons.sms_outlined,
              size: 15, color: Brand.orangeSoft),
        ),
      ),
    );
  }
}

/// Amber chip for a partially-paid unit, showing the remaining balance.
class _PartialPill extends StatelessWidget {
  final int remaining;
  const _PartialPill({required this.remaining});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Brand.orangeWarm.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Brand.orangeWarm.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timelapse, size: 12, color: Brand.orangeWarm),
          const SizedBox(width: 4),
          Text(
            '${Money.format(remaining)} left',
            style: const TextStyle(
              color: Brand.orangeWarm,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              fontFeatures: tabularNums,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mark paid" pill = dimmed translucent orange (softer than solid CTAs).
class _MarkPaidPill extends StatelessWidget {
  final VoidCallback onTap;
  const _MarkPaidPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Brand.pillBg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Brand.pillBorder),
        ),
        child: const Text(
          'Mark paid',
          style: TextStyle(
            color: Brand.orangeSoft,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  /// True when the ledger has no units at all (vs a search/filter with no hits).
  final bool noUnits;
  const _Empty({required this.noUnits});

  @override
  Widget build(BuildContext context) {
    // A search/filter that matched nothing — keep it plain.
    if (!noUnits) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Text(
            'No units match.',
            style: TextStyle(color: Brand.muted, fontSize: 14),
          ),
        ),
      );
    }

    // A genuinely empty ledger — invite the owner to add their first unit.
    // Generous bottom padding keeps the button clear of the floating nav bar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Brand.glassBg,
              shape: BoxShape.circle,
              border: Border.all(color: Brand.glassBorder),
            ),
            child: const Icon(Icons.storefront_outlined,
                size: 33, color: Brand.orangeSoft),
          ),
          const SizedBox(height: 18),
          Text('No units yet',
              style: display(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Add your shutters or shops to start tracking rent each month.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 22),
          _AddFirstUnitButton(onTap: () => EditUnitSheet.show(context)),
        ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            gradient: Brand.orangeGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Brand.orange.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 19, color: Colors.white),
              SizedBox(width: 7),
              Text('Add your first unit',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
