# Reports Page — Improvement Plan

Scope agreed 2026-09-22: Phase 1 (quick wins) and Phase 2 (income breakdown).
Cross-year reporting was considered and dropped from this plan — then built
after all on 2026-10-02 as the AD-mode "Jan–Dec" Year scope (see the status
section at the bottom).

Context: the month's due is now `rent + charges − deduction` everywhere
(see `netDue` in `lib/domain/models.dart`), and reports already price
historical months at the rent in effect then (`RentSchedule`).

## Phase 1 — Quick wins

- [x] **1a. Actionable Outstanding rows** — tapping a row opens the unit's
      detail sheet; an SMS icon (when a phone is on file) sends the overdue
      reminder with the true amount owed. Multi-month debts get their own
      reminder wording ("across N months") instead of a single month's label.
- [x] **1b. Actionable deposit card** — when vacated units owe refunds, the
      Deposit liability card expands to list them (code · tenant · amount);
      tapping a row opens that unit's sheet, where the refund is recorded.
- [x] **1c. Honest "Paid n/m" metric** — months before a tenant moved in no
      longer count as paid slots, and the denominator only counts months a
      unit actually owed. (Previously a tenant who moved in month 4 showed
      "Paid 3/12" before paying anything.)

## Phase 2 — Rent / charges / deduction breakdown

- [x] **2a. Components from `periodSummary`** — return `rentExpected`,
      `chargesExpected` and `deductions` alongside `expected`, computed in the
      existing loop (no new queries). Per-month deductions are capped at that
      month's rent + charges so the identity
      `expected = rentExpected + chargesExpected − deductions` holds exactly.
- [x] **2b. Breakdown line on the Reports screen** — under the summary grid,
      shown only when charges or deductions exist in the period:
      `Rent Rs A · + Charges Rs B · − Deductions Rs C`.
- [x] **2c. Tests** — component sums, the cap identity, and the fixed slot
      metric.

Note: the CSV export already carries the split per row
(`deduction,electricity,water,service` columns added 2026-09-22), so no CSV
change is needed in Phase 2.

## Done when

`flutter analyze` clean, `flutter test` green, and each checkbox above ticked.

## Status — 2026-09-22

All Phase 1 and Phase 2 tasks are implemented. `flutter analyze` clean
(one pre-existing doc-comment info lint in `store_screenshots_test.dart`),
`flutter test` green: 148 passed, 15 skipped (store-screenshot goldens,
skipped by design). (Committed and shipped since — see below.)

## Shipped — v1.1.0, live on the App Store since 2026-09-23

Everything above plus, from the same stretch of work:

- **USD currency setting** (NPR stays the default) — global setting, synced
  across devices, threaded through every money display, SMS text, and the
  JSON backup round-trip.
- **AD calendar labels by default for new installs only** — existing users
  untouched (fresh-install detection via `AuthProvider.hasExistingInstall`).
- The earlier "due = rent + charges − deduction" change, the current-month
  fix, typed-ERASE confirmation, and the Apple-HIG reskin.
- App Store listing refreshed (subtitle `Landlord & Tenant Ledger`,
  optimized keywords incl. Romanized-Nepali terms, full-feature description
  with FAQ block). Deployed headlessly via the ASC API — pipeline recorded
  in the project memory (`rent-bee-release-pipeline`).

## Status — 2026-10-02 (uncommitted on `feat/rent-deductions-perf`)

New since 1.1.0, all verified (`flutter analyze` clean, 195 tests passing
before the parallel bug-fix session added more):

- **Reports → Year follows the display calendar**: in AD mode the Year scope
  is the calendar year, "Jan – Dec", spanning two BS years (Magh → Poush);
  BS mode keeps Baishakh–Chaitra. Built on new cross-year span plumbing in
  the repository (`periodSummarySpan`, `paymentsForSpan`/`chargesForSpan`,
  `exportCsvSpan`; the old single-year APIs remain as wrappers). Toggling
  the calendar in Settings reloads the report live.
- **Brand kit** (`lib/app/theme.dart`): new `Sys.brand` token — #FF6600
  light / #FF751F dark — used in exactly two signature moments (the money
  progress fills on Home and Reports). Tint and status colours reverted to
  the pure Apple palette after a too-orange detour.
- **macOS fixed for real**: `/Applications/Rent Bee.app` turned out to be
  the iOS App Store build running on Apple Silicon (never syncs — Firebase
  session can't persist there). The native Mac build now has the Keychain
  Sharing entitlement + real dev signing + the vendored
  `libsqlite3.x64.macos.dylib` (Release builds are universal), installed as
  "Rent Bee (Mac).app". App-side fix for the iOS-wrapper copy: future release.
- **Data recovery**: the "lost" Ashad/Shrawan ledger was found intact in
  Firestore under Shrawan 2082 (old hardcoded-month anchor) and migrated to
  Shrawan 2083; snapshot kept at
  `~/Documents/rentbee-cloud-snapshot-20261002-140357.json`.
- A **parallel Claude session** is working the review bug-fix queue
  (`buglog.md`): zone-free BS calendar conversions, schema v6 sync outbox,
  etc. File ownership is split; neither session commits the other's work.

## Open items

- Commit/push this session's pile (brand kit, Jan–Dec reports, macOS fixes,
  `.gitignore`) — awaiting the user's go.
- **Google Play deployment** still blocked on three one-time user steps:
  enable the Android Publisher API, grant the service account Play access,
  and `android/key.properties` + upload keystore (candidates:
  `~/Documents/anti/rent/key/keystore.jks`, `~/flutter_app/keys/keystore.jks`).
- Ship the Firebase-session fix for the iOS-on-Mac App Store copy in a
  future app update.
