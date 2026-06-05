import 'package:drift/drift.dart';

import 'connection/connection.dart' as conn;

part 'database.g.dart';

/// Payment method, stored as text. Default `cash`.
enum PayMethod { cash, bank, wallet, other }

@DataClassName('Unit')
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 32).unique()();
  TextColumn get tenantName => text().withLength(min: 1, max: 120)();
  TextColumn get businessType => text().withDefault(const Constant(''))();
  IntColumn get monthlyRent => integer()(); // whole NPR
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// When the tenant joined / the current rent started. Anchors the annual
  /// rent increase: a unit is only raised once a full year has passed since
  /// this date (so a newly-joined tenant isn't raised immediately). Nullable
  /// for legacy units with no recorded start.
  DateTimeColumn get startedOn => dateTime().nullable()();

  /// Last time the annual increase was applied to this unit. Makes the raise
  /// idempotent within a year — eligibility is measured from
  /// `lastRaisedOn ?? startedOn`. Null until the first raise.
  DateTimeColumn get lastRaisedOn => dateTime().nullable()();

  /// Refundable security deposit held for the tenant, whole NPR. 0 = none.
  IntColumn get depositAmount =>
      integer().withDefault(const Constant(0))();

  /// Whether the deposit has been returned to the tenant. false = still held.
  BoolColumn get depositRefunded =>
      boolean().withDefault(const Constant(false))();

  /// When the deposit was refunded. Null while still held.
  DateTimeColumn get depositRefundedOn => dateTime().nullable()();
}

/// Variable per-month utility/service charges for a unit, tracked separately
/// from rent. One row per (unit, month); absent row = nothing recorded yet.
/// These do NOT feed the rent collection summary — they are their own ledger.
@DataClassName('Charge')
class Charges extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get unitId =>
      integer().references(Units, #id, onDelete: KeyAction.cascade)();
  IntColumn get year => integer()(); // BS year
  IntColumn get month => integer()(); // 1–12
  IntColumn get electricity => integer().withDefault(const Constant(0))();
  IntColumn get water => integer().withDefault(const Constant(0))();
  IntColumn get service => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // One charges record per unit per month.
  @override
  List<Set<Column>> get uniqueKeys => [
        {unitId, year, month},
      ];
}

@DataClassName('Payment')
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get unitId =>
      integer().references(Units, #id, onDelete: KeyAction.cascade)();
  IntColumn get year => integer()(); // BS year
  IntColumn get month => integer()(); // 1–12
  IntColumn get amount => integer()(); // whole NPR, captured per record
  DateTimeColumn get paidOn => dateTime().nullable()();
  TextColumn get method =>
      textEnum<PayMethod>().withDefault(Constant(PayMethod.cash.name))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // v1: one record per unit per month.
  @override
  List<Set<Column>> get uniqueKeys => [
        {unitId, year, month},
      ];
}

@DriftDatabase(tables: [Units, Payments, Charges])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2: per-unit rent-start + last-raised dates for the annual increase.
          if (from < 2) {
            await m.addColumn(units, units.startedOn);
            await m.addColumn(units, units.lastRaisedOn);
          }
          // v3: tracked security deposit + variable per-month utility charges.
          if (from < 3) {
            await m.addColumn(units, units.depositAmount);
            await m.addColumn(units, units.depositRefunded);
            await m.addColumn(units, units.depositRefundedOn);
            await m.createTable(charges);
          }
        },
        beforeOpen: (details) async {
          // Enforce FK cascade.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Opens the ledger with the platform-appropriate backend, resolved at compile
/// time by [conn] (see `connection/`):
///   • native (mobile/desktop) — a plain on-disk SQLite file.
///   • web — sqlite3 compiled to WASM, persisted via OPFS/IndexedDB.
/// Neither is encrypted at rest; access is gated by the device/origin sandbox
/// plus the PIN UI lock.
Future<AppDatabase> openAppDatabase() async =>
    AppDatabase(await conn.openLedgerExecutor());
