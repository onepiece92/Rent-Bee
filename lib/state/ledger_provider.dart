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

  LedgerProvider(this.repo, {required BsMonth initialMonth})
      : _month = initialMonth;

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
          if (r.isPaid) return false;
          break;
        case LedgerFilter.paid:
          if (!r.isPaid) return false;
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
  /// on a fresh install — demo data is opt-in via Settings → Generate demo data.
  Future<void> init({double annualRaisePercent = 0}) async {
    if (annualRaisePercent > 0) {
      await repo.applyAnniversaryRaises(percent: annualRaisePercent);
    }
    await refresh(showLoading: true);
  }

  /// Reloads the month's rows + summary. [showLoading] gates the loading
  /// state so it only appears on initial load and month switches — in-place
  /// mutations (mark paid, undo, edits) refresh silently to avoid a flash.
  Future<void> refresh({bool showLoading = false}) async {
    if (showLoading) {
      _loading = true;
      notifyListeners();
    }
    final view = await repo.monthView(_month.year, _month.month);
    _rows = view.rows;
    _summary = view.summary;
    _loading = false;
    notifyListeners();
  }

  void setMonth(BsMonth m) {
    _month = m;
    refresh(showLoading: true);
  }

  void nextMonth() => setMonth(_month.next());
  void previousMonth() => setMonth(_month.previous());

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setFilter(LedgerFilter f) {
    _filter = f;
    notifyListeners();
  }

  // ---- mutations (each refreshes affected derived state) ------------------

  Future<void> markPaid(Unit unit,
      {int? amount,
      DateTime? paidOn,
      PayMethod method = PayMethod.cash,
      String? note}) async {
    await repo.markPaid(unit, _month.year, _month.month,
        amount: amount, paidOn: paidOn, method: method, note: note);
    await refresh();
  }

  Future<void> updatePayment(Payment payment) async {
    await repo.updatePayment(payment);
    await refresh();
  }

  Future<void> undo(int unitId) async {
    await repo.undo(unitId, _month.year, _month.month);
    await refresh();
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

  // ---- Charges (variable per-month utility/service fees) -----------------

  /// This unit's charges for the selected month (null = none recorded yet).
  Future<Charge?> chargesFor(int unitId) =>
      repo.chargesFor(unitId, _month.year, _month.month);

  /// Record this unit's electricity/water/service charges for the selected
  /// month, then refresh.
  Future<void> setCharges(
    int unitId, {
    int electricity = 0,
    int water = 0,
    int service = 0,
  }) async {
    await repo.setCharges(unitId, _month.year, _month.month,
        electricity: electricity, water: water, service: service);
    await refresh();
  }

  // ---- Deposit -----------------------------------------------------------

  /// Set the held deposit amount on a unit, then refresh.
  Future<void> setDeposit(Unit unit, int amount) async {
    await repo.setDeposit(unit, amount);
    await refresh();
  }

  /// Flip a unit's deposit between held and refunded, then refresh.
  Future<void> setDepositRefunded(Unit unit, bool refunded) async {
    await repo.setDepositRefunded(unit, refunded);
    await refresh();
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
  /// [LedgerRepository.exportBackupJson]).
  Future<String> exportBackupJson() => repo.exportBackupJson();

  /// Restores a JSON backup, replacing all current data, then refreshes the
  /// view. Returns the number of units/payments/charges written.
  Future<({int units, int payments, int charges})> restoreBackup(
      String content) async {
    final res = await repo.importBackupJson(content);
    await refresh(showLoading: true);
    return res;
  }

  /// Applies any now-due automatic anniversary lease escalations at [percent]%
  /// (used when the owner changes the rate so the effect is immediate; startup
  /// applies them via [init]). Returns the number of units raised.
  Future<int> applyDueRaises(double percent) async {
    final raised = await repo.applyAnniversaryRaises(percent: percent);
    await refresh();
    return raised;
  }

  Future<List<HistoryEntry>> historyFor(int unitId, {int months = 6}) =>
      repo.history(unitId, _month, months: months);

  /// Find the current row for a unit id (after a refresh) for live sheets.
  UnitRow? rowFor(int unitId) {
    for (final r in _rows) {
      if (r.unit.id == unitId) return r;
    }
    return null;
  }
}
