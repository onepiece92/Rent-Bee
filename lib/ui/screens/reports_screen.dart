import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
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
    // queries once instead of per-change. Settings too: the BS/AD calendar
    // toggle changes what the Year scope spans (Baishakh–Chaitra vs Jan–Dec),
    // and the escalation rate changes historical pricing.
    _ledger.addListener(_onLedgerChanged);
    _settings.addListener(_onLedgerChanged);
    _reload();
  }

  /// False while this tab is parked off-screen (the shell keeps every branch
  /// alive and disables its tickers). A hidden report is not recomputed — it
  /// is marked stale and reloaded once, when the tab is shown again.
  ValueListenable<TickerModeData>? _tickerMode;
  bool get _visible => _tickerMode?.value.enabled ?? true;
  bool _stale = false;

  /// What the figures on screen were computed from. A notification that
  /// leaves this unchanged (typing in the Ledger's search box, switching its
  /// filter, a currency or appearance change) needs no query at all.
  (int, CalendarMode, double)? _loadedFrom;
  (int, CalendarMode, double) get _inputs => (
        _ledger.dataRevision,
        _settings.calendar,
        _settings.annualRaisePercent,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_onVisibilityChanged);
      _tickerMode = notifier..addListener(_onVisibilityChanged);
    }
  }

  void _onVisibilityChanged() {
    if (_visible && _stale && mounted) _reload();
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onVisibilityChanged);
    _ledger.removeListener(_onLedgerChanged);
    _settings.removeListener(_onLedgerChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onLedgerChanged() {
    if (_inputs == _loadedFrom) return;
    if (!_visible) {
      _stale = true;
      _debounce?.cancel();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_visible) {
        _reload();
      } else {
        _stale = true;
      }
    });
  }

  // ---- period math -------------------------------------------------------

  /// Inclusive BS-month span for the current scope + anchor. In AD display
  /// mode the Year scope is the AD calendar year containing the anchor —
  /// January through December, a run of 12 BS months that crosses the BS
  /// year boundary (Magh → Poush). In BS mode it stays Baishakh–Chaitra.
  (BsMonth, BsMonth) get _range {
    switch (_scope) {
      case ReportScope.month:
        return (_anchor, _anchor);
      case ReportScope.quarter:
        final start =
            BsMonth(_anchor.year, ((_anchor.month - 1) ~/ 3) * 3 + 1);
        return (start, start.next().next());
      case ReportScope.year:
        if (_settings.calendar == CalendarMode.ad) {
          final start = _adYearStart(_anchor.yearIn(CalendarMode.ad));
          var end = start;
          for (var i = 0; i < 11; i++) {
            end = end.next();
          }
          return (start, end);
        }
        return (BsMonth(_anchor.year, 1), BsMonth(_anchor.year, 12));
    }
  }

  /// The BS month whose first day falls in January of AD [adYear] — where
  /// the Jan–Dec report year starts. Computed through the calendar helpers
  /// (a date safely inside that BS month, then a guard on the edge) rather
  /// than a fixed year offset.
  static BsMonth _adYearStart(int adYear) {
    final ym = bsYearMonth(DateTime(adYear, 1, 25));
    var m = BsMonth(ym.year, ym.month);
    while (adForBsMonthStart(m.year, m.month).month != 1) {
      m = adForBsMonthStart(m.year, m.month).month == 12
          ? m.next()
          : m.previous();
    }
    return m;
  }

  String _periodLabel(CalendarMode mode) {
    final (startM, endM) = _range;
    switch (_scope) {
      case ReportScope.month:
        return _anchor.labelIn(mode);
      case ReportScope.quarter:
        if (mode == CalendarMode.ad) {
          return '${startM.shortMonthNameIn(mode)}–${endM.shortMonthNameIn(mode)} ${endM.yearIn(mode)}';
        }
        final q = (startM.month - 1) ~/ 3 + 1;
        return 'Q$q ${_anchor.year} · ${BsCalendar.label(startM.month)}–${BsCalendar.label(endM.month)}';
      case ReportScope.year:
        if (mode == CalendarMode.ad) {
          // The AD calendar year: "Jan – Dec 2026".
          return '${startM.shortMonthNameIn(mode)} – ${endM.shortMonthNameIn(mode)} ${endM.yearIn(mode)}';
        }
        return '${_anchor.year} · Baishakh–Chaitra';
    }
  }

  void _reload() {
    _stale = false;
    _loadedFrom = _inputs;
    final (start, end) = _range;
    _future = _ledger.repo.periodSummarySpan(start, end,
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
      final csv = await _ledger.repo.exportCsvSpan(start, end);
      // Year scope in AD mode is the AD calendar year — name the file by it.
      final yearLabel = _scope == ReportScope.year &&
              _settings.calendar == CalendarMode.ad
          ? '${end.yearIn(CalendarMode.ad)}'
          : '${_anchor.year}';
      final name = 'unit-ledger-$yearLabel-${_exportSuffix(start.month)}.csv';
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
          _ChargesCard(summary: summary, scope: scope, mode: mode),
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

/// Where the period's charges came from and where its deductions went: the
/// per-type split of charges (electricity / water / other) with how many
/// units each was billed to, the deduction audit trail (expand in place, same
/// interaction as the deposit card's "Due back" line), and — on the single
/// month scope — how many units have charges entered at all, since a
/// forgotten meter reading silently understates Expected. Only rendered when
/// the period actually has charges or deductions, so an all-rent ledger keeps
/// its uncluttered grid.
class _ChargesCard extends StatefulWidget {
  final PeriodSummary summary;
  final ReportScope scope;
  final CalendarMode mode;
  const _ChargesCard(
      {required this.summary, required this.scope, required this.mode});

  @override
  State<_ChargesCard> createState() => _ChargesCardState();
}

class _ChargesCardState extends State<_ChargesCard> {
  bool _expanded = false;

  static String _units(int n) => n == 1 ? '1 unit' : '$n units';

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final s = widget.summary;
    final b = s.chargesBreakdown;
    final currency = context.watch<SettingsProvider>().currency;
    // The card's headline is the net effect on Expected beyond plain rent.
    final net = s.chargesExpected - s.deductions;
    final netText = net < 0
        ? '− ${Money.format(-net, currency)}'
        : '+ ${Money.format(net, currency)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 12),
      child: GroupedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and net total side by side; stacked at accessibility
            // text sizes (same arrangement as the deposit card).
            Builder(builder: (context) {
              final title = Row(
                children: [
                  Icon(Icons.functions, size: 20, color: sys.secondaryLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Charges & deductions',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.title3.semibold.colored(sys.label)),
                  ),
                ],
              );
              final total = Text(netText,
                  style: Type.title3.semibold.colored(sys.label).tabular);
              if (TextSize.large(context)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: total),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  TrailingValue(child: total),
                ],
              );
            }),
            const SizedBox(height: 12),
            Well(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (b.electricity > 0)
                    _ChargeLine(
                      icon: Icons.bolt_outlined,
                      label: 'Electricity · ${_units(b.electricityUnits)}',
                      amount: Money.format(b.electricity, currency),
                    ),
                  if (b.water > 0) ...[
                    if (b.electricity > 0) const Hairline(inset: 12),
                    _ChargeLine(
                      icon: Icons.water_drop_outlined,
                      label: 'Water · ${_units(b.waterUnits)}',
                      amount: Money.format(b.water, currency),
                    ),
                  ],
                  if (b.service > 0) ...[
                    if (b.electricity > 0 || b.water > 0)
                      const Hairline(inset: 12),
                    _ChargeLine(
                      icon: Icons.receipt_long_outlined,
                      label: 'Other · ${_units(b.serviceUnits)}',
                      amount: Money.format(b.service, currency),
                    ),
                  ],
                  if (s.deductions > 0) ...[
                    if (b.total > 0) const Hairline(inset: 12),
                    // Tapping the deductions line expands its entries.
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ChargeLine(
                              icon: Icons.remove_circle_outline,
                              label: 'Deductions · '
                                  '${_units(s.deductionEntries.length)}',
                              amount:
                                  '− ${Money.format(s.deductions, currency)}',
                              warn: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              _expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: sys.secondaryLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_expanded)
                      for (final e in s.deductionEntries) ...[
                        const Hairline(inset: 12),
                        _DeductionEntryRow(entry: e, mode: widget.mode),
                      ],
                  ],
                ],
              ),
            ),
            // On a single month, flag units whose charges are not entered yet
            // — their Expected is rent-only until the meter reading goes in.
            if (widget.scope == ReportScope.month && s.totalSlots > 0) ...[
              const SizedBox(height: 10),
              Builder(builder: (context) {
                final complete = s.unitsWithCharges >= s.totalSlots;
                return Text(
                  'Charges entered for ${s.unitsWithCharges} of '
                  '${s.totalSlots} units',
                  style: Type.footnote.colored(
                      complete ? sys.secondaryLabel : sys.orangeText),
                );
              }),
            ],
            const SizedBox(height: 6),
            // The equation the summary grid's Expected comes from.
            Text(
              'Rent ${Money.format(s.rentExpected, currency)}'
              '${s.chargesExpected > 0 ? '  +  ${Money.format(s.chargesExpected, currency)}' : ''}'
              '${s.deductions > 0 ? '  −  ${Money.format(s.deductions, currency)}' : ''}'
              '  =  ${Money.format(s.expected, currency)}',
              style: Type.footnote.colored(sys.tertiaryLabel).tabular,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line inside the charges card: icon, label, trailing amount.
class _ChargeLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final bool warn;
  const _ChargeLine(
      {required this.icon,
      required this.label,
      required this.amount,
      this.warn = false});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final color = warn ? sys.orangeText : sys.secondaryLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: Type.subhead.colored(color))),
          const SizedBox(width: 12),
          TrailingValue(
            child: Text(amount,
                style: Type.subhead.semibold
                    .colored(warn ? sys.orangeText : sys.label)
                    .tabular),
          ),
        ],
      ),
    );
  }
}

/// One expanded deduction: who, which month, what for. Tapping opens the
/// unit's sheet, where the deduction can be edited.
class _DeductionEntryRow extends StatelessWidget {
  final DeductionEntry entry;
  final CalendarMode mode;
  const _DeductionEntryRow({required this.entry, required this.mode});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final currency = context.watch<SettingsProvider>().currency;
    final e = entry;
    final note = e.note?.trim();
    return InkWell(
      onTap: () => UnitDetailSheet.show(context, e.unit.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            CodeAvatar(code: e.unit.code, paid: false, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.unit.tenantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.subhead.colored(sys.label)),
                  Text(
                    note == null || note.isEmpty
                        ? e.month.labelIn(mode)
                        : '${e.month.labelIn(mode)} — $note',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.footnote.colored(sys.secondaryLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('− ${Money.format(e.amount, currency)}',
                style:
                    Type.subhead.semibold.colored(sys.orangeText).tabular),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: sys.tertiaryLabel),
          ],
        ),
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
          // Turns green by itself once the month is fully collected. Brand
          // orange fill — one of the kit's two signature brand moments.
          Expanded(child: ProgressBar(value: bucket.progress, color: sys.brand)),
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
                  // Name the month that is actually unpaid, not the period's
                  // anchor (a year report anchored on Ashwin with only
                  // Baishakh unpaid used to say "rent for Ashwin").
                  debt.unpaidMonths.length == 1
                      ? debt.unpaidMonths.first
                      : anchor,
                  paid: false,
                  amount: debt.amountOwed,
                  currency: currency,
                  months: debt.monthsUnpaid,
                  mode: context.read<SettingsProvider>().calendar,
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
      // The sheet works on the Ledger's selected month, so point the Ledger
      // at the month this debt is for first (its oldest unpaid month) —
      // otherwise "Collect" would record whatever month Home happened to be
      // on and the debt shown here would stay outstanding (buglog B07).
      onTap: () async {
        final ledger = context.read<LedgerProvider>();
        await ledger.goToMonth(
            debt.unpaidMonths.isNotEmpty ? debt.unpaidMonths.first : anchor);
        if (context.mounted) UnitDetailSheet.show(context, u.id);
      },
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
            // Title and total side by side; at the accessibility text
            // sizes the total goes under the title so neither is cut.
            Builder(builder: (context) {
              final title = Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 20, color: sys.secondaryLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Deposit liability',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.title3.semibold.colored(sys.label)),
                  ),
                ],
              );
              final total = Text(
                Money.format(l.total, currency),
                style: Type.title3.semibold.colored(sys.label).tabular,
              );
              if (TextSize.large(context)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: total),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  TrailingValue(child: total),
                ],
              );
            }),
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
        TrailingValue(
          child: Text(
            Money.format(amount, currency),
            style: Type.subhead.semibold.colored(color).tabular,
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
      // Two cards per row, as tall as their text needs: a fixed-ratio grid
      // clipped the figures once the text size went up.
      child: Column(
        children: [
          for (var i = 0; i < cells.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in cells.skip(i).take(2)) ...[
                    if (c != cells[i]) const SizedBox(width: 12),
                    Expanded(
                      child: GroupedCard(
                        padding: const EdgeInsets.all(14),
                        child: ConstrainedBox(
                          // The height the old 1.8 grid gave at default text.
                          constraints: const BoxConstraints(minHeight: 62),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.$1,
                                  style: Type.caption1
                                      .colored(sys.secondaryLabel)),
                              const SizedBox(height: 4),
                              // Big totals shrink to fit rather than truncate.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(c.$2,
                                    maxLines: 1,
                                    style: Type.title2.semibold.tabular
                                        .colored(c.$3)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
