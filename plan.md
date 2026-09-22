# Reports Page — Improvement Plan

Scope agreed 2026-09-22: Phase 1 (quick wins) and Phase 2 (income breakdown).
Cross-year reporting was considered and dropped from this plan.

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
skipped by design). Changes are uncommitted in the working tree, on branch
`feat/rent-deductions-perf`, together with the earlier
"due = rent + charges − deduction" change — review and commit when back.
