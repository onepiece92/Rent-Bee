# Graph Report - lib  (2026-06-05)

## Corpus Check
- Corpus is ~27,165 words - fits in a single context window. You may not need a graph.

## Summary
- 368 nodes · 437 edges · 25 communities detected
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Unit Detail & Charges UI|Unit Detail & Charges UI]]
- [[_COMMUNITY_Home Screen UI|Home Screen UI]]
- [[_COMMUNITY_Settings & CSV Export|Settings & CSV Export]]
- [[_COMMUNITY_Theme & Nav Shell|Theme & Nav Shell]]
- [[_COMMUNITY_Reports Screen|Reports Screen]]
- [[_COMMUNITY_Domain Models|Domain Models]]
- [[_COMMUNITY_App Bootstrap & Routing|App Bootstrap & Routing]]
- [[_COMMUNITY_Database Schema & Repository|Database Schema & Repository]]
- [[_COMMUNITY_Glass UI Widgets|Glass UI Widgets]]
- [[_COMMUNITY_Edit Unit Form|Edit Unit Form]]
- [[_COMMUNITY_Ledger & Rent-Raise Logic|Ledger & Rent-Raise Logic]]
- [[_COMMUNITY_Drift Generated Models|Drift Generated Models]]
- [[_COMMUNITY_Login  PIN Screen|Login / PIN Screen]]
- [[_COMMUNITY_Toast Notifications|Toast Notifications]]
- [[_COMMUNITY_PIN Authentication|PIN Authentication]]
- [[_COMMUNITY_Raise-Percent Settings|Raise-Percent Settings]]
- [[_COMMUNITY_Money Formatting|Money Formatting]]
- [[_COMMUNITY_Unit-Code Suggestion|Unit-Code Suggestion]]
- [[_COMMUNITY_Web DB Connection|Web DB Connection]]
- [[_COMMUNITY_Platform DB Dispatch|Platform DB Dispatch]]
- [[_COMMUNITY_Phone Normalization|Phone Normalization]]
- [[_COMMUNITY_Router Builder|Router Builder]]
- [[_COMMUNITY_BS Calendar Conversion|BS Calendar Conversion]]
- [[_COMMUNITY_BS Month Start|BS Month Start]]
- [[_COMMUNITY_BS Date Labeling|BS Date Labeling]]

## God Nodes (most connected - your core abstractions)
1. `_` - 19 edges
2. `package:flutter/material.dart` - 14 edges
3. `../../app/theme.dart` - 11 edges
4. `../domain/bs_calendar.dart` - 9 edges
5. `package:provider/provider.dart` - 8 edges
6. `../../state/ledger_provider.dart` - 7 edges
7. `applyAnniversaryRaises({percent, asOf})` - 7 edges
8. `../data/database.dart` - 6 edges
9. `../../state/settings_provider.dart` - 6 edges
10. `../../domain/money.dart` - 6 edges

## Surprising Connections (you probably didn't know these)
- `PIN gates UI not the data/queries` --rationale_for--> `Plain unencrypted NativeDatabase SQLite file`  [INFERRED]
  lib/state/auth_provider.dart → lib/data/connection/native.dart
- `init({annualRaisePercent})` --rationale_for--> `RATIONALE: catch-up at app launch (Flutter has no background scheduler)`  [INFERRED]
  lib/state/ledger_provider.dart → lib/data/ledger_repository.dart
- `applyDueRaises(double percent)` --calls--> `applyAnniversaryRaises({percent, asOf})`  [EXTRACTED]
  lib/state/ledger_provider.dart → lib/data/ledger_repository.dart
- `init({annualRaisePercent})` --calls--> `applyAnniversaryRaises({percent, asOf})`  [EXTRACTED]
  lib/state/ledger_provider.dart → lib/data/ledger_repository.dart
- `RATIONALE: BS start month anchors the anniversary month` --rationale_for--> `Units.startedOn column`  [EXTRACTED]
  lib/data/ledger_repository.dart → lib/data/database.dart

## Communities

### Community 0 - "Unit Detail & Charges UI"
Cohesion: 0.06
Nodes (33): edit_unit_sheet.dart, _BaseBigButton, _BigToggleButton, build, _ChargeField, _ChargeRow, _ChargesSection, _ChargesSectionState (+25 more)

### Community 1 - "Home Screen UI"
Cohesion: 0.06
Nodes (31): build, _CardSmsButton, Container, dispose, _Empty, Expanded, _FilterChip, GlassPanel (+23 more)

### Community 2 - "Settings & CSV Export"
Cohesion: 0.07
Nodes (28): dart:convert, dart:typed_data, AlertDialog, build, _CalendarToggle, Column, dispose, _Divider (+20 more)

### Community 3 - "Theme & Nav Shell"
Cohesion: 0.08
Nodes (24): dart:ui, glass.dart, Brand, buildTheme, display, build, _CenterAddButton, Expanded (+16 more)

### Community 4 - "Reports Screen"
Cohesion: 0.07
Nodes (26): _BreakdownRow, build, Center, dispose, _exportSuffix, GlassPanel, initState, ListView (+18 more)

### Community 5 - "Domain Models"
Cohesion: 0.08
Nodes (23): ../data/database.dart, ../data/ledger_repository.dart, ../domain/bs_calendar.dart, ../domain/models.dart, ../../domain/money.dart, HistoryEntry, MonthBucket, MonthSummary (+15 more)

### Community 6 - "App Bootstrap & Routing"
Cohesion: 0.08
Nodes (23): app/router.dart, build, MaterialApp, MultiProvider, SizedBox, _StartupErrorApp, Text, UnitLedgerApp (+15 more)

### Community 7 - "Database Schema & Repository"
Cohesion: 0.08
Nodes (23): connection/connection.dart, database.dart, AppDatabase, Charges, customStatement, Payments, Units, cell (+15 more)

### Community 8 - "Glass UI Widgets"
Cohesion: 0.08
Nodes (23): BrandBackground, BrandProgressBar, build, ClipRect, ClipRRect, CodeAvatar, Container, DecoratedBox (+15 more)

### Community 9 - "Edit Unit Form"
Cohesion: 0.09
Nodes (21): ../../domain/phone.dart, ../../domain/unit_code.dart, BoxConstraints, build, _DateField, dispose, EditUnitSheet, _EditUnitSheetState (+13 more)

### Community 10 - "Ledger & Rent-Raise Logic"
Cohesion: 0.13
Nodes (18): AppDatabase, MigrationStrategy onUpgrade addColumn (v1->v2), AppDatabase.schemaVersion (=2), Units table, Units.lastRaisedOn column, Units.startedOn column, applyDueRaises(double percent), init({annualRaisePercent}) (+10 more)

### Community 11 - "Drift Generated Models"
Cohesion: 0.12
Nodes (18): _, Charge, ChargesCompanion, copyWith, copyWithCompanion, f, Function, map (+10 more)

### Community 12 - "Login / PIN Screen"
Cohesion: 0.15
Nodes (12): build, dispose, Icon, LoginScreen, _LoginScreenState, _PinField, Scaffold, SizedBox (+4 more)

### Community 13 - "Toast Notifications"
Cohesion: 0.18
Nodes (10): ../../app/theme.dart, build, dispose, initState, Positioned, showToast, showToastOn, SizedBox (+2 more)

### Community 14 - "PIN Authentication"
Cohesion: 0.29
Nodes (10): AuthProvider, Legacy single-round SHA-256 PIN migration, AuthProvider.load, PBKDF2-HMAC-SHA256 derivation (100k iters, off-thread), AuthProvider.setPin, PIN salt+hash stored in shared_preferences, PIN gates UI not the data/queries, AuthProvider.unlock (+2 more)

### Community 15 - "Raise-Percent Settings"
Cohesion: 0.25
Nodes (8): RATIONALE: fractional double percent for finer rate control (e.g. 7.5%), RATIONALE: new prefs key avoids int<->double SharedPreferences type clash, annualRaisePercent (double getter), _defaultRaisePercent (5), _kRaisePercent ('annual_raise_pct'), _maxRaisePercent (1000 guard), setAnnualRaisePercent(double), SettingsProvider

### Community 16 - "Money Formatting"
Cohesion: 0.4
Nodes (4): format, grouped, Money, package:intl/intl.dart

### Community 17 - "Unit-Code Suggestion"
Cohesion: 0.67
Nodes (2): _firstFree, suggestUnitCode

### Community 18 - "Web DB Connection"
Cohesion: 1.0
Nodes (2): web openLedgerExecutor, WASM/OPFS unencrypted web ledger

### Community 19 - "Platform DB Dispatch"
Cohesion: 1.0
Nodes (2): openLedgerExecutor (conditional export dispatch), Compile-time platform backend dispatch (native vs web)

### Community 20 - "Phone Normalization"
Cohesion: 1.0
Nodes (1): normalizePhone

### Community 21 - "Router Builder"
Cohesion: 1.0
Nodes (1): buildRouter

### Community 22 - "BS Calendar Conversion"
Cohesion: 1.0
Nodes (1): bsYearMonth(DateTime)

### Community 23 - "BS Month Start"
Cohesion: 1.0
Nodes (1): adForBsMonthStart(year, month)

### Community 24 - "BS Date Labeling"
Cohesion: 1.0
Nodes (1): dateLabel(date, mode)

## Knowledge Gaps
- **296 isolated node(s):** `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState`, `build`, `MaterialApp` (+291 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Web DB Connection`** (2 nodes): `web openLedgerExecutor`, `WASM/OPFS unencrypted web ledger`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Platform DB Dispatch`** (2 nodes): `openLedgerExecutor (conditional export dispatch)`, `Compile-time platform backend dispatch (native vs web)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Phone Normalization`** (2 nodes): `phone.dart`, `normalizePhone`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Router Builder`** (1 nodes): `buildRouter`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BS Calendar Conversion`** (1 nodes): `bsYearMonth(DateTime)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BS Month Start`** (1 nodes): `adForBsMonthStart(year, month)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BS Date Labeling`** (1 nodes): `dateLabel(date, mode)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Theme & Nav Shell` to `Unit Detail & Charges UI`, `Home Screen UI`, `Settings & CSV Export`, `Reports Screen`, `Domain Models`, `App Bootstrap & Routing`, `Glass UI Widgets`, `Edit Unit Form`, `Login / PIN Screen`, `Toast Notifications`?**
  _High betweenness centrality (0.170) - this node is a cross-community bridge._
- **Why does `../../app/theme.dart` connect `Toast Notifications` to `Unit Detail & Charges UI`, `Home Screen UI`, `Settings & CSV Export`, `Theme & Nav Shell`, `Reports Screen`, `App Bootstrap & Routing`, `Glass UI Widgets`, `Edit Unit Form`, `Login / PIN Screen`?**
  _High betweenness centrality (0.127) - this node is a cross-community bridge._
- **Why does `../domain/bs_calendar.dart` connect `Domain Models` to `Unit Detail & Charges UI`, `Home Screen UI`, `Settings & CSV Export`, `Reports Screen`, `App Bootstrap & Routing`, `Database Schema & Repository`, `Edit Unit Form`?**
  _High betweenness centrality (0.084) - this node is a cross-community bridge._
- **What connects `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState` to the rest of the system?**
  _296 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Unit Detail & Charges UI` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Home Screen UI` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Settings & CSV Export` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._