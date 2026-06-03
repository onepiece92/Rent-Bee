# Rent Bee (Flutter)

Offline-first mobile app for a landlord to track monthly rent across 30+ rented
shutters in **Bikram Sambat (BS)** months. Glassmorphic navy + orange brand,
ported from the `rent glass.md` build spec.

## Stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.41 (Dart) |
| Routing | **go_router** (`lib/app/router.dart`) |
| State management | **provider** (`LedgerProvider`, `AuthProvider`) |
| Offline DB | **Drift over SQLite** (`lib/data/database.dart`) — a typed relational SQL store. PostgreSQL cannot run on a phone, so SQLite via Drift is the offline equivalent; the schema (`shutters`, `payments`, unique `(shutter_id, year, month)`, cascade delete) maps 1:1 to the spec's data model. |
| Fonts | **Fraunces** (display) + **Hanken Grotesk** (UI/body), bundled as variable TTFs in `assets/fonts/` so the app renders fully offline — no runtime download |
| Money | whole-NPR integers, never floats; `Rs 1,80,000` en-IN grouping (`lib/domain/money.dart`) |
| Auth | single-owner local **PIN lock** — salted **PBKDF2-HMAC-SHA256** in `shared_preferences`, no server, no committed secrets. The local DB is not encrypted at rest. |

## Architecture

```
lib/
  app/        theme.dart (design tokens §6), router.dart (go_router)
  data/       database.dart (Drift tables) + .g.dart, ledger_repository.dart (all business logic §4)
  domain/     bs_calendar.dart (BS months + wrapping nav), money.dart, models.dart
  state/      ledger_provider.dart, auth_provider.dart  (ChangeNotifier / provider)
  ui/
    widgets/  glass.dart (BrandBackground, GlassPanel, BrandProgressBar)
    screens/  login_screen.dart, home_screen.dart, reports_screen.dart
    sheets/   shutter_detail_sheet.dart, edit_shutter_sheet.dart
```

Modeling choice (from spec): only **paid** rows are stored. A shutter is
**pending** for a month when no payment row exists — insert to pay, delete to
undo. Editing a shutter's rent never alters past payment amounts because the
amount is captured per `payments` record at mark time.

## Develop

```bash
flutter pub get
dart run build_runner build          # regenerate database.g.dart after schema changes
flutter analyze                      # clean
flutter test                         # unit tests for money / BS nav / repo logic
flutter run                          # pick a device
```

The DB auto-**seeds ~10 sample shutters** on first launch (`LedgerRepository.seedIfEmpty`).
The SQLite file lives in the app documents directory (`shutter_ledger.sqlite`).

## Build

```bash
flutter build apk          # Android (needs Android SDK / ANDROID_HOME)
flutter build ios          # iOS (needs Xcode)
flutter build macos        # desktop — verified building in this repo
```

## Features (v1 scope)

- Home month ledger: BS month switcher (`‹ Jestha 2082 ›`), summary card
  (collected / expected, progress, paid count, pending), search + All/Pending/Paid
  filters, shutter rows with Mark-paid / Paid pills, FAB to add.
- Shutter detail sheet: Collect/Undo for the selected month, 6-month history
  strip, edit, delete (cascades payments).
- Add / edit shutter sheet (code, tenant, business, rent, phone, active).
- Reports: monthly summary grid, outstanding list, **CSV export/share**.
- PIN login (set on first run, unlock after).

## Notes / future work (out of scope v1)

Multi-user, tenant portal, SMS/WhatsApp reminders, leases/deposits/utilities,
late fees, partial-payment installments, and a `tenancies` history table are all
deferred per the spec.
