# Shutter Ledger — Build Spec

A cross-platform **Flutter** app (mobile-first; also runs on macOS and web) for a landlord to track monthly rent across 30+ rented shutters/units. The owner records, each month, which tenants have paid and sees what's still outstanding. Fully offline — all data lives in a local SQLite database; no server, no cloud, no network dependency at runtime.

A working **UI prototype** already exists (`ShutterLedger.jsx`, glassmorphic, brand-themed). It is state-only with no persistence. This spec is for turning it into a real, deployed product. Port the prototype's look and interactions; replace its in-memory state with a backend + database.

---

## 1. Scope

**In scope (v1)**
- Single-owner app (one landlord account).
- Manage shutters (units): add, edit, delete, list.
- Per-month rent tracking in **Bikram Sambat (BS)** months.
- Mark a shutter paid / undo for a given month; edit amount, paid date, and method.
- Dashboard per selected month: expected vs collected, pending total, paid count.
- Search + filter (all / pending / paid).
- Per-shutter payment history (last 6+ months).
- Monthly summary + outstanding list; CSV export.

**Out of scope (v1)** — note as future work, do not build:
- Multi-user / role-based access, tenant self-service portal.
- Automated SMS/WhatsApp reminders (keep a manual "copy reminder text" helper only if cheap).
- Lease documents, deposits, utilities, late fees/penalties.
- Partial payments split across multiple installments (v1 treats a record as paid/unpaid; allow editing the amount, but one record per shutter per month).

---

## 2. Tech stack

Flutter, offline-first, fully local — no server, no cloud DB, no runtime network dependency. One codebase ships to iOS, Android, macOS, and web.

- **Framework:** Flutter (Dart). State via **provider** (`LedgerProvider`, `AuthProvider`); routing via **go_router**. Port the prototype's look and interactions.
- **DB:** **Drift** (typed SQL over SQLite). The backend is chosen at compile time by a conditional import (`lib/data/connection/{connection,native,web}.dart`):
  - **native** (iOS / Android / macOS / desktop): a plain on-disk SQLite file (`unit_ledger.sqlite` in the app documents dir).
  - **web**: `sqlite3` compiled to **WASM**, persisted by the browser (OPFS, falling back to IndexedDB) through a drift worker (`web/sqlite3.wasm`, `web/drift_worker.js`).
  - The DB is **not encrypted at rest** on any platform — it is protected by the device/app (or browser origin) sandbox plus the PIN UI lock, and no secure store / keychain is used. (If at-rest encryption is wanted later, add a cipher build keyed from a platform secure store.)
- **Auth:** single-owner **local PIN lock** (no accounts, no server). The PIN is stretched with **PBKDF2-HMAC-SHA256** (100k iterations, off the UI thread via `compute`); its salt + derived hash live in `shared_preferences` (the hash is not a secret — PBKDF2 makes brute-forcing a leaked hash expensive). Legacy single-round-SHA-256 PINs migrate transparently on next unlock. The PIN gates the *UI*, not the queries.
- **Styling:** Port the prototype as a Flutter theme (tokens in §6). Bundled variable fonts (Fraunces + Hanken Grotesk) so it renders fully offline — no runtime download.
- **Money:** integers in whole NPR; never floats. Display `Rs 18,000` (en-IN grouping) — `lib/domain/money.dart`.
- **Calendar:** Bikram Sambat months — `lib/domain/bs_calendar.dart`.

---

## 3. Data model

Drift (relational SQLite) schema in `lib/data/database.dart`. The prototype's "shutters" are modeled as the **`Units`** table — the code uses *unit* throughout. `month` is the BS month integer **1–12** (Baishakh = 1 … Chaitra = 12); `year` is the BS year (e.g. 2082). Single-owner: one local DB per install, no user/tenant scoping.

### `Units` table (`@DataClassName('Unit')`)
| column | type | notes |
|---|---|---|
| id | int PK (autoIncrement) | |
| code | text, **unique**, len 1–32 | e.g. `A-01` |
| tenant_name | text, len 1–120 | current occupant |
| business_type | text, default `''` | e.g. "Grocery" |
| monthly_rent | int (NPR) | current rent |
| phone | text, nullable | |
| notes | text, nullable | |
| is_active | bool, default true | inactive = vacant, excluded from "expected" |
| created_at | datetime, default now | |

`code` is a real DB **unique constraint** — no app-side pre-check needed.

### `Payments` table (`@DataClassName('Payment')`)
| column | type | notes |
|---|---|---|
| id | int PK (autoIncrement) | |
| unit_id | int, **FK → Units(id) ON DELETE CASCADE** | |
| year | int | BS year |
| month | int | 1–12 |
| amount | int (NPR) | captured per record at mark time |
| paid_on | datetime, nullable | render the BS label |
| method | text enum | `cash` \| `bank` \| `wallet` \| `other` (default `cash`) |
| note | text, nullable | |
| created_at | datetime, default now | |

**Constraint:** unique `(unit_id, year, month)` (`uniqueKeys`). There is **no `status` column** — a row's *presence* means paid; its *absence* means pending.

**Cascade:** the FK's `ON DELETE CASCADE` is enforced by `PRAGMA foreign_keys = ON` in the drift migration `beforeOpen` (SQLite requires this per-connection).

> Modeling choice (unchanged): only "paid" records are stored. A unit is **pending** for a month if no row exists. Writes stay trivial — insert to pay, delete to undo — and no month needs backfilling for every unit.

**Future:** a `tenancies` table (unit_id, tenant_name, rent, start/end) for tenant turnover history. Out of scope for v1 — the unit row holds the current tenant inline.

---

## 4. Business logic

- **Expected (month):** sum of `monthly_rent` over active shutters.
- **Collected (month):** sum of `amount` over the month's payment rows (`WHERE year = Y AND month = M`).
- **Pending:** expected − collected.
- **Paid count:** number of active units that have a payment row that month.
- **Mark paid:** insert a payment row `(unit_id, year, month)` with `amount = unit.monthly_rent`, `paid_on = today`, `method = cash` (editable after).
- **Undo:** delete the payment row for `(unit_id, year, month)`.
- **Month navigation:** BS month index wraps; rolling below Baishakh decrements the year, above Chaitra increments it.
- **List sort:** pending shutters first, then paid.
- Changing a shutter's `monthly_rent` must **not** alter already-recorded payment amounts (amount is captured per record).

BS month labels (index → label):
`1 Baishakh, 2 Jestha, 3 Ashadh, 4 Shrawan, 5 Bhadra, 6 Ashwin, 7 Kartik, 8 Mangsir, 9 Poush, 10 Magh, 11 Falgun, 12 Chaitra`.

---

## 5. Data access (repository over Drift)

No server, no REST, no cloud — the app talks to the local Drift DB through a single repository (`LedgerRepository`, `lib/data/ledger_repository.dart`) so the business logic (§4) is unit-testable against an in-memory DB (`AppDatabase.forTesting`). There is no auth gate on the data layer itself; access is controlled by the device/app (or browser origin) sandbox plus the PIN UI lock.

| operation | implementation |
|---|---|
| unlock / lock | local PIN (PBKDF2) via `AuthProvider` — gates the UI, not the queries |
| list units | `SELECT … FROM units ORDER BY code` |
| create / update unit | drift insert / update |
| delete unit | drift delete (payments cascade via the FK) |
| payments for a month | `SELECT … FROM payments WHERE year = ? AND month = ?` |
| mark paid | insert a payment row `(unit_id, year, month, amount, paid_on, method)` |
| undo | delete the payment row for `(unit_id, year, month)` |
| unit history | `SELECT … FROM payments WHERE unit_id = ? ORDER BY year DESC, month DESC LIMIT N` |
| month summary | aggregate in the repository → `{ expected, collected, pending, paidCount }` |
| CSV export | build from the month query; share the file via `share_plus` |

### 5.1 Storage backends

Mobile/desktop open a plain `NativeDatabase` file in `lib/data/connection/native.dart`; web uses drift's WASM database (OPFS/IndexedDB) in `connection/web.dart`. Neither is encrypted at rest — see §2.

---

## 6. Design tokens (brand)

Carry over verbatim from the prototype. Glassmorphic, navy + orange brand.

```css
:root{
  /* brand */
  --brand-orange:#ff6600;
  --brand-orange-soft:#ff9a52;
  --brand-navy:#274074;

  /* surface / text */
  --text:#F5F6FF;
  --muted:rgba(226,230,255,.82);

  /* state */
  --paid:#34d399;            /* green — paid/success */
  --paid-text:#4ee0a8;

  /* glass */
  --glass-bg:rgba(24,36,68,.55);
  --glass-border:rgba(255,255,255,.16);
  --glass-blur:20px;
}
```

- **Background:** navy gradient `#22365f → #192a4f → #0e1830` with soft blurred orbs (orange + navy). Glass panels use `--glass-bg` + `backdrop-filter: blur(var(--glass-blur)) saturate(150%)` + `--glass-border` + inner top highlight.
- **Action color = orange.** Primary buttons (FAB, "Collect" CTA), progress bar fill, active filter chip, the collected-% indicator.
- **"Mark paid" list pill = dimmed translucent orange** (`rgba(255,102,0,.2)` bg, `--brand-orange-soft` text) — softer than the solid orange CTAs.
- **Paid state = green** (`--paid`) so paid vs unpaid is readable at a glance, distinct from the orange action color.
- **Fonts:** Fraunces (display: big numbers, headings, shutter codes), Hanken Grotesk (UI/body). Use `font-variant-numeric: tabular-nums` for money.
- Keep text contrast high (dark glass tint behind light text — do not lighten the glass).
- **Currency:** `Rs ` + `Number.toLocaleString("en-IN")`.

---

## 7. Screens

1. **Home / month ledger** (single primary screen):
   - Header: app name + BS month switcher (`‹ Jestha 2082 ›`).
   - Summary glass card: collected (big), of expected, progress bar, paid count + pending total.
   - Search field + filter chips (All / Pending / Paid).
   - Shutter list rows: code avatar, tenant + business, rent, status pill / "Mark paid". Tap row → detail sheet.
   - Floating **+** to add a shutter.
2. **Shutter detail sheet** (bottom sheet): tenant, rent, contact; big Collect/Undo button for the selected month; edit + delete; 6-month history strip.
3. **Add / edit shutter sheet:** code, tenant, business, rent, phone.
4. **Login** screen.
5. (Optional) **Reports** view: monthly summary + outstanding list + CSV export.

---

## 8. Acceptance criteria

- Owner sets a PIN on first run and must unlock to reach the ledger.
- Adding a shutter/unit makes it appear in the current month as pending and increases "expected".
- Marking paid moves it to paid, updates collected/pending/% live, and persists across reload.
- Undo removes the payment and reverts the totals.
- Switching months shows independent paid/unpaid state per month.
- Editing a shutter's rent does not change past recorded amounts.
- Deleting a shutter removes it and its payment history.
- Money never renders as a float; grouping is `Rs 1,80,000` style.
- UI matches the prototype's glass + navy/orange brand and stays legible.

---

## 9. Deliverables

- Flutter app (iOS / Android / macOS / web) implementing the UI + repository above.
- Drift schema (`Units`, `Payments`) + generated code; `LedgerRepository` holding the §4 logic.
- Web assets (`web/sqlite3.wasm`, `web/drift_worker.js`) for the WASM backend.
- Tests (`test/`): money formatting, BS month navigation, and repository logic.
- README: local dev (`flutter run`) and per-platform build notes.
