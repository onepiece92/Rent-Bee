import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/ledger_repository.dart';
import '../domain/bs_calendar.dart';
import '../domain/models.dart';

enum LedgerFilter { all, pending, paid }

/// Central app state: the selected BS month, the unit rows for that month,
/// the summary, search text, and filter. Backed by [LedgerRepository].
class LedgerProvider extends ChangeNotifier {
  final LedgerRepository repo;

  BsMonth _month;
  List<UnitRow> _rows = [];
  MonthSummary _summary = const MonthSummary(
      expected: 0, collected: 0, paidCount: 0, activeCount: 0);
  String _query = '';
  LedgerFilter _filter = LedgerFilter.all;
  bool _loading = true;

  /// Units whose paid state changed while the Pending / Paid filter was on.
  /// They stay listed until the filter changes or the month is really
  /// reloaded — otherwise the row would vanish and the next tenant would
  /// slide under the finger (buglog B08).
  final Set<int> _held = {};

  /// The active escalation rate, read whenever the month is (re)loaded: a
  /// past month is priced at the rent in effect then, which depends on it.
  /// Defaults to "off" for callers that don't escalate (tests).
  final double Function() _raisePercent;

  LedgerProvider(this.repo,
      {required BsMonth initialMonth, double Function()? raisePercent})
      : _month = initialMonth,
        _raisePercent = raisePercent ?? (() => 0);

  // getters
  BsMonth get month => _month;
  MonthSummary get summary => _summary;
  String get query => _query;
  LedgerFilter get filter => _filter;
  bool get loading => _loading;
  int get totalCount => _rows.length;

  /// Rows after applying the search + filter.
  List<UnitRow> get visibleRows {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      switch (_filter) {
        case LedgerFilter.pending:
          if (r.isPaid && !_held.contains(r.unit.id)) return false;
          break;
        case LedgerFilter.paid:
          if (!r.isPaid && !_held.contains(r.unit.id)) return false;
          break;
        case LedgerFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final s = r.unit;
      return s.code.toLowerCase().contains(q) ||
          s.tenantName.toLowerCase().contains(q) ||
          s.businessType.toLowerCase().contains(q);
    }).toList();
  }

  /// All pending rows for the month (ignores search/filter) — for reports.
  List<UnitRow> get visibleRowsAllPending =>
      _rows.where((r) => !r.isPaid && r.unit.isActive).toList();

  /// All units sorted by code (ignores filter) — for the Units directory.
  List<UnitRow> get allUnitsByCode {
    final rows = [..._rows];
    rows.sort((a, b) => a.unit.code.compareTo(b.unit.code));
    return rows;
  }

  int get activeUnitCount =>
      _rows.where((r) => r.unit.isActive).length;

  /// Applies any due automatic lease escalations (see
  /// [LedgerRepository.applyAnniversaryRaises]) at [annualRaisePercent], then
  /// loads the current month. Called once at startup. The ledger starts **empty**
  /// on a fresh install. Demo data is a review/testing tool: Settings →
  /// Generate demo data is offered only to the store-review test login and the
  /// debug guest session (see `AuthProvider.canGenerateDemoData`).
  Future<void> init({double annualRaisePercent = 0}) async {
    if (annualRaisePercent > 0) {
      try {
        await repo.applyAnniversaryRaises(percent: annualRaisePercent);
      } catch (e) {
        // The catch-up is a convenience; it must never stop the ledger from
        // loading (it runs again once sync has started).
        debugPrint('Ledger: anniversary catch-up failed: $e');
      }
    }
    await refresh(showLoading: true);
  }

  /// Counts completed loads of ledger data. Listeners that derive their own
  /// figures from the database (Reports) compare it to tell a data change
  /// from a notification that only moved the search box or the filter.
  int get dataRevision => _dataRevision;
  int _dataRevision = 0;

  /// Why the last load failed, or null. The database opens lazily, so a
  /// failed open or migration surfaces here on the first query — without
  /// this the Home screen just spun forever (buglog B10).
  Object? get loadError => _loadError;
  Object? _loadError;

  /// Reloads the month's rows + summary. [showLoading] gates the loading
  /// state so it only appears on initial load and month switches — in-place
  /// mutations (mark paid, undo, edits) refresh silently to avoid a flash.
  ///
  /// [keepOrder] keeps every row where it already is. The natural order puts
  /// pending units first, so marking one paid used to move it down and slide
  /// the next tenant under the finger — where a double-tap marked *them* paid
  /// too (buglog B08). In-place changes keep the order; the list re-sorts on
  /// the next real load (month switch, pull to refresh).
  Future<void> refresh(
      {bool showLoading = false, bool keepOrder = false}) async {
    if (showLoading) {
      _loading = true;
      notifyListeners();
    }
    try {
      final view = await repo.monthView(_month.year, _month.month,
          percent: _raisePercent());
      _rows = keepOrder ? _inCurrentOrder(view.rows) : view.rows;
      if (!keepOrder) _held.clear();
      _summary = view.summary;
      _loadError = null;
      _dataRevision++;
    } catch (e) {
      debugPrint('Ledger: loading ${_month.label} failed: $e');
      _loadError = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// [fresh] rearranged to follow the order the rows are in now; units not
  /// in the current list go after them, in their natural order.
  List<UnitRow> _inCurrentOrder(List<UnitRow> fresh) {
    final position = {
      for (var i = 0; i < _rows.length; i++) _rows[i].unit.id: i,
    };
    final indexed = [
      for (var i = 0; i < fresh.length; i++)
        (position[fresh[i].unit.id] ?? _rows.length + i, fresh[i]),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final e in indexed) e.$2];
  }

  void setMonth(BsMonth m) {
    _month = m;
    refresh(showLoading: true);
  }

  /// Switches to [m] and completes once that month is loaded — for callers
  /// that open something bound to the selected month right afterwards.
  Future<void> goToMonth(BsMonth m) async {
    if (m == _month) return;
    _month = m;
    await refresh(showLoading: true);
  }

  void nextMonth() => setMonth(_month.next());
  void previousMonth() => setMonth(_month.previous());

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setFilter(LedgerFilter f) {
    _filter = f;
    _held.clear();
    notifyListeners();
  }

  // ---- mutations (each refreshes affected derived state) ------------------

  /// Records this month's payment. With no [amount], settles the month at the
  /// due the UI is showing (`rowFor(unit).totalDue` — rent + charges less
  /// deduction), so what the button says and what gets recorded cannot diverge.
  Future<void> markPaid(Unit unit,
      {int? amount,
      DateTime? paidOn,
      PayMethod method = PayMethod.cash,
      String? note}) async {
    final row = rowFor(unit.id);
    await repo.markPaid(unit, _month.year, _month.month,
        amount: amount ?? row?.totalDue,
        rent: row?.monthRent, // priced as shown, and remembered on the payment
        paidOn: paidOn,
        method: method,
        note: note);
    _hold(unit.id);
    await refresh(keepOrder: true);
  }

  void _hold(int unitId) {
    if (_filter != LedgerFilter.all) _held.add(unitId);
  }

  Future<void> updatePayment(Payment payment) async {
    await repo.updatePayment(payment);
    _hold(payment.unitId);
    await refresh(keepOrder: true);
  }

  Future<void> undo(int unitId) async {
    await repo.undo(unitId, _month.year, _month.month);
    _hold(unitId);
    await refresh(keepOrder: true);
  }

  Future<void> createUnit(UnitsCompanion entry) async {
    await repo.createUnit(entry);
    await refresh();
  }

  Future<void> updateUnit(Unit unit) async {
    await repo.updateUnit(unit);
    await refresh();
  }

  Future<void> deleteUnit(int id) async {
    await repo.deleteUnit(id);
    await refresh();
  }

  // ---- Charges + rent deduction (one row per unit-month) -----------------

  /// This unit's charges row (utilities + rent deduction) for the selected
  /// month (null = none recorded yet).
  Future<Charge?> chargesFor(int unitId) =>
      repo.chargesFor(unitId, _month.year, _month.month);

  /// Record this unit's electricity/water/service charges for the selected
  /// month, then refresh — they add to the month's due everywhere.
  Future<void> setCharges(
    int unitId, {
    int electricity = 0,
    int water = 0,
    int service = 0,
  }) async {
    await repo.setCharges(unitId, _month.year, _month.month,
        electricity: electricity, water: water, service: service);
    await refresh(keepOrder: true);
  }

  /// Record the landlord's rent deduction for this unit in the selected month
  /// (0 clears it), then refresh — it changes the month's due everywhere.
  Future<void> setDeduction(int unitId,
      {required int amount, String? note}) async {
    await repo.setDeduction(unitId, _month.year, _month.month,
        amount: amount, note: note);
    await refresh(keepOrder: true);
  }

  // ---- Deposit -----------------------------------------------------------

  /// Set the held deposit amount on a unit, then refresh.
  Future<void> setDeposit(Unit unit, int amount) async {
    await repo.setDeposit(unit, amount);
    await refresh(keepOrder: true);
  }

  /// Flip a unit's deposit between held and refunded, then refresh.
  Future<void> setDepositRefunded(Unit unit, bool refunded) async {
    await repo.setDepositRefunded(unit, refunded);
    await refresh(keepOrder: true);
  }

  /// Replace all data with a realistic multi-year demo dataset (anchored at the
  /// current selected month), with rent growing each anniversary by
  /// [annualRaisePercent]%.
  Future<void> generateDemoData(double annualRaisePercent) async {
    await repo.generateDemoData(_month, annualRaisePercent: annualRaisePercent);
    await refresh();
  }

  /// Delete every unit and payment.
  Future<void> eraseAllData() async {
    await repo.eraseAll();
    await refresh();
  }

  /// Merge a CSV (export format) into the ledger; payments without a year
  /// column land in the currently selected BS year. Returns import counts.
  Future<({int unitsAdded, int unitsUpdated, int payments})> importCsv(
      String content) async {
    final res = await repo.importCsv(content, fallbackYear: _month.year);
    await refresh(showLoading: true);
    return res;
  }

  /// A full, lossless JSON snapshot of the ledger for backup (see
  /// [LedgerRepository.exportBackupJson]). [currency] is the ledger's active
  /// currency name ('npr'/'usd'), passed in from the UI layer since this
  /// provider has no settings dependency of its own.
  Future<String> exportBackupJson({required String currency}) =>
      repo.exportBackupJson(currency: currency);

  /// Restores a JSON backup, replacing all current data, then refreshes the
  /// view. Returns the number of units/payments/charges written, plus the
  /// backup's currency (if it carried one) for the caller to re-apply.
  Future<({int units, int payments, int charges, String? currency})>
      restoreBackup(String content) async {
    final res = await repo.importBackupJson(content);
    await refresh(showLoading: true);
    return res;
  }

  /// Whether cloud sync is live for this session.
  bool get cloudSyncActive => repo.cloudSyncActive;

  /// Forces a full re-push of everything to the cloud (manual backup).
  Future<void> resyncToCloud() => repo.resyncAllToCloud();

  /// Applies any now-due automatic anniversary lease escalations at [percent]%
  /// (used when the owner changes the rate so the effect is immediate; startup
  /// applies them via [init]). Returns the number of units raised.
  Future<int> applyDueRaises(double percent) async {
    final raised = await repo.applyAnniversaryRaises(percent: percent);
    await refresh();
    return raised;
  }

  /// [percent] is the active escalation rate, used to price each history month
  /// at the rent in effect then (see [LedgerRepository.rentInEffect]).
  Future<List<HistoryEntry>> historyFor(int unitId,
          {int months = 6, double percent = 0}) =>
      repo.history(unitId, _month, months: months, percent: percent);

  /// Find the current row for a unit id (after a refresh) for live sheets.
  UnitRow? rowFor(int unitId) {
    for (final r in _rows) {
      if (r.unit.id == unitId) return r;
    }
    return null;
  }
}
