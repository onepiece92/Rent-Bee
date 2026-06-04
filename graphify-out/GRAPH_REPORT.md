# Graph Report - lib  (2026-06-04)

## Corpus Check
- Corpus is ~21,194 words - fits in a single context window. You may not need a graph.

## Summary
- 301 nodes · 356 edges · 23 communities detected
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Home Screen UI|Home Screen UI]]
- [[_COMMUNITY_Reports Screen|Reports Screen]]
- [[_COMMUNITY_Theme & Nav Shell|Theme & Nav Shell]]
- [[_COMMUNITY_Unit Detail Sheet|Unit Detail Sheet]]
- [[_COMMUNITY_Settings Screen|Settings Screen]]
- [[_COMMUNITY_Glass UI Widgets|Glass UI Widgets]]
- [[_COMMUNITY_Ledger & Rent-Raise Logic|Ledger & Rent-Raise Logic]]
- [[_COMMUNITY_Edit Unit Form|Edit Unit Form]]
- [[_COMMUNITY_Drift Generated Models|Drift Generated Models]]
- [[_COMMUNITY_App Bootstrap & Routing|App Bootstrap & Routing]]
- [[_COMMUNITY_Units List Screen|Units List Screen]]
- [[_COMMUNITY_Login  PIN Screen|Login / PIN Screen]]
- [[_COMMUNITY_Toast Notifications|Toast Notifications]]
- [[_COMMUNITY_PIN Authentication|PIN Authentication]]
- [[_COMMUNITY_Raise-Percent Settings|Raise-Percent Settings]]
- [[_COMMUNITY_Domain Models|Domain Models]]
- [[_COMMUNITY_Money Formatting|Money Formatting]]
- [[_COMMUNITY_Web DB Connection|Web DB Connection]]
- [[_COMMUNITY_Platform DB Dispatch|Platform DB Dispatch]]
- [[_COMMUNITY_Router Builder|Router Builder]]
- [[_COMMUNITY_BS Calendar Conversion|BS Calendar Conversion]]
- [[_COMMUNITY_BS Month Start|BS Month Start]]
- [[_COMMUNITY_BS Date Labeling|BS Date Labeling]]

## God Nodes (most connected - your core abstractions)
1. `_` - 17 edges
2. `package:flutter/material.dart` - 13 edges
3. `../../app/theme.dart` - 11 edges
4. `package:provider/provider.dart` - 8 edges
5. `../../state/ledger_provider.dart` - 7 edges
6. `applyAnniversaryRaises({percent, asOf})` - 7 edges
7. `../../domain/bs_calendar.dart` - 6 edges
8. `../../state/settings_provider.dart` - 6 edges
9. `../widgets/glass.dart` - 6 edges
10. `../../domain/money.dart` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Plain unencrypted NativeDatabase SQLite file` --rationale_for--> `PIN gates UI not the data/queries`  [INFERRED]
  lib/data/connection/native.dart → lib/state/auth_provider.dart
- `RATIONALE: catch-up at app launch (Flutter has no background scheduler)` --rationale_for--> `init({annualRaisePercent})`  [INFERRED]
  lib/data/ledger_repository.dart → lib/state/ledger_provider.dart
- `applyDueRaises(double percent)` --calls--> `applyAnniversaryRaises({percent, asOf})`  [EXTRACTED]
  lib/state/ledger_provider.dart → lib/data/ledger_repository.dart
- `init({annualRaisePercent})` --calls--> `applyAnniversaryRaises({percent, asOf})`  [EXTRACTED]
  lib/state/ledger_provider.dart → lib/data/ledger_repository.dart
- `RATIONALE: BS start month anchors the anniversary month` --rationale_for--> `Units.startedOn column`  [EXTRACTED]
  lib/data/ledger_repository.dart → lib/data/database.dart

## Communities

### Community 0 - "Home Screen UI"
Cohesion: 0.07
Nodes (28): build, Container, dispose, _Empty, Expanded, _FilterChip, GlassPanel, _Header (+20 more)

### Community 1 - "Reports Screen"
Cohesion: 0.07
Nodes (26): ../../domain/models.dart, _BreakdownRow, build, Center, dispose, _exportSuffix, GlassPanel, initState (+18 more)

### Community 2 - "Theme & Nav Shell"
Cohesion: 0.08
Nodes (24): dart:ui, glass.dart, Brand, buildTheme, display, build, _CenterAddButton, Expanded (+16 more)

### Community 3 - "Unit Detail Sheet"
Cohesion: 0.08
Nodes (25): edit_unit_sheet.dart, _BaseBigButton, _BigToggleButton, build, Column, _DetailCell, dispose, Expanded (+17 more)

### Community 4 - "Settings Screen"
Cohesion: 0.08
Nodes (25): dart:convert, AlertDialog, build, _CalendarToggle, Column, dispose, _Divider, fmtPercent (+17 more)

### Community 5 - "Glass UI Widgets"
Cohesion: 0.08
Nodes (23): BrandBackground, BrandProgressBar, build, ClipRect, ClipRRect, CodeAvatar, Container, DecoratedBox (+15 more)

### Community 6 - "Ledger & Rent-Raise Logic"
Cohesion: 0.13
Nodes (18): AppDatabase, MigrationStrategy onUpgrade addColumn (v1->v2), AppDatabase.schemaVersion (=2), Units table, Units.lastRaisedOn column, Units.startedOn column, applyDueRaises(double percent), init({annualRaisePercent}) (+10 more)

### Community 7 - "Edit Unit Form"
Cohesion: 0.12
Nodes (16): build, _DateField, dispose, EditUnitSheet, _EditUnitSheetState, _Field, Form, Icon (+8 more)

### Community 8 - "Drift Generated Models"
Cohesion: 0.13
Nodes (16): _, copyWith, copyWithCompanion, f, Function, map, Payment, PaymentsCompanion (+8 more)

### Community 9 - "App Bootstrap & Routing"
Cohesion: 0.13
Nodes (14): app/router.dart, data/ledger_repository.dart, ../../domain/bs_calendar.dart, build, MaterialApp, MultiProvider, SizedBox, _StartupErrorApp (+6 more)

### Community 10 - "Units List Screen"
Cohesion: 0.15
Nodes (12): ../../domain/money.dart, _ActiveBadge, build, Container, GlassPanel, SafeArea, SizedBox, SliverFillRemaining (+4 more)

### Community 11 - "Login / PIN Screen"
Cohesion: 0.15
Nodes (12): build, dispose, Icon, LoginScreen, _LoginScreenState, _PinField, Scaffold, SizedBox (+4 more)

### Community 12 - "Toast Notifications"
Cohesion: 0.18
Nodes (10): ../../app/theme.dart, build, dispose, initState, Positioned, showToast, showToastOn, SizedBox (+2 more)

### Community 13 - "PIN Authentication"
Cohesion: 0.29
Nodes (10): AuthProvider, Legacy single-round SHA-256 PIN migration, AuthProvider.load, PBKDF2-HMAC-SHA256 derivation (100k iters, off-thread), AuthProvider.setPin, PIN salt+hash stored in shared_preferences, PIN gates UI not the data/queries, AuthProvider.unlock (+2 more)

### Community 14 - "Raise-Percent Settings"
Cohesion: 0.25
Nodes (8): RATIONALE: fractional double percent for finer rate control (e.g. 7.5%), RATIONALE: new prefs key avoids int<->double SharedPreferences type clash, annualRaisePercent (double getter), _defaultRaisePercent (5), _kRaisePercent ('annual_raise_pct'), _maxRaisePercent (1000 guard), setAnnualRaisePercent(double), SettingsProvider

### Community 15 - "Domain Models"
Cohesion: 0.25
Nodes (7): ../data/database.dart, HistoryEntry, MonthBucket, MonthSummary, PeriodDebt, PeriodSummary, UnitRow

### Community 16 - "Money Formatting"
Cohesion: 0.4
Nodes (4): format, grouped, Money, package:intl/intl.dart

### Community 17 - "Web DB Connection"
Cohesion: 1.0
Nodes (2): web openLedgerExecutor, WASM/OPFS unencrypted web ledger

### Community 18 - "Platform DB Dispatch"
Cohesion: 1.0
Nodes (2): openLedgerExecutor (conditional export dispatch), Compile-time platform backend dispatch (native vs web)

### Community 19 - "Router Builder"
Cohesion: 1.0
Nodes (1): buildRouter

### Community 20 - "BS Calendar Conversion"
Cohesion: 1.0
Nodes (1): bsYearMonth(DateTime)

### Community 21 - "BS Month Start"
Cohesion: 1.0
Nodes (1): adForBsMonthStart(year, month)

### Community 22 - "BS Date Labeling"
Cohesion: 1.0
Nodes (1): dateLabel(date, mode)

## Knowledge Gaps
- **243 isolated node(s):** `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState`, `build`, `MaterialApp` (+238 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Web DB Connection`** (2 nodes): `web openLedgerExecutor`, `WASM/OPFS unencrypted web ledger`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Platform DB Dispatch`** (2 nodes): `openLedgerExecutor (conditional export dispatch)`, `Compile-time platform backend dispatch (native vs web)`
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

- **Why does `package:flutter/material.dart` connect `Theme & Nav Shell` to `Home Screen UI`, `Reports Screen`, `Unit Detail Sheet`, `Settings Screen`, `Glass UI Widgets`, `Edit Unit Form`, `App Bootstrap & Routing`, `Units List Screen`, `Login / PIN Screen`, `Toast Notifications`?**
  _High betweenness centrality (0.186) - this node is a cross-community bridge._
- **Why does `../../app/theme.dart` connect `Toast Notifications` to `Home Screen UI`, `Reports Screen`, `Theme & Nav Shell`, `Unit Detail Sheet`, `Settings Screen`, `Glass UI Widgets`, `Edit Unit Form`, `App Bootstrap & Routing`, `Units List Screen`, `Login / PIN Screen`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Why does `../data/database.dart` connect `Domain Models` to `App Bootstrap & Routing`, `Unit Detail Sheet`, `Edit Unit Form`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **What connects `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState` to the rest of the system?**
  _243 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Home Screen UI` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Reports Screen` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Theme & Nav Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._