import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../util/csv_share.dart';
import '../widgets/glass.dart';
import '../widgets/toast.dart';

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
    final mode = context.watch<SettingsProvider>().calendar;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reports',
                      style:
                          display(fontSize: 20, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Export CSV',
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.ios_share, color: Brand.orange),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: _ScopeToggle(scope: _scope, onChanged: _setScope),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: _PeriodStepper(
              label: _periodLabel(mode),
              onPrev: () => _step(-1),
              onNext: () => _step(1),
            ),
          ),
          Expanded(
            child: FutureBuilder<PeriodSummary>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: Brand.orange));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load report: ${snap.error}',
                        style: const TextStyle(color: Brand.muted)),
                  );
                }
                final summary = snap.data;
                if (summary == null) return const SizedBox.shrink();
                return _ReportBody(
                    scope: _scope,
                    summary: summary,
                    mode: mode,
                    liability: _liability);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Month / Quarter / Year segmented control.
class _ScopeToggle extends StatelessWidget {
  final ReportScope scope;
  final ValueChanged<ReportScope> onChanged;
  const _ScopeToggle({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final s in ReportScope.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(s),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: s == scope ? Brand.orangeGradient : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: s == scope ? Colors.white : Brand.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ‹ period label › stepper.
class _PeriodStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _PeriodStepper(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left, color: Brand.text),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: display(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, color: Brand.text),
        ),
      ],
    );
  }
}

/// Scrollable body: summary grid, (period) per-month breakdown, outstanding.
class _ReportBody extends StatelessWidget {
  final ReportScope scope;
  final PeriodSummary summary;
  final CalendarMode mode;
  final Future<DepositLiability>? liability;
  const _ReportBody(
      {required this.scope,
      required this.summary,
      required this.mode,
      this.liability});

  @override
  Widget build(BuildContext context) {
    final isPeriod = scope != ReportScope.month;
    final outstanding = summary.outstanding;

    return ListView(
      padding: const EdgeInsets.only(bottom: 120), // clear the footer navbar
      children: [
        _SummaryGrid(summary: summary),
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
          const _SectionTitle('Monthly breakdown'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: GlassPanel(
              child: Column(
                children: [
                  for (final b in summary.months)
                    _BreakdownRow(bucket: b, mode: mode),
                ],
              ),
            ),
          ),
        ],
        _SectionTitle('Outstanding (${outstanding.length})'),
        if (outstanding.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text('Everyone has paid 🎉',
                  style: TextStyle(color: Brand.muted)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                for (final d in outstanding) ...[
                  _OutstandingRow(debt: d, showMonths: isPeriod),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Text(text,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final MonthBucket bucket;
  final CalendarMode mode;
  const _BreakdownRow({required this.bucket, required this.mode});

  @override
  Widget build(BuildContext context) {
    final full = bucket.collected >= bucket.expected && bucket.expected > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
                BsMonth(bucket.year, bucket.month).monthNameIn(mode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: 8, color: const Color(0x22FFFFFF)),
                  FractionallySizedBox(
                    widthFactor: bucket.progress,
                    child: Container(
                      height: 8,
                      color: full ? Brand.paid : Brand.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${Money.format(bucket.collected)} / ${Money.format(bucket.expected)}',
            style: const TextStyle(
              fontSize: 12,
              color: Brand.muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutstandingRow extends StatelessWidget {
  final PeriodDebt debt;
  final bool showMonths;
  const _OutstandingRow({required this.debt, required this.showMonths});

  @override
  Widget build(BuildContext context) {
    final u = debt.unit;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(u.code,
              style: display(
                  fontWeight: FontWeight.w700, color: Brand.orangeSoft)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(u.tenantName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(debt.amountOwed),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
              if (showMonths)
                Text('${debt.monthsUnpaid} mo',
                    style: const TextStyle(
                        fontSize: 11, color: Brand.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Standing deposit liability — total refundable money the landlord holds,
/// split into deposits on active tenancies vs. vacated units overdue a refund.
class _DepositCard extends StatelessWidget {
  final DepositLiability liability;
  const _DepositCard({required this.liability});

  @override
  Widget build(BuildContext context) {
    final l = liability;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: Brand.muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Deposit liability',
                      style: TextStyle(color: Brand.muted, fontSize: 12)),
                ),
                Text(
                  Money.format(l.total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DepositLine(
              label: 'Held · ${l.heldCount} active',
              amount: l.held,
              color: Brand.text,
            ),
            if (l.hasOverdue) ...[
              const SizedBox(height: 6),
              _DepositLine(
                label: 'Due back · ${l.dueBackCount} vacated',
                amount: l.dueBack,
                color: Brand.orangeSoft,
                warn: true,
              ),
            ],
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
    return Row(
      children: [
        if (warn) ...[
          const Icon(Icons.error_outline, size: 14, color: Brand.orangeSoft),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: warn ? Brand.orangeSoft : Brand.muted)),
        ),
        Text(
          Money.format(amount),
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
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
    final cells = [
      ('Expected', Money.format(summary.expected), Brand.text),
      ('Collected', Money.format(summary.collected), Brand.paidText),
      ('Pending', Money.format(summary.pending), Brand.orangeSoft),
      ('Paid', '${summary.paidSlots}/${summary.totalSlots}', Brand.text),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: [
          for (final c in cells)
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.$1,
                      style:
                          const TextStyle(color: Brand.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(c.$2,
                      style: TextStyle(
                        color: c.$3,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
