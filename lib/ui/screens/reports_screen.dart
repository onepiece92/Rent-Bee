import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../sheets/unit_detail_sheet.dart';
import '../util/csv_share.dart';
import '../util/sms_reminder.dart';
import '../widgets/glass.dart';
import '../widgets/tap_target.dart';
import '../widgets/toast.dart';

/// Section headings get a little air above them, on top of the 12 pt the
/// previous card leaves.
const _sectionPad = EdgeInsets.fromLTRB(Sys.gutter, 8, Sys.gutter, 8);

/// Month / quarter / year summary + per-month breakdown + outstanding list
/// + CSV export. Hosted as a tab inside [ScaffoldWithNavBar].
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final LedgerProvider _ledger;
  late final SettingsProvider _settings;
  ReportScope _scope = ReportScope.month;
  late BsMonth _anchor;
  Future<PeriodSummary>? _future;
  Future<DepositLiability>? _liability;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ledger = context.read<LedgerProvider>();
    _settings = context.read<SettingsProvider>();
    _anchor = _ledger.month;
    // Refetch whenever ledger data changes (e.g. a payment marked elsewhere),
    // debounced so a burst of mark-paid/sync notifies re-runs the multi-month
    // queries once instead of per-change.
    _ledger.addListener(_onLedgerChanged);
    _reload();
  }

  @override
  void dispose() {
    _ledger.removeListener(_onLedgerChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onLedgerChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _reload();
    });
  }

  // ---- period math -------------------------------------------------------

  /// Inclusive (startMonth, endMonth) for the current scope + anchor.
  (int, int) get _range {
    switch (_scope) {
      case ReportScope.month:
        return (_anchor.month, _anchor.month);
      case ReportScope.quarter:
        final start = ((_anchor.month - 1) ~/ 3) * 3 + 1;
        return (start, start + 2);
      case ReportScope.year:
        return (1, 12);
    }
  }

  String _periodLabel(CalendarMode mode) {
    final (start, end) = _range;
    final startM = BsMonth(_anchor.year, start);
    final endM = BsMonth(_anchor.year, end);
    switch (_scope) {
      case ReportScope.month:
        return _anchor.labelIn(mode);
      case ReportScope.quarter:
        if (mode == CalendarMode.ad) {
          return '${startM.shortMonthNameIn(mode)}–${endM.shortMonthNameIn(mode)} ${endM.yearIn(mode)}';
        }
        final q = (start - 1) ~/ 3 + 1;
        return 'Q$q ${_anchor.year} · ${BsCalendar.label(start)}–${BsCalendar.label(end)}';
      case ReportScope.year:
        if (mode == CalendarMode.ad) {
          return '${startM.shortMonthNameIn(mode)} ${startM.yearIn(mode)} – ${endM.shortMonthNameIn(mode)} ${endM.yearIn(mode)}';
        }
        return '${_anchor.year} · Baishakh–Chaitra';
    }
  }

  void _reload() {
    final (start, end) = _range;
    _future = _ledger.repo.periodSummary(_anchor.year, start, end,
        percent: _settings.annualRaisePercent);
    // Deposit liability is period-independent but reloads with the data so it
    // tracks unit edits / move-outs made elsewhere.
    _liability = _ledger.repo.depositLiability();
    if (mounted) setState(() {});
  }

  void _setScope(ReportScope s) {
    if (s == _scope) return;
    _scope = s;
    _reload();
  }

  /// Step the anchor forward (dir = 1) or back (dir = -1) by one scope unit.
  void _step(int dir) {
    switch (_scope) {
      case ReportScope.month:
        _anchor = dir > 0 ? _anchor.next() : _anchor.previous();
        break;
      case ReportScope.quarter:
        final start = ((_anchor.month - 1) ~/ 3) * 3 + 1;
        var s = BsMonth(_anchor.year, start);
        for (var i = 0; i < 3; i++) {
          s = dir > 0 ? s.next() : s.previous();
        }
        _anchor = s;
        break;
      case ReportScope.year:
        _anchor = BsMonth(_anchor.year + dir, _anchor.month);
        break;
    }
    _reload();
  }

  // ---- export ------------------------------------------------------------

  Future<void> _exportCsv() async {
    final overlay = Overlay.of(context, rootOverlay: true); // capture pre-await
    final origin = shareOriginFor(context);
    final (start, end) = _range;
    try {
      final csv =
          await _ledger.repo.exportCsvRange(_anchor.year, start, end);
      final name = 'unit-ledger-${_anchor.year}-${_exportSuffix(start)}.csv';
      await shareCsv(csv, name, origin: origin);
    } catch (e) {
      showToastOn(overlay, 'Export failed: $e', error: true);
    }
  }

  String _exportSuffix(int start) => switch (_scope) {
        ReportScope.month => '$start',
        ReportScope.quarter => 'Q${(start - 1) ~/ 3 + 1}',
        ReportScope.year => 'full',
      };

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final mode = context.watch<SettingsProvider>().calendar;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120), // clear the floating tab bar
        children: [
          // Large Title with the period it describes; the ‹ › period stepper
          // is the title row's toolbar.
          Padding(
            padding: const EdgeInsets.fromLTRB(Sys.gutter, 12, Sys.gutter, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reports',
                          style: Type.largeTitle.colored(sys.label)),
                      const SizedBox(height: 2),
                      Text(_periodLabel(mode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.subhead.colored(sys.secondaryLabel)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.chevron_left,
                  semanticLabel: 'Previous period',
                  onTap: () => _step(-1),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.chevron_right,
                  semanticLabel: 'Next period',
                  onTap: () => _step(1),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 16),
            child: SegmentedControl<ReportScope>(
              values: ReportScope.values,
              selected: _scope,
              label: (s) => s.label,
              onChanged: _setScope,
              glass: true,
            ),
          ),
          FutureBuilder<PeriodSummary>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text('Could not load report: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: Type.subhead.colored(sys.secondaryLabel)),
                  ),
                );
              }
              final summary = snap.data;
              if (summary == null) return const SizedBox.shrink();
              return _ReportBody(
                  scope: _scope,
                  summary: summary,
                  mode: mode,
                  anchor: _anchor,
                  liability: _liability);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sys.gutter, 20, Sys.gutter, 0),
            child: Center(
              child: AppButton(
                kind: ButtonKind.tinted,
                icon: Icons.ios_share,
                label: 'Export CSV',
                onTap: _exportCsv,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Report content: summary grid, (period) per-month breakdown, outstanding.
/// Lives inside the screen's scroll view, so it is a plain column.
class _ReportBody extends StatelessWidget {
  final ReportScope scope;
  final PeriodSummary summary;
  final CalendarMode mode;
  final BsMonth anchor; // for the single-month reminder's label
  final Future<DepositLiability>? liability;
  const _ReportBody(
      {required this.scope,
      required this.summary,
      required this.mode,
      required this.anchor,
      this.liability});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final isPeriod = scope != ReportScope.month;
    final outstanding = summary.outstanding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryGrid(summary: summary),
        if (summary.chargesExpected > 0 || summary.deductions > 0)
          _IncomeBreakdown(summary: summary),
        if (liability != null)
          FutureBuilder<DepositLiability>(
            future: liability,
            builder: (context, snap) {
              final l = snap.data;
              if (l == null || l.total == 0) return const SizedBox.shrink();
              return _DepositCard(liability: l);
            },
          ),
        if (isPeriod) ...[
          const SectionTitle('Monthly breakdown', padding: _sectionPad),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 12),
            child: GroupedCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < summary.months.length; i++) ...[
                    if (i > 0) const Hairline(),
                    _BreakdownRow(bucket: summary.months[i], mode: mode),
                  ],
                ],
              ),
            ),
          ),
        ],
        SectionTitle('Outstanding (${outstanding.length})',
            padding: _sectionPad),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sys.gutter),
          child: outstanding.isEmpty
              ? GroupedCard(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('Everyone has paid 🎉',
                        style: Type.subhead.colored(sys.secondaryLabel)),
                  ),
                )
              : GroupedCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < outstanding.length; i++) ...[
                        // Inset past the avatar so the line starts under the
                        // tenant's name, like iOS.
                        if (i > 0) const Hairline(inset: 72),
                        _OutstandingRow(
                            debt: outstanding[i],
                            showMonths: isPeriod,
                            anchor: anchor),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// What the period's Expected is made of — rent vs. utility charges vs.
/// deductions. Only rendered when the period actually has charges or
/// deductions, so an all-rent ledger keeps its uncluttered grid. Reads as a
/// section footer under the summary grid.
class _IncomeBreakdown extends StatelessWidget {
  final PeriodSummary summary;
  const _IncomeBreakdown({required this.summary});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final s = summary;
    final currency = context.watch<SettingsProvider>().currency;
    final parts = [
      'Rent ${Money.format(s.rentExpected, currency)}',
      if (s.chargesExpected > 0)
        '+ Charges ${Money.format(s.chargesExpected, currency)}',
      if (s.deductions > 0)
        '− Deductions ${Money.format(s.deductions, currency)}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Sys.gutter + 4, 0, Sys.gutter + 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.functions, size: 14, color: sys.secondaryLabel),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('  ·  '),
              style: Type.footnote.colored(sys.secondaryLabel).tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final MonthBucket bucket;
  final CalendarMode mode;
  const _BreakdownRow({required this.bucket, required this.mode});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final currency = context.watch<SettingsProvider>().currency;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Sys.gutter, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
                BsMonth(bucket.year, bucket.month).monthNameIn(mode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.subhead.colored(sys.label)),
          ),
          // Turns green by itself once the month is fully collected.
          Expanded(child: ProgressBar(value: bucket.progress)),
          const SizedBox(width: 12),
          Text(
            '${Money.format(bucket.collected, currency)} / '
            '${Money.format(bucket.expected, currency)}',
            style: Type.footnote.colored(sys.secondaryLabel).tabular,
          ),
        ],
      ),
    );
  }
}

class _OutstandingRow extends StatelessWidget {
  final PeriodDebt debt;
  final bool showMonths;
  final BsMonth anchor;
  const _OutstandingRow(
      {required this.debt, required this.showMonths, required this.anchor});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final u = debt.unit;
    final hasPhone = u.phone != null && u.phone!.isNotEmpty;
    final currency = context.watch<SettingsProvider>().currency;
    return ListRow(
      leading: CodeAvatar(code: u.code, paid: false),
      title: u.tenantName,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhone) ...[
            Tooltip(
              message: 'Send reminder',
              child: TapTarget(
                onTap: () => sendRentReminder(
                  context,
                  u,
                  anchor,
                  paid: false,
                  amount: debt.amountOwed,
                  currency: currency,
                  months: debt.monthsUnpaid,
                ),
                child:
                    Icon(Icons.sms_outlined, size: 18, color: sys.tintText),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(debt.amountOwed, currency),
                  style: Type.subhead.semibold.tabular
                      .colored(sys.orangeText)),
              if (showMonths)
                Text('${debt.monthsUnpaid} mo',
                    style: Type.footnote.colored(sys.secondaryLabel)),
            ],
          ),
        ],
      ),
      chevron: true,
      // The row is the shortcut to act on the debt: open the unit's sheet.
      onTap: () => UnitDetailSheet.show(context, u.id),
    );
  }
}

/// Standing deposit liability — total refundable money the landlord holds,
/// split into deposits on active tenancies vs. vacated units overdue a refund.
/// With overdue refunds the card expands to list the vacated units; tapping
/// one opens its sheet, where the refund is recorded (see DepositCell).
class _DepositCard extends StatefulWidget {
  final DepositLiability liability;
  const _DepositCard({required this.liability});

  @override
  State<_DepositCard> createState() => _DepositCardState();
}

class _DepositCardState extends State<_DepositCard> {
  bool _expanded = false;
  Future<List<Unit>>? _dueBack; // fetched on first expand only

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _dueBack ??=
          context.read<LedgerProvider>().repo.unitsOwingDepositRefund();
    });
  }

  @override
  void didUpdateWidget(covariant _DepositCard old) {
    super.didUpdateWidget(old);
    // The body re-fetches liability on every ledger change, handing this card
    // a fresh instance — refetch the expanded list too, so a refund recorded
    // from the sheet drops its row instead of lingering stale.
    if (!identical(old.liability, widget.liability) && _dueBack != null) {
      _dueBack =
          context.read<LedgerProvider>().repo.unitsOwingDepositRefund();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final l = widget.liability;
    final currency = context.watch<SettingsProvider>().currency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 12),
      child: GroupedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: sys.secondaryLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Deposit liability',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.title3.semibold.colored(sys.label)),
                ),
                const SizedBox(width: 12),
                Text(
                  Money.format(l.total, currency),
                  style: Type.title3.semibold.colored(sys.label).tabular,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The split, as an inset list inside the card.
            Well(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: _DepositLine(
                      label: 'Held · ${l.heldCount} active',
                      amount: l.held,
                      color: sys.label,
                    ),
                  ),
                  if (l.hasOverdue) ...[
                    const Hairline(inset: 12),
                    // Tapping the overdue line expands the units behind it.
                    InkWell(
                      onTap: _toggle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: _DepositLine(
                                label:
                                    'Due back · ${l.dueBackCount} vacated',
                                amount: l.dueBack,
                                color: sys.orangeText,
                                warn: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: sys.secondaryLabel,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded)
                      FutureBuilder<List<Unit>>(
                        future: _dueBack,
                        builder: (context, snap) {
                          final units = snap.data;
                          if (units == null) return const SizedBox.shrink();
                          return Column(
                            children: [
                              for (final u in units) ...[
                                const Hairline(inset: 12),
                                InkWell(
                                  onTap: () =>
                                      UnitDetailSheet.show(context, u.id),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    child: Row(
                                      children: [
                                        CodeAvatar(
                                            code: u.code,
                                            paid: false,
                                            size: 40),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(u.tenantName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Type.subhead
                                                  .colored(sys.label)),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          Money.format(
                                              u.depositAmount, currency),
                                          style: Type.subhead.semibold
                                              .colored(sys.label)
                                              .tabular,
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(Icons.chevron_right,
                                            size: 20,
                                            color: sys.tertiaryLabel),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositLine extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  final bool warn;
  const _DepositLine({
    required this.label,
    required this.amount,
    required this.color,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final currency = context.watch<SettingsProvider>().currency;
    return Row(
      children: [
        if (warn) ...[
          Icon(Icons.error_outline, size: 15, color: sys.orangeText),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(label,
              style: Type.subhead
                  .colored(warn ? sys.orangeText : sys.secondaryLabel)),
        ),
        const SizedBox(width: 12),
        Text(
          Money.format(amount, currency),
          style: Type.subhead.semibold.colored(color).tabular,
        ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final PeriodSummary summary;
  const _SummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final currency = context.watch<SettingsProvider>().currency;
    final cells = [
      ('Expected', Money.format(summary.expected, currency), sys.label),
      ('Collected', Money.format(summary.collected, currency), sys.greenText),
      ('Pending', Money.format(summary.pending, currency), sys.orangeText),
      ('Paid', '${summary.paidSlots}/${summary.totalSlots}', sys.label),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Tall enough for caption + Title 2 at 14 pt padding, with room for
        // a couple of Dynamic Type steps.
        childAspectRatio: 1.8,
        children: [
          for (final c in cells)
            GroupedCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.$1, style: Type.caption1.colored(sys.secondaryLabel)),
                  const SizedBox(height: 4),
                  // Big totals shrink to fit rather than truncate.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(c.$2,
                        maxLines: 1,
                        style: Type.title2.semibold.tabular.colored(c.$3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
