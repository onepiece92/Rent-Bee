# Graph Report - .  (2026-06-03)

## Corpus Check
- 0 files · ~47,000 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 460 nodes · 479 edges · 47 communities detected
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.77)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Unit Detail Sheet|Unit Detail Sheet]]
- [[_COMMUNITY_Home Screen UI|Home Screen UI]]
- [[_COMMUNITY_Ledger Repository & Models|Ledger Repository & Models]]
- [[_COMMUNITY_Edit Unit Sheet|Edit Unit Sheet]]
- [[_COMMUNITY_Unit Detail Sheet|Unit Detail Sheet]]
- [[_COMMUNITY_Settings & Auto-Raise|Settings & Auto-Raise]]
- [[_COMMUNITY_Reports Screen|Reports Screen]]
- [[_COMMUNITY_Glass Widgets|Glass Widgets]]
- [[_COMMUNITY_Automatic Rent Increase|Automatic Rent Increase]]
- [[_COMMUNITY_Unit Tests|Unit Tests]]
- [[_COMMUNITY_Local DB & Backends|Local DB & Backends]]
- [[_COMMUNITY_JSX Prototype|JSX Prototype]]
- [[_COMMUNITY_BSAD Calendar|BS/AD Calendar]]
- [[_COMMUNITY_PIN Auth (PBKDF2)|PIN Auth (PBKDF2)]]
- [[_COMMUNITY_Units Screen|Units Screen]]
- [[_COMMUNITY_macOS App Delegate|macOS App Delegate]]
- [[_COMMUNITY_Home Screen UI|Home Screen UI]]
- [[_COMMUNITY_Edit Unit Sheet|Edit Unit Sheet]]
- [[_COMMUNITY_Money & LLDB Helper|Money & LLDB Helper]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Old Icon|Old Icon]]
- [[_COMMUNITY_New Rent Bee Icon|New Rent Bee Icon]]
- [[_COMMUNITY_iOS Runner Tests|iOS Runner Tests]]
- [[_COMMUNITY_Plugin Registrants|Plugin Registrants]]
- [[_COMMUNITY_macOS Main Window|macOS Main Window]]
- [[_COMMUNITY_macOS Scene Delegate|macOS Scene Delegate]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_iOS Runner Tests|iOS Runner Tests]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Plugin Registrants|Plugin Registrants]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_iOS Runner Tests|iOS Runner Tests]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Plugin Registrants|Plugin Registrants]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Settings & Auto-Raise|Settings & Auto-Raise]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Routing & App Shell|Routing & App Shell]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]

## God Nodes (most connected - your core abstractions)
1. `_` - 17 edges
2. `package:flutter/material.dart` - 9 edges
3. `AppDelegate` - 8 edges
4. `../../app/theme.dart` - 7 edges
5. `applyAnniversaryRaises({percent, asOf})` - 7 edges
6. `package:drift/drift.dart` - 6 edges
7. `Shutter Ledger Build Spec` - 6 edges
8. `package:provider/provider.dart` - 6 edges
9. `Rent Bee App Icon` - 5 edges
10. `PIN salt+hash stored in shared_preferences` - 5 edges

## Surprising Connections (you probably didn't know these)
- `PIN lock — PBKDF2 in shared_preferences, DB not encrypted at rest` --semantically_similar_to--> `Plain unencrypted NativeDatabase SQLite file`  [INFERRED] [semantically similar]
  README.md → lib/data/connection/native.dart
- `Single-owner local PIN lock (PBKDF2 in shared_preferences)` --semantically_similar_to--> `PIN salt+hash stored in shared_preferences`  [EXTRACTED] [semantically similar]
  rent glass.md → lib/state/auth_provider.dart
- `DB not encrypted at rest on any platform` --semantically_similar_to--> `Plain unencrypted NativeDatabase SQLite file`  [EXTRACTED] [semantically similar]
  rent glass.md → lib/data/connection/native.dart
- `DB not encrypted at rest on any platform` --semantically_similar_to--> `WASM/OPFS unencrypted web ledger`  [EXTRACTED] [semantically similar]
  rent glass.md → lib/data/connection/web.dart
- `PIN lock — PBKDF2 in shared_preferences, DB not encrypted at rest` --semantically_similar_to--> `PIN salt+hash stored in shared_preferences`  [EXTRACTED] [semantically similar]
  README.md → lib/state/auth_provider.dart

## Hyperedges (group relationships)
- **Setting feeds startup init which applies due anniversary raises against start/last-raised dates** — settings_provider_annualraisepercent, ledger_provider_init, ledger_repository_applyanniversaryraises, ledger_repository_startedon, ledger_repository_lastraisedon [INFERRED 0.80]
- **Editing the rate persists it and immediately catches up due raises** — settings_screen_editraisepercent, settings_provider_setannualraisepercent, ledger_provider_applydueraises, ledger_repository_applyanniversaryraises [INFERRED 0.85]

## Communities

### Community 0 - "Unit Detail Sheet"
Cohesion: 0.05
Nodes (39): app/router.dart, ../../app/theme.dart, build, MaterialApp, MultiProvider, SizedBox, _StartupErrorApp, Text (+31 more)

### Community 1 - "Home Screen UI"
Cohesion: 0.06
Nodes (30): build, Container, dispose, _Empty, Expanded, _FilterChip, GlassPanel, _Header (+22 more)

### Community 2 - "Ledger Repository & Models"
Cohesion: 0.07
Nodes (27): ../data/ledger_repository.dart, database.dart, ../domain/bs_calendar.dart, ../domain/models.dart, cell, col, _csv, eraseAll (+19 more)

### Community 3 - "Edit Unit Sheet"
Cohesion: 0.08
Nodes (24): dart:ui, glass.dart, Brand, buildTheme, display, build, _CenterAddButton, Expanded (+16 more)

### Community 4 - "Unit Detail Sheet"
Cohesion: 0.08
Nodes (25): ../../domain/money.dart, edit_unit_sheet.dart, _BaseBigButton, _BigToggleButton, build, Column, _DetailCell, dispose (+17 more)

### Community 5 - "Settings & Auto-Raise"
Cohesion: 0.08
Nodes (25): AlertDialog, build, _CalendarToggle, Column, dispose, _Divider, fmtPercent, Icon (+17 more)

### Community 6 - "Reports Screen"
Cohesion: 0.08
Nodes (24): _BreakdownRow, build, Center, dispose, _exportSuffix, GlassPanel, initState, ListView (+16 more)

### Community 7 - "Glass Widgets"
Cohesion: 0.08
Nodes (23): BrandBackground, BrandProgressBar, build, ClipRect, ClipRRect, CodeAvatar, Container, DecoratedBox (+15 more)

### Community 8 - "Automatic Rent Increase"
Cohesion: 0.09
Nodes (24): applyDueRaises(double percent), init({annualRaisePercent}), LedgerProvider, applyAnniversaryRaises({percent, asOf}), lastRaisedOn stamp, LedgerRepository, startedOn (rent-start date), RATIONALE: catch-up at app launch (Flutter has no background scheduler) (+16 more)

### Community 9 - "Unit Tests"
Cohesion: 0.09
Nodes (19): connection/connection.dart, dart:io, LazyDatabase, NativeDatabase, AppDatabase, customStatement, Payments, Units (+11 more)

### Community 10 - "Local DB & Backends"
Cohesion: 0.13
Nodes (22): AuthProvider, Legacy single-round SHA-256 PIN migration, AuthProvider.load, PBKDF2-HMAC-SHA256 derivation (100k iters, off-thread), AuthProvider.setPin, PIN salt+hash stored in shared_preferences, PIN gates UI not the data/queries, AuthProvider.unlock (+14 more)

### Community 11 - "JSX Prototype"
Cohesion: 0.1
Nodes (18): _, copyWith, copyWithCompanion, f, Function, map, Payment, PaymentsCompanion (+10 more)

### Community 12 - "BS/AD Calendar"
Cohesion: 0.11
Nodes (17): adForBsMonthStart, BsCalendar, BsMonth, DateFormat, dateLabel, label, labelIn, labelWithYear (+9 more)

### Community 13 - "PIN Auth (PBKDF2)"
Cohesion: 0.18
Nodes (10): dart:convert, dart:math, AuthProvider, compute, _legacyHash, lock, _newSalt, _pbkdf2Worker (+2 more)

### Community 14 - "Units Screen"
Cohesion: 0.2
Nodes (9): _ActiveBadge, build, Container, GlassPanel, SafeArea, SizedBox, SliverFillRemaining, SliverPadding (+1 more)

### Community 15 - "macOS App Delegate"
Cohesion: 0.22
Nodes (3): AppDelegate, FlutterAppDelegate, FlutterImplicitEngineDelegate

### Community 16 - "Home Screen UI"
Cohesion: 0.22
Nodes (8): buildRouter, GoRouter, ../ui/screens/home_screen.dart, ../ui/screens/login_screen.dart, ../ui/screens/reports_screen.dart, ../ui/screens/settings_screen.dart, ../ui/screens/units_screen.dart, ../ui/widgets/scaffold_with_navbar.dart

### Community 17 - "Edit Unit Sheet"
Cohesion: 0.28
Nodes (9): dateLabel(date, mode), AppDatabase, MigrationStrategy onUpgrade addColumn (v1->v2), AppDatabase.schemaVersion (=2), Units table, Units.lastRaisedOn column, Units.startedOn column, EditUnitSheet (+1 more)

### Community 18 - "Money & LLDB Helper"
Cohesion: 0.25
Nodes (6): handle_new_rx_page(), __lldb_init_module(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., format, grouped, Money

### Community 19 - "Community 19"
Cohesion: 0.25
Nodes (7): ../data/database.dart, HistoryEntry, MonthBucket, MonthSummary, PeriodDebt, PeriodSummary, UnitRow

### Community 20 - "Old Icon"
Cohesion: 0.4
Nodes (6): Blue color palette (light sky blue to deep navy gradient), Stylized Flutter 'F' chevron mark (default Flutter logo), Rent Bee App Icon (1024px master launcher), Placeholder/unbranded default identity (no Rent Bee custom brand), Rent Bee rental application brand identity, White rounded-square (squircle) background tile

### Community 21 - "New Rent Bee Icon"
Cohesion: 0.53
Nodes (6): Cartoon bee mascot (yellow/black striped, smiling, wings), Yellow/orange gradient background with honeycomb hexagon pattern, Golden key with R-shaped bow and hexagonal head, Letter R on key bow (Rent branding initial), Rent Bee App Icon, Rounded-square iOS-style app icon tile with light border

### Community 22 - "iOS Runner Tests"
Cohesion: 0.4
Nodes (2): RunnerTests, XCTestCase

### Community 23 - "Plugin Registrants"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 24 - "macOS Main Window"
Cohesion: 0.5
Nodes (2): MainFlutterWindow, NSWindow

### Community 25 - "macOS Scene Delegate"
Cohesion: 0.67
Nodes (2): FlutterSceneDelegate, SceneDelegate

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (1): PodsDummy_share_plus

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): PodsDummy_Pods_Runner

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): PodsDummy_shared_preferences_foundation

### Community 29 - "iOS Runner Tests"
Cohesion: 1.0
Nodes (1): PodsDummy_Pods_RunnerTests

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (2): openLedgerExecutor (conditional export dispatch), Compile-time platform backend dispatch (native vs web)

### Community 32 - "Plugin Registrants"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "iOS Runner Tests"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Plugin Registrants"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Settings & Auto-Raise"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (1): Launch Screen Assets (default Flutter template)

### Community 43 - "Routing & App Shell"
Cohesion: 1.0
Nodes (1): buildRouter

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (1): bsYearMonth(DateTime)

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (1): adForBsMonthStart(year, month)

## Knowledge Gaps
- **319 isolated node(s):** `PodsDummy_share_plus`, `PodsDummy_Pods_Runner`, `PodsDummy_shared_preferences_foundation`, `PodsDummy_Pods_RunnerTests`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.` (+314 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 26`** (2 nodes): `share_plus-dummy.m`, `PodsDummy_share_plus`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (2 nodes): `Pods-Runner-dummy.m`, `PodsDummy_Pods_Runner`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (2 nodes): `shared_preferences_foundation-dummy.m`, `PodsDummy_shared_preferences_foundation`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Runner Tests`** (2 nodes): `Pods-RunnerTests-dummy.m`, `PodsDummy_Pods_RunnerTests`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (2 nodes): `openLedgerExecutor (conditional export dispatch)`, `Compile-time platform backend dispatch (native vs web)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Plugin Registrants`** (2 nodes): `RegisterGeneratedPlugins()`, `GeneratedPluginRegistrant.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `share_plus-umbrella.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (1 nodes): `Pods-Runner-umbrella.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (1 nodes): `shared_preferences_foundation-umbrella.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Runner Tests`** (1 nodes): `Pods-RunnerTests-umbrella.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (1 nodes): `Runner-Bridging-Header.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Plugin Registrants`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Settings & Auto-Raise`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (1 nodes): `Launch Screen Assets (default Flutter template)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Routing & App Shell`** (1 nodes): `buildRouter`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `connection.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `bsYearMonth(DateTime)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `adForBsMonthStart(year, month)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:drift/drift.dart` connect `Unit Tests` to `Unit Detail Sheet`, `Ledger Repository & Models`?**
  _High betweenness centrality (0.053) - this node is a cross-community bridge._
- **Why does `package:flutter/material.dart` connect `Edit Unit Sheet` to `Unit Detail Sheet`, `Home Screen UI`, `Unit Detail Sheet`, `Settings & Auto-Raise`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Why does `../../app/theme.dart` connect `Unit Detail Sheet` to `Home Screen UI`, `Edit Unit Sheet`, `Unit Detail Sheet`, `Settings & Auto-Raise`?**
  _High betweenness centrality (0.035) - this node is a cross-community bridge._
- **What connects `PodsDummy_share_plus`, `PodsDummy_Pods_Runner`, `PodsDummy_shared_preferences_foundation` to the rest of the system?**
  _319 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Unit Detail Sheet` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Home Screen UI` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Ledger Repository & Models` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._