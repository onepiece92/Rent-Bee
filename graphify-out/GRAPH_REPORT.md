# Graph Report - lib  (2026-06-10)

## Corpus Check
- Corpus is ~31,205 words - fits in a single context window. You may not need a graph.

## Summary
- 464 nodes · 574 edges · 23 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Domain Models & Repository|Domain Models & Repository]]
- [[_COMMUNITY_Units & Onboarding Screens|Units & Onboarding Screens]]
- [[_COMMUNITY_Routing & Login|Routing & Login]]
- [[_COMMUNITY_Home Screen UI|Home Screen UI]]
- [[_COMMUNITY_Unit Detail & Collect|Unit Detail & Collect]]
- [[_COMMUNITY_Reports Screen|Reports Screen]]
- [[_COMMUNITY_Settings Screen|Settings Screen]]
- [[_COMMUNITY_Theme & Sheet Buttons|Theme & Sheet Buttons]]
- [[_COMMUNITY_Database Schema|Database Schema]]
- [[_COMMUNITY_Glass UI Widgets|Glass UI Widgets]]
- [[_COMMUNITY_BS Calendar & Money|BS Calendar & Money]]
- [[_COMMUNITY_Edit Unit Form|Edit Unit Form]]
- [[_COMMUNITY_Auth State & Shared Utils|Auth State & Shared Utils]]
- [[_COMMUNITY_Phone Auth (Firebase)|Phone Auth (Firebase)]]
- [[_COMMUNITY_Drift Generated Models|Drift Generated Models]]
- [[_COMMUNITY_Nav Bar & Sponsored Carousel|Nav Bar & Sponsored Carousel]]
- [[_COMMUNITY_Nav Bar Shell|Nav Bar Shell]]
- [[_COMMUNITY_PIN Authentication|PIN Authentication]]
- [[_COMMUNITY_Unit-Code Suggestion|Unit-Code Suggestion]]
- [[_COMMUNITY_Web DB Connection|Web DB Connection]]
- [[_COMMUNITY_Platform DB Dispatch|Platform DB Dispatch]]
- [[_COMMUNITY_Phone Normalization|Phone Normalization]]
- [[_COMMUNITY_Router Builder|Router Builder]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 22 edges
2. `../../app/theme.dart` - 19 edges
3. `_` - 19 edges
4. `package:provider/provider.dart` - 12 edges
5. `../domain/bs_calendar.dart` - 12 edges
6. `../../state/ledger_provider.dart` - 9 edges
7. `../data/database.dart` - 8 edges
8. `../../state/settings_provider.dart` - 8 edges
9. `../../domain/money.dart` - 8 edges
10. `../widgets/glass.dart` - 8 edges

## Surprising Connections (you probably didn't know these)
- `PIN gates UI not the data/queries` --rationale_for--> `Plain unencrypted NativeDatabase SQLite file`  [INFERRED]
  lib/state/auth_provider.dart → lib/data/connection/native.dart

## Communities

### Community 0 - "Domain Models & Repository"
Cohesion: 0.04
Nodes (45): app/router.dart, dart:math, ../data/database.dart, data/ledger_repository.dart, ../domain/bs_calendar.dart, ../domain/models.dart, ../../domain/money.dart, firebase_options.dart (+37 more)

### Community 1 - "Units & Onboarding Screens"
Cohesion: 0.06
Nodes (35): _ActiveBadge, build, Container, GlassPanel, SafeArea, SizedBox, SliverFillRemaining, SliverPadding (+27 more)

### Community 2 - "Routing & Login"
Cohesion: 0.06
Nodes (31): buildRouter, GoRouter, build, dispose, Icon, LoginScreen, _LoginScreenState, _PinField (+23 more)

### Community 3 - "Home Screen UI"
Cohesion: 0.06
Nodes (32): _AddFirstUnitButton, build, _CardSmsButton, Container, dispose, _Empty, Expanded, _FilterChip (+24 more)

### Community 4 - "Unit Detail & Collect"
Cohesion: 0.07
Nodes (26): charges_section.dart, deposit_cell.dart, edit_unit_sheet.dart, _BaseBigButton, _BigToggleButton, build, Column, Container (+18 more)

### Community 5 - "Reports Screen"
Cohesion: 0.07
Nodes (26): _BreakdownRow, build, Center, dispose, _exportSuffix, GlassPanel, initState, ListView (+18 more)

### Community 6 - "Settings Screen"
Cohesion: 0.08
Nodes (25): build, _CalendarToggle, Column, dispose, _Divider, fmtPercent, GlassDialog, Icon (+17 more)

### Community 7 - "Theme & Sheet Buttons"
Cohesion: 0.08
Nodes (22): ../../app/theme.dart, Brand, buildTheme, display, build, InkWell, SecondaryButton, SizedBox (+14 more)

### Community 8 - "Database Schema"
Cohesion: 0.08
Nodes (23): connection/connection.dart, database.dart, AppDatabase, Charges, customStatement, Payments, Units, cell (+15 more)

### Community 9 - "Glass UI Widgets"
Cohesion: 0.08
Nodes (23): BrandBackground, BrandProgressBar, build, ClipRect, ClipRRect, CodeAvatar, Container, DecoratedBox (+15 more)

### Community 10 - "BS Calendar & Money"
Cohesion: 0.09
Nodes (20): adForBsMonthStart, BsCalendar, BsMonth, DateFormat, dateLabel, label, labelIn, labelWithYear (+12 more)

### Community 11 - "Edit Unit Form"
Cohesion: 0.1
Nodes (20): ../../domain/unit_code.dart, BoxConstraints, build, _DateField, dispose, EditUnitSheet, _EditUnitSheetState, _Field (+12 more)

### Community 12 - "Auth State & Shared Utils"
Cohesion: 0.1
Nodes (18): dart:convert, dart:typed_data, dart:ui, _ActionButton, build, _Card, DecoratedBox, GlassDialog (+10 more)

### Community 13 - "Phone Auth (Firebase)"
Cohesion: 0.1
Nodes (18): ../../data/phone_auth_service.dart, ../../domain/phone.dart, FirebaseAuthException, Function, _message, PhoneAuthService, build, dispose (+10 more)

### Community 14 - "Drift Generated Models"
Cohesion: 0.12
Nodes (18): _, Charge, ChargesCompanion, copyWith, copyWithCompanion, f, Function, map (+10 more)

### Community 15 - "Nav Bar & Sponsored Carousel"
Cohesion: 0.12
Nodes (15): dart:async, glass.dart, _advance, build, dispose, GlassPanel, Icon, initState (+7 more)

### Community 16 - "Nav Bar Shell"
Cohesion: 0.13
Nodes (14): build, _CenterAddButton, Expanded, GestureDetector, _GlassNavBar, _go, _NavDest, _NavItem (+6 more)

### Community 17 - "PIN Authentication"
Cohesion: 0.29
Nodes (10): AuthProvider, Legacy single-round SHA-256 PIN migration, AuthProvider.load, PBKDF2-HMAC-SHA256 derivation (100k iters, off-thread), AuthProvider.setPin, PIN salt+hash stored in shared_preferences, PIN gates UI not the data/queries, AuthProvider.unlock (+2 more)

### Community 18 - "Unit-Code Suggestion"
Cohesion: 0.67
Nodes (2): _firstFree, suggestUnitCode

### Community 19 - "Web DB Connection"
Cohesion: 1.0
Nodes (2): web openLedgerExecutor, WASM/OPFS unencrypted web ledger

### Community 20 - "Platform DB Dispatch"
Cohesion: 1.0
Nodes (2): openLedgerExecutor (conditional export dispatch), Compile-time platform backend dispatch (native vs web)

### Community 21 - "Phone Normalization"
Cohesion: 1.0
Nodes (1): normalizePhone

### Community 22 - "Router Builder"
Cohesion: 1.0
Nodes (1): buildRouter

## Knowledge Gaps
- **386 isolated node(s):** `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState`, `build`, `MaterialApp` (+381 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Web DB Connection`** (2 nodes): `web openLedgerExecutor`, `WASM/OPFS unencrypted web ledger`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Platform DB Dispatch`** (2 nodes): `openLedgerExecutor (conditional export dispatch)`, `Compile-time platform backend dispatch (native vs web)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Phone Normalization`** (2 nodes): `phone.dart`, `normalizePhone`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Router Builder`** (1 nodes): `buildRouter`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Theme & Sheet Buttons` to `Domain Models & Repository`, `Units & Onboarding Screens`, `Routing & Login`, `Home Screen UI`, `Unit Detail & Collect`, `Reports Screen`, `Settings Screen`, `Glass UI Widgets`, `Edit Unit Form`, `Auth State & Shared Utils`, `Phone Auth (Firebase)`, `Nav Bar & Sponsored Carousel`, `Nav Bar Shell`?**
  _High betweenness centrality (0.219) - this node is a cross-community bridge._
- **Why does `../../app/theme.dart` connect `Theme & Sheet Buttons` to `Domain Models & Repository`, `Units & Onboarding Screens`, `Routing & Login`, `Home Screen UI`, `Unit Detail & Collect`, `Reports Screen`, `Settings Screen`, `Glass UI Widgets`, `Edit Unit Form`, `Auth State & Shared Utils`, `Phone Auth (Firebase)`, `Nav Bar & Sponsored Carousel`, `Nav Bar Shell`?**
  _High betweenness centrality (0.177) - this node is a cross-community bridge._
- **Why does `../domain/bs_calendar.dart` connect `Domain Models & Repository` to `Units & Onboarding Screens`, `Home Screen UI`, `Unit Detail & Collect`, `Reports Screen`, `Settings Screen`, `Database Schema`, `Edit Unit Form`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **What connects `_StartupErrorApp`, `UnitLedgerApp`, `_UnitLedgerAppState` to the rest of the system?**
  _386 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Domain Models & Repository` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
- **Should `Units & Onboarding Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Routing & Login` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._