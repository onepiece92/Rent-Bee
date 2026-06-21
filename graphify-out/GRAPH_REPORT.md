# Graph Report - lib  (2026-06-21)

## Corpus Check
- Corpus is ~37,533 words - fits in a single context window. You may not need a graph.

## Summary
- 511 nodes · 590 edges · 26 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Firestore Sync & Auth Provider|Firestore Sync & Auth Provider]]
- [[_COMMUNITY_Home & Units Screens|Home & Units Screens]]
- [[_COMMUNITY_Ledger Repository & Schema|Ledger Repository & Schema]]
- [[_COMMUNITY_Theme & UI Primitives|Theme & UI Primitives]]
- [[_COMMUNITY_Domain Models & Charges|Domain Models & Charges]]
- [[_COMMUNITY_Settings Screen|Settings Screen]]
- [[_COMMUNITY_Routing & Nav Shell|Routing & Nav Shell]]
- [[_COMMUNITY_Reports Screen|Reports Screen]]
- [[_COMMUNITY_App Bootstrap & Ledger State|App Bootstrap & Ledger State]]
- [[_COMMUNITY_Unit Detail Sheet|Unit Detail Sheet]]
- [[_COMMUNITY_Glass UI Components|Glass UI Components]]
- [[_COMMUNITY_BS Calendar & Money|BS Calendar & Money]]
- [[_COMMUNITY_Phone Auth & Onboarding|Phone Auth & Onboarding]]
- [[_COMMUNITY_Edit Unit Sheet|Edit Unit Sheet]]
- [[_COMMUNITY_CSV Share & Dialogs|CSV Share & Dialogs]]
- [[_COMMUNITY_PIN Login Screens|PIN Login Screens]]
- [[_COMMUNITY_Generated Drift Code|Generated Drift Code]]
- [[_COMMUNITY_Sponsored Carousel & Sync|Sponsored Carousel & Sync]]
- [[_COMMUNITY_SMS Reminders & Unit Edit|SMS Reminders & Unit Edit]]
- [[_COMMUNITY_Firebase Options|Firebase Options]]
- [[_COMMUNITY_Unit Code Suggestion|Unit Code Suggestion]]
- [[_COMMUNITY_Phone Normalization|Phone Normalization]]
- [[_COMMUNITY_Web DB Backend|Web DB Backend]]
- [[_COMMUNITY_Native DB Backend|Native DB Backend]]
- [[_COMMUNITY_Firebase Config|Firebase Config]]
- [[_COMMUNITY_DB Connection Resolver|DB Connection Resolver]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 22 edges
2. `../../app/theme.dart` - 19 edges
3. `_` - 19 edges
4. `../../data/database.dart` - 8 edges
5. `package:provider/provider.dart` - 8 edges
6. `package:flutter/services.dart` - 6 edges
7. `../../domain/bs_calendar.dart` - 6 edges
8. `../state/auth_provider.dart` - 6 edges
9. `../widgets/glass.dart` - 6 edges
10. `package:flutter/foundation.dart` - 6 edges

## Surprising Connections (you probably didn't know these)
- `UnitDetailSheet` --calls--> `sendRentReminder`  [EXTRACTED]
  lib/ui/sheets/unit_detail_sheet.dart → lib/ui/util/sms_reminder.dart

## Communities

### Community 0 - "Firestore Sync & Auth Provider"
Cohesion: 0.05
Nodes (43): dart:math, database.dart, firestore_sync_service.dart, ledger_repository.dart, _applyChargeDoc, _applyPaymentDoc, attachListeners, _childId (+35 more)

### Community 1 - "Home & Units Screens"
Cohesion: 0.04
Nodes (45): ../../domain/money.dart, _AddFirstUnitButton, build, _CardSmsButton, Container, dispose, _Empty, Expanded (+37 more)

### Community 2 - "Ledger Repository & Schema"
Cohesion: 0.06
Nodes (33): connection/connection.dart, AppDatabase, Charges, customStatement, Payments, Units, cell, _chargeFromBackup (+25 more)

### Community 3 - "Theme & UI Primitives"
Cohesion: 0.07
Nodes (27): ../../app/theme.dart, Brand, buildTheme, display, build, DepositCell, Expanded, SizedBox (+19 more)

### Community 4 - "Domain Models & Charges"
Cohesion: 0.07
Nodes (26): ../../data/database.dart, HistoryEntry, MonthBucket, MonthSummary, PeriodDebt, PeriodSummary, UnitRow, build (+18 more)

### Community 5 - "Settings Screen"
Cohesion: 0.07
Nodes (27): build, _CalendarToggle, Column, dispose, _Divider, fmtPercent, GlassDialog, Icon (+19 more)

### Community 6 - "Routing & Nav Shell"
Cohesion: 0.07
Nodes (25): buildRouter, GoRouter, build, _CenterAddButton, Expanded, GestureDetector, _GlassNavBar, _go (+17 more)

### Community 7 - "Reports Screen"
Cohesion: 0.07
Nodes (26): _BreakdownRow, build, Center, dispose, _exportSuffix, GlassPanel, initState, ListView (+18 more)

### Community 8 - "App Bootstrap & Ledger State"
Cohesion: 0.08
Nodes (25): app/router.dart, ../data/ledger_repository.dart, data/sync_bootstrap.dart, ../../domain/bs_calendar.dart, ../domain/models.dart, build, dispose, initState (+17 more)

### Community 9 - "Unit Detail Sheet"
Cohesion: 0.08
Nodes (25): charges_section.dart, deposit_cell.dart, edit_unit_sheet.dart, _BaseBigButton, _BigToggleButton, build, Column, Container (+17 more)

### Community 10 - "Glass UI Components"
Cohesion: 0.08
Nodes (23): BrandBackground, BrandProgressBar, build, ClipRect, ClipRRect, CodeAvatar, Container, DecoratedBox (+15 more)

### Community 11 - "BS Calendar & Money"
Cohesion: 0.09
Nodes (20): adForBsMonthStart, BsCalendar, BsMonth, DateFormat, dateLabel, label, labelIn, labelWithYear (+12 more)

### Community 12 - "Phone Auth & Onboarding"
Cohesion: 0.09
Nodes (20): ../../data/phone_auth_service.dart, ../../domain/phone.dart, ../firebase_options.dart, FirebaseAuthException, Function, _message, PhoneAuthService, build (+12 more)

### Community 13 - "Edit Unit Sheet"
Cohesion: 0.09
Nodes (21): ../../domain/unit_code.dart, BoxConstraints, build, _DateField, dispose, EditUnitSheet, _EditUnitSheetState, _Field (+13 more)

### Community 14 - "CSV Share & Dialogs"
Cohesion: 0.1
Nodes (18): dart:convert, dart:typed_data, dart:ui, _ActionButton, build, _Card, DecoratedBox, GlassDialog (+10 more)

### Community 15 - "PIN Login Screens"
Cohesion: 0.11
Nodes (18): build, dispose, Icon, LoginScreen, _LoginScreenState, Scaffold, SizedBox, Text (+10 more)

### Community 16 - "Generated Drift Code"
Cohesion: 0.12
Nodes (18): _, Charge, ChargesCompanion, copyWith, copyWithCompanion, f, Function, map (+10 more)

### Community 17 - "Sponsored Carousel & Sync"
Cohesion: 0.12
Nodes (15): dart:async, glass.dart, _advance, build, dispose, GlassPanel, Icon, initState (+7 more)

### Community 18 - "SMS Reminders & Unit Edit"
Cohesion: 0.29
Nodes (7): Rationale: SMS logic shared between card and detail sheet, rentReminderText, sendRentReminder, sendSms, _BigToggleButton (Collect/Undo), _HistoryStrip, UnitDetailSheet

### Community 19 - "Firebase Options"
Cohesion: 0.67
Nodes (2): DefaultFirebaseOptions, UnsupportedError

### Community 20 - "Unit Code Suggestion"
Cohesion: 0.67
Nodes (2): _firstFree, suggestUnitCode

### Community 21 - "Phone Normalization"
Cohesion: 1.0
Nodes (1): normalizePhone

### Community 22 - "Web DB Backend"
Cohesion: 1.0
Nodes (2): web openLedgerExecutor, WASM/OPFS unencrypted web ledger

### Community 23 - "Native DB Backend"
Cohesion: 1.0
Nodes (2): native openLedgerExecutor, Plain unencrypted NativeDatabase SQLite file

### Community 24 - "Firebase Config"
Cohesion: 1.0
Nodes (1): DefaultFirebaseOptions (FlutterFire config)

### Community 25 - "DB Connection Resolver"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **434 isolated node(s):** `DefaultFirebaseOptions`, `UnsupportedError`, `buildRouter`, `GoRouter`, `../ui/screens/home_screen.dart` (+429 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Phone Normalization`** (2 nodes): `phone.dart`, `normalizePhone`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Web DB Backend`** (2 nodes): `web openLedgerExecutor`, `WASM/OPFS unencrypted web ledger`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Native DB Backend`** (2 nodes): `native openLedgerExecutor`, `Plain unencrypted NativeDatabase SQLite file`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Firebase Config`** (1 nodes): `DefaultFirebaseOptions (FlutterFire config)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `DB Connection Resolver`** (1 nodes): `connection.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Theme & UI Primitives` to `Home & Units Screens`, `Domain Models & Charges`, `Settings Screen`, `Routing & Nav Shell`, `Reports Screen`, `App Bootstrap & Ledger State`, `Unit Detail Sheet`, `Glass UI Components`, `Phone Auth & Onboarding`, `Edit Unit Sheet`, `CSV Share & Dialogs`, `PIN Login Screens`, `Sponsored Carousel & Sync`?**
  _High betweenness centrality (0.261) - this node is a cross-community bridge._
- **Why does `../../app/theme.dart` connect `Theme & UI Primitives` to `Home & Units Screens`, `Domain Models & Charges`, `Settings Screen`, `Routing & Nav Shell`, `Reports Screen`, `App Bootstrap & Ledger State`, `Unit Detail Sheet`, `Glass UI Components`, `Phone Auth & Onboarding`, `Edit Unit Sheet`, `CSV Share & Dialogs`, `PIN Login Screens`, `Sponsored Carousel & Sync`?**
  _High betweenness centrality (0.224) - this node is a cross-community bridge._
- **Why does `../../domain/bs_calendar.dart` connect `App Bootstrap & Ledger State` to `Home & Units Screens`, `Ledger Repository & Schema`, `Edit Unit Sheet`, `Settings Screen`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **What connects `DefaultFirebaseOptions`, `UnsupportedError`, `buildRouter` to the rest of the system?**
  _434 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Firestore Sync & Auth Provider` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Home & Units Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
- **Should `Ledger Repository & Schema` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._