# Rent Bee bug log

A running record of defects found and fixed, so you can see later what changed and why.
Newest work is at the top of each section. Each entry says what went wrong, why, what
was changed, and how it is tested.

**Status key:** ✅ fixed · 🔧 in progress · ⏳ queued · ⏸ deferred (needs a decision or a backend change) · ℹ️ noted, not a code fix

**How entries are verified:** unless an entry says otherwise, "fixed" means the change has a
test that fails without it and the full suite plus `flutter analyze` pass with it.

---

## Review of 2 Oct 2026 — queue

Found by a full-project review (data and sync, app state and lifecycle, UI). Worked one at a
time in this order: money and data loss first, then wrong-result bugs, then security, then
speed, then polish.

**Result (2 Oct 2026):** 37 of 38 items fixed, 1 deferred (B14, needs a backend decision).
The suite stands at 299 passing tests (27 skipped: screenshot and preview renders);
`flutter analyze` reports no errors or warnings. Database schema is now version 7 (v6 adds the sync outbox table, v7 one nullable
column on payments); both upgrades are additive.

**Things to know after this round:**

- Bumping the app version: change `version:` in `pubspec.yaml` **and** `appVersion` in
  `lib/app/version.dart` (a test fails if they differ).
- PINs saved by older builds keep working and are converted on the next unlock.
- Five wrong PINs now start a timeout; "Forgot PIN?" on the lock screen resets it by SMS.
- Restore, Erase and Generate demo data each need a typed word (RESTORE / ERASE / REPLACE).
- Rents already over-raised by B01 on a phone abroad are not corrected automatically.

### Money and data loss

| ID | Status | Issue |
|---|---|---|
| B01 | ✅ | Rent compounds on every launch outside Nepal's time zone |
| B02 | ✅ | Automatic rent raises are reverted on synced accounts |
| B03 | ✅ | Sync start deletes local changes that were never pushed |
| B04 | ✅ | "Back up to cloud now" and Restore can wipe the local ledger |
| B05 | ✅ | Past months re-priced from today's rent (phantom debt) |
| B06 | ✅ | "Pending" understated when a vacated or overpaying unit has paid |
| B12 | ✅ | Unit-code collision between devices is skipped silently |

### Wrong result or broken flow

| ID | Status | Issue |
|---|---|---|
| B07 | ✅ | Reports "Outstanding" row opens the sheet for the Ledger's month |
| B08 | ✅ | Double-tap on "Mark paid" marks the next tenant |
| B10 | ✅ | Database failure shows an endless spinner instead of the error screen |
| B11 | ✅ | New-install AD calendar default flips to BS on the second launch |
| B13 | ✅ | Restore confirms before the file is chosen; an empty backup wipes everything |
| B15 | ✅ | Reminder SMS quotes the full due on a partial payment, and the BS month to AD users |
| B16 | ✅ | Alert content cannot scroll, so its buttons clip with the keyboard up |
| B17 | ✅ | CSV import is not atomic |
| B19 | ✅ | Search box and the filtered list disagree after lock/unlock |
| B20 | ✅ | Change PIN and Save can double-submit |
| B21 | ✅ | Phone field moves the cursor to the end on every edit |
| B22 | ✅ | Reports keeps the old escalation rate after it changes |
| B23 | ✅ | Stale static text ("v1.0.0 · offline") |
| B24 | ✅ | Sync listeners: no error handling, no ordering, one bad document stops sync |
| B25 | ✅ | Signing out while sync is starting leaves orphaned listeners |
| B26 | ✅ | Settings changed while sync is starting are reverted by the cloud |
| B28 | ✅ | Upgrade from a very old database (schema v2) fails |

### Security

| ID | Status | Issue |
|---|---|---|
| B09 | ✅ | PIN has no attempt limit and no "forgot PIN" path |
| B29 | ✅ | A failed Firebase start is cached for the life of the app |
| B30 | ✅ | PIN material is written as three separate values |
| B14 | ⏸ | OTP daily counter is writable without signing in (needs a backend change) |

### Speed

| ID | Status | Item |
|---|---|---|
| S1 | ✅ | Sync start applies every cloud document twice, one at a time |
| S2 | ✅ | Each local change triggers up to three full refreshes |
| S3 | ✅ | Seven backdrop blurs over the flat page colour |
| S4 | ✅ | Reports recomputes while its tab is hidden |
| S5 | ✅ | PIN check: 100,000 hash rounds in pure Dart on every unlock |
| S6 | ✅ | Whole-screen rebuilds on every Ledger notification; themes rebuilt on any setting |

### Polish and accessibility

| ID | Status | Issue |
|---|---|---|
| B18 | ✅ | Layouts that break at large text sizes |
| B31 | ✅ | Low contrast for body text on light alerts |
| B32 | ✅ | Small items: undisposed controllers, hit areas under 44 pt, missing labels |
| B35 | ✅ | CSV import hides encoding problems |

---

## Entries

### B01 ✅ Rent compounded on every launch outside Nepal's time zone

- **Seen as:** a unit's rent rising by the escalation rate each time the app opened. Reproduced: in UTC+8, US Eastern and Sydney, four launches on one day took 10,000 → 10,500 → 11,025 → 11,576 → 12,155. Nepal and UTC were unaffected.
- **Cause:** after a raise the unit is stamped "last raised: 1st of the anniversary month". Reading that stamp back used the calendar library's Gregorian→BS conversion, which goes through "UTC + 5:45" and then truncates a local-time day count. East of Nepal, or in any daylight-saving zone, the 1st reads back as the last day of the *previous* month, so the app thought the anniversary had not been applied yet.
- **Fix:**
  - `lib/domain/bs_calendar.dart`: new `bsDate()` converts a calendar date to BS by pure arithmetic (derived from the reliable BS→Gregorian direction), identical on every device. `bsYearMonth()` and `dateLabel()` use it. Dates outside the supported range clamp instead of throwing.
  - Raises are now stamped **mid-month at noon** (`raiseStampFor`) and read tolerantly (`bsMonthOfRaiseStamp`), so a stamp synced to a phone in another time zone still names the same month. Old-style stamps are understood too.
- **Tests:** `test/bs_calendar_test.dart`, `test/anniversary_raise_test.dart`. Run in Kathmandu, Singapore, New York, Los Angeles and Auckland time: all pass.
- **Not repaired automatically:** rents already over-raised on a device abroad stay as they are; correct them by editing the unit.
- **Known limit:** a unit's *start date* is still stored as an instant. If the start date is the first or last day of a BS month, a device many time zones away can read it as the neighbouring month. Rare; a full fix means storing dates as text.

### B11 ✅ New-install AD calendar default flipped to BS on the second launch

- **Seen as:** a fresh install shows Gregorian dates, then Bikram Sambat from the next launch.
- **Cause:** the default is worked out from "has this device set a PIN before?". That is false on first launch and true ever after, and the chosen default was never saved.
- **Fix:** `lib/state/settings_provider.dart` saves the resolved default the first time it is computed.
- **Tests:** `test/settings_provider_test.dart` ("the fresh-install AD default survives the second launch").

### B02 ✅ Automatic rent raises were reverted on synced accounts

- **Seen as:** a unit past its anniversary still showing (and collecting) last year's rent on an account with cloud sync.
- **Cause:** the startup raise runs before sync is attached, so it was never pushed. The sync pull that follows then overwrote the unit with the cloud's old rent. This repeated every launch.
- **Fix:** `lib/main.dart` re-applies due raises once sync has started, when they are pushed and stick.
- **Tests:** `test/firestore_sync_test.dart` ("an anniversary raise applied after reconcile is pushed and sticks").

### B03 ✅ Sync start deleted local changes that were never pushed

- **Seen as:** a payment marked right after unlocking flips back to "pending" seconds later; or a whole session's work disappears on the next launch.
- **Cause:** sync start treated "a local row the cloud doesn't have" as "deleted on another device" and removed it, and overwrote local rows with the cloud's copy. Nothing recorded whether a local change had actually reached the cloud. Changes made before sync finished starting (it takes a few seconds), in a session where sync couldn't start, or whose push failed, were therefore destroyed.
- **Fix — a local outbox.** New table `pending_pushes` (database schema v6). Every local change records its key there before the push is fired; the key is removed only when the cloud acknowledges it. Sync start now pushes the outbox first, and no pull or listener overwrites or deletes a row whose key is still pending. A push sends the *current* local row, so repeating one is harmless.
  - `lib/data/database.dart` (table, migration), `lib/data/sync_types.dart` (new), `lib/data/ledger_repository.dart` (`_queue`, `applyRemote`), `lib/data/firestore_sync_service.dart` (rewritten).
  - A cache-only read (offline) is applied as updates only: it never deletes, and it doesn't count as the "first sync".
- **Tests:** `test/sync_outbox_test.dart`, group "changes made while sync is not attached": payment, new unit, edit, undo, unit delete and an offline restore all survive and reach the cloud.

### B04 ✅ "Back up to cloud now" and Restore could wipe the local ledger

- **Seen as:** units disappearing after tapping "Back up to cloud now"; if the phone was offline, or the rewrite failed, they did not come back.
- **Cause:** the cloud copy was replaced by *erase everything, then write everything*. This device's own listeners saw its units "removed" and deleted them locally (with their payments). The rewrite then had to put it all back.
- **Fix:** replace is now *write every local row, then delete only cloud documents that have no local counterpart*. The only deletions are of things already absent locally, so their echo has nothing to remove. Same path for restore, demo data and erase-all, and it goes through the outbox, so it still happens if sync isn't attached at that moment.
- **Tests:** `test/sync_outbox_test.dart`, group "whole-ledger replaces": re-sync with live listeners keeps the same rows and ids; stale cloud documents are removed; erase empties the cloud.

### B12 ✅ The same unit code on two devices was dropped silently

- **Seen as:** two phones each add "A-05"; each shows only its own unit, money recorded on one never appears on the other, and both say "synced".
- **Cause:** the incoming unit violated the unique-code rule; the error was caught and the unit skipped.
- **Fix:** both units are kept. The one with the larger internal id gets a suffix (`A-05-2`); every device makes the same choice, so they converge. The rename is pushed.
- **Tests:** `test/sync_outbox_test.dart` ("the same unit code created on two devices keeps both units").

### B24 ✅ Sync listeners: no ordering, no error handling, one bad document stopped everything

- **Cause:** listener callbacks were async and un-awaited, so two could interleave; a document with a missing or wrong-typed field threw and aborted the whole pull, on every launch; a dead listener (permission denied) left the badge saying "synced".
- **Fix:** listener batches run strictly one after another; each document is parsed defensively and a malformed one is skipped and logged; listener errors set the sync status to error.
- **Tests:** `test/sync_outbox_test.dart` ("one malformed cloud document does not stop the rest").

### B25 ✅ Signing out while sync was starting left orphaned listeners

- **Fix:** `lib/data/sync_bootstrap.dart` checks after each slow step that the session is still the live one, and a detached service refuses to attach listeners.
- **Tests:** `test/sync_outbox_test.dart` ("signing out mid-start: a detached service attaches nothing").

### B26 ✅ Settings changed while sync was starting were reverted by the cloud

- **Cause:** the "push my settings" hook was only connected after sync had finished starting, and the cloud's values were then applied unconditionally.
- **Fix:** the hook is connected once at app start. Sync start now settles settings *before* attaching its listeners, and if the owner changed a setting during start-up, that newer choice wins and is pushed (`SettingsProvider.localRevision`).
- **Tests:** covered by the existing settings round-trip tests; the start-up ordering itself is not unit-tested.

### B28 ✅ Upgrading a very old database (schema v2) failed

- **Cause:** the v3 step creates the charges table with today's columns; the v5 step then tried to add the `deduction` column again ("duplicate column name") and the app never opened. Only databases older than the first store build were affected.
- **Fix:** the v5 step only runs for databases that already had a charges table.
- **Tests:** `test/sync_outbox_test.dart` ("a v2 database … upgrades cleanly"), which also exercises the v4 and v6 steps.

### S1 ✅ Sync start applied every cloud document twice, one at a time

- **Was:** each document cost a lookup plus a write as separate round trips to the database thread, each write its own committed transaction; the two child collections were then downloaded a second time just for their ids; and the listeners' first snapshots replayed every document again. For 20 units over three years that is roughly 5,800 database round trips and three downloads of each collection, on every launch.
- **Now:** each collection is read once, in parallel. Differences are worked out in memory and written in a single transaction; rows that already match are skipped. A normal launch with nothing new performs about six database round trips and writes nothing. The listeners' first snapshots go through the same diff and also write nothing.
- **Also:** SQLite now runs in WAL mode with `synchronous = NORMAL` (`lib/data/connection/native.dart`), so a commit no longer pays a full disk sync.
- **Not measured on a device;** the counts above are from the code.

### S2 ✅ Each local change triggered up to three full refreshes

- **Was:** the app refreshed after its own write, then again when the write echoed back through the listener, then again when the server acknowledged it.
- **Now:** a listener batch refreshes the screen only if it actually changed a local row. The device's own writes come back identical and change nothing.
- **Tests:** `test/sync_outbox_test.dart` ("a local change does not refresh the UI again through its own echo").

### B05 ✅ Past months were re-priced from today's rent (phantom debt)

- **Seen as:** after editing a unit's rent from 10,000 to 12,000, earlier months that were paid in full at 10,000 show "partial, 2,000 left", and the year report lists the tenant as owing. Changing or switching off the escalation rate did the same to pre-raise months. Separately, the Ledger priced every past month at today's rent while Reports used the rent in effect then, so the two screens disagreed.
- **Cause:** no record of what a month actually cost. Past rent was reconstructed by unwinding raises from the current rent using the *current* rate, and the Ledger didn't even do that.
- **Fix:**
  - Each payment now stores the rent it was made against (`payments.rent_at_payment`, database schema v7; synced and included in backups).
  - One rule prices a month everywhere (`LedgerRepository._monthRent`): the rent recorded on its payment if there is one, otherwise the rent in effect that month. The Ledger rows, month summary, unit history strip, Reports and CSV status all use it.
  - A month before the tenant moved in owes nothing and offers nothing to collect ("Not rented yet this month").
  - Changing the escalation rate re-prices the month on screen straight away.
- **Limit:** payments recorded before this change carry no rent, so they still fall back to the reconstructed rent. Only payments made from now on are pinned.
- **Tests:** `test/month_pricing_test.dart`.

### B06 ✅ "Pending" was understated

- **Seen as:** one tenant owes 10,000, another tenant paid 10,000 and was then marked vacant: the summary shows nothing pending and 100% collected. An overpayment by one tenant hid another's debt the same way.
- **Cause:** pending was computed as expected minus collected, and "collected" includes money from vacated units and overpayments that "expected" does not.
- **Fix:** pending is now the sum of each active unit's own shortfall, on the month summary, each month of a report, and the period total.
- **Tests:** `test/month_pricing_test.dart`, group "pending is what is actually still owed".

### B07 ✅ Reports "Outstanding" row opened the sheet for the Ledger's month

- **Seen as:** Home is on Ashwin, Reports is stepped back to Bhadra and shows a unit owing. Tapping the row opens a sheet saying "Collect … for Ashwin"; collecting records Ashwin and the Bhadra debt stays.
- **Cause:** the unit sheet always works on the Ledger's selected month; Reports opened it without changing that.
- **Fix:** each debt now carries the months it covers (`PeriodDebt.unpaidMonths`). Tapping a row first moves the Ledger to that unit's oldest unpaid month (`LedgerProvider.goToMonth`), then opens the sheet.
- **Note:** this changes the month shown on the Ledger tab too, which is visible in its title.
- **Tests:** `test/month_pricing_test.dart`, group "acting on a debt from Reports".

### B15 ✅ Reminder SMS quoted the wrong amount and the wrong calendar

- **Seen as:** a tenant who paid 10,000 of 15,000 is reminded that "rent of Rs 15,000 is due". Owners using Gregorian dates text tenants "rent for Ashwin 2083". From a year report with one unpaid month, the text named the report's anchor month.
- **Fix:** a part-paid month reminds for the remainder; the month is named in the owner's calendar; a single unpaid month is named exactly. The amount and charges dialogs use the owner's calendar too.
- **Tests:** `test/sms_reminder_test.dart`, group "calendar the owner reads dates in".

### B13 ✅ Restore replaced everything behind a one-tap confirm, before the file was even chosen

- **Seen as:** "Restore from backup" asked "Replace all data?" first, then opened the file picker. Whatever file was picked next replaced the whole ledger — and, with sync on, every other device's — with no look at what the file held. An old or empty backup wiped current data.
- **Fix:** the file is chosen and read first (`LedgerRepository.inspectBackup`). The confirmation then states what the file contains (units, payments, charges, export date) against what will be replaced, says so when other devices are affected, and requires typing `RESTORE`. A backup with no units is refused. The file must be valid UTF-8 (a damaged file is rejected instead of restored with garbled names).
- **Also fixed:** the backup's currency was dropped if the app auto-locked while the picker was open (the screen was gone when the restore finished). It is applied regardless now.
- **Tests:** `test/backup_test.dart`, group "inspectBackup".

### B16 ✅ A long alert pushed its own buttons off the screen
### B31 ✅ Alert text was low-contrast on glass

- **Seen as:** on a small phone, or with the keyboard up (the typed ERASE / REPLACE / RESTORE confirmations), the alert overflowed and Cancel / Confirm were clipped or unreachable. Body text was secondary grey on translucent glass, hard to read over a busy page.
- **Fix:** the alert's content now shrinks and scrolls; the action row always stays visible above the keyboard. Alerts use a near-opaque glass (`Glass(strong: true)`) and body text in the primary label colour.
- **Tests:** `test/dialog_layout_test.dart`.

### B19 ✅ After auto-lock the list stayed filtered but the search box was empty

- **Seen as:** search for a tenant, let the app lock, unlock: the Ledger shows one unit (or "no units") and the search box is blank, so the rest of the units look lost.
- **Cause:** the query lives in the provider (survives the lock); the text field is rebuilt empty.
- **Fix:** the search box is seeded from the provider's query.
- **Tests:** `test/app_integration_test.dart`, "the search box still shows the query after a lock" (fails without the fix).

### B08 ✅ Double-tapping "Mark paid" marked the next tenant paid too

- **Seen as:** tap Mark paid on the first pending unit. The list is sorted pending-first, so that row drops away and the next tenant slides into the same spot — a second tap (or a double-tap) records a payment for them.
- **Fix:** changes made in place (mark paid, undo, edit payment, charges, deduction, deposit, and changes arriving from another device) keep every row where it is. With the Pending or Paid filter on, the changed row also stays listed until the filter changes. The list re-sorts on the next real load: month switch or pull to refresh.
- **Tests:** `test/stable_rows_test.dart`.

### B10 ✅ A database failure showed an endless spinner

- **Seen as:** if the database cannot open or migrate, the Ledger tab spins forever with no message.
- **Fix:** a failed load is caught and shown as a "Could not load your ledger" card with the reason and a Try again button. A failure in the startup rent-raise catch-up no longer blocks the first load.
- **Tests:** `test/stable_rows_test.dart` ("a failed load reports the error…"), `test/app_integration_test.dart` ("a ledger that cannot load says so…").

### B17 ✅ A CSV import that failed part-way left half the file merged in
### B35 ✅ CSV import hid encoding problems

- **Seen as:** an import that hit a bad row (or ran out of storage) stopped with "Import failed", but every row before it was already written and pushed to the other devices: renamed tenants, changed rents and some payments, with no way to tell which. Separately, a CSV saved by Excel as plain "CSV" (Windows-1252) imported with tenant names full of "�" marks.
- **Fix:** the whole import is one transaction (`LedgerRepository._atomically`). Its changes are recorded for sync in that same transaction and sent to the cloud only after it commits, so a failed import changes nothing here or anywhere else. The file must be UTF-8; otherwise nothing is imported and the message says to save as "CSV UTF-8".
- **Tests:** `test/csv_import_atomic_test.dart` (fails without the fix).

### B20 ✅ A double tap on Save / Add Unit submitted twice

- **Seen as:** tapping "Add Unit" twice quickly ran the save twice: the second attempt failed on the duplicate unit code and showed "Could not save — code may already exist" for a unit that had in fact been added. Change PIN could likewise run twice while the PIN hash was being derived.
- **Fix:** both are guarded while a save is in flight; the unit form's button shows a busy indicator.
- **Tests:** `test/app_integration_test.dart`, "a double tap on Add Unit saves once, with no error".

### B21 ✅ Editing a phone number threw the cursor to the end

- **Seen as:** correcting one digit in the middle of a tenant's phone number moved the caret to the end after every keystroke, so the next digit landed in the wrong place.
- **Fix:** the clean-up formatter (`lib/ui/util/phone_input_formatter.dart`) now keeps the caret after the same characters it followed.
- **Tests:** `test/phone_input_formatter_test.dart`.

### B22 ✅ Changing the escalation rate did not re-price the month on screen

- **Seen as:** after changing the Annual Lease Escalation Rate (or receiving a change from another device), past months on the Ledger kept the old rents until the month was switched or the app restarted. Reports and the unit history were already correct.
- **Cause:** the refresh added for this earlier in the session never ran. It compared the rate against a "last seen" value that was first read only after the change, so the two always matched.
- **Fix:** the last-seen rate is captured at startup, before listening for changes.
- **Tests:** `test/app_integration_test.dart`, "changing the escalation rate re-prices the month on screen" (this test is what exposed the bug).

### B23 ✅ Settings showed "v1.0.0 · offline" on every release

- **Fix:** the label reads `appVersion` (`lib/app/version.dart`), and the line below says the data is also synced to the account when sync is on.
- **Note:** when bumping `version:` in `pubspec.yaml`, bump `lib/app/version.dart` too. A test fails if they differ.
- **Tests:** `test/version_test.dart`.

### B09 ✅ The PIN could be guessed without limit, and a forgotten PIN had no way back

- **Seen as:** the lock screen accepted wrong PINs forever (a 4-digit PIN has 10,000 values). And an owner who forgot the PIN was locked out for good: the only reset was Sign out, which is inside the app.
- **Fix, attempt limit:** five wrong PINs are free (the last two warn "2 tries left", "1 try left"). Each miss after that locks the screen for 30 s, 1 min, 5 min, 15 min, then 1 hour, shown as a countdown. The count and the timeout are saved, so quitting the app does not reset them; setting the clock back cannot extend one. While locked, nothing is checked, not even the right PIN. Change PIN in Settings uses the same counter.
- **Fix, forgot PIN:** "Forgot PIN?" on the lock screen sends an SMS code to the number the device was set up with. Only that number can clear the PIN (the field is fixed, and a different verified number is refused), so someone holding the phone cannot swap in their own number. After verification the owner sets a new PIN; the ledger is untouched. "Back to PIN" cancels with nothing changed.
- **Known limit:** the code is sent to the same phone. If the SIM is in a stolen, unlocked phone, the thief can read it. The PIN protects against casual access, not against someone who also controls the SIM; the phone's own screen lock is the real barrier.
- **Tests:** `test/pin_security_test.dart`, groups "attempt limit", "forgot PIN", "lock screen countdown".

### B30 ✅ PIN salt, hash and rounds were three separate writes

- **Seen as (rare):** if the app was killed between those writes while setting or changing a PIN, the stored salt and hash no longer belonged together and no PIN could unlock the app.
- **Fix:** the three values are one stored record, replaced in a single write. PINs saved by older builds are read as before and converted after the next successful unlock.
- **Tests:** `test/pin_security_test.dart`, group "PIN storage".

### S5 ✅ Every unlock ran 100,000 hash rounds in pure Dart

- **Seen as:** a pause between entering the PIN and the app opening, longest on slow Android phones.
- **Change:** 20,000 rounds, about five times faster. Existing PINs are re-hashed in the background after their next unlock.
- **Why this is not a security loss:** with only 10,000 possible PINs, no round count makes a copied hash slow to search, and the ledger file itself is not encrypted. What stops guessing is the attempt limit above. To change it back, edit `_iterations` in `lib/state/auth_provider.dart`; existing PINs follow automatically.
- **Tests:** `test/pin_security_test.dart` ("a PIN from an older build…", "the real derivation…").

### B29 ✅ One failed Firebase start disabled sync and verification until the app was force-quit

- **Seen as:** open the app with no network: cloud sync does not start, and stays off after the network returns. The same for phone verification.
- **Cause:** the failed start-up was remembered and returned to every later caller.
- **Fix:** only a successful start is remembered; a failed one is retried on the next attempt (`RetryableOnce` in `lib/data/phone_auth_service.dart`).
- **Tests:** `test/pin_security_test.dart`, group "Firebase start".

### S3 ✅ Seven backdrop blurs over a flat background

- **What it cost:** the month arrows, the add buttons and the Reports scope switch are glass, and each ran a backdrop blur, an offscreen layer redrawn on every frame of every scroll. They sit on the flat page colour, where a blur changes nothing you can see.
- **Change:** `Glass` has a `blur` flag. In-page controls pass `false`; alerts (now near-opaque) skip it too. Only glass with content moving behind it keeps the blur: the tab bar and toasts. Each tab now has one blur instead of up to four.
- **Tests:** `test/app_integration_test.dart`, "only glass that floats over content is blurred".

### S4 ✅ Reports recomputed while its tab was hidden

- **What it cost:** Reports listened to every Ledger notification. Each search keystroke, filter tap and payment on the Ledger tab re-ran the multi-month report queries in the background, for a screen nobody was looking at.
- **Change:** a hidden Reports tab is only marked stale and reloads once when shown. Notifications that do not change data (search text, filter, currency, appearance) are ignored even while it is visible (`LedgerProvider.dataRevision`).
- **Tests:** `test/app_integration_test.dart`, "Reports is not recomputed while hidden, nor for a keystroke".

### S6 ✅ Whole screens rebuilt on every Ledger notification; themes rebuilt on any setting

- **What it cost:** Settings and the Units directory rebuilt completely on every Ledger notification, including each search keystroke, even while off-screen. Any settings change built two fresh themes for the whole app.
- **Change:** Settings follows only the three ledger facts it shows (unit count, month, sync on/off). Units rebuilds per data load. The search bar follows only the query and filter. The month summary compares by value, so its card rebuilds only when a figure changes. The light and dark themes are built once.
- **Tests:** `test/app_integration_test.dart`, "a keystroke in search rebuilds the list, not the other tabs" (fails with the old subscription); `test/month_pricing_test.dart`, "month summaries compare by value".

### B18 ✅ Layouts broke at large text sizes

- **Seen as:** with the phone's text size raised (Settings → Display → Larger Text, or the accessibility sizes), the Ledger header ran off the right edge, unit rows overflowed or squeezed the tenant's name to a few letters, the tab bar labels spilled out of the bar, the four Reports cards clipped their figures, and several amount rows in Reports and the unit sheet overflowed. A row with both charges and a deduction squeezed the name even at the default size.
- **Fix:**
  - Unit rows (Ledger and Units) keep name and amount side by side at ordinary sizes, with the amount block limited to half the row; at the accessibility sizes the amount and actions move under the name (`SplitRow`).
  - Trailing amounts everywhere take what they need up to a share of the width, then scale down; a figure is never wrapped or cut (`TrailingValue`, also used by every `ListRow`).
  - Fixed-height chrome stops growing at 1.3×, as iOS bars do: the tab bar, toolbar buttons, the sponsor strip and the six-month history strip (`TextSize.capped`).
  - The Ledger subhead wraps the date chip onto its own line; the Reports summary cards size to their text; the Deposit liability title and total stack at large sizes.
- **Tests:** `test/large_text_test.dart` walks every screen, the unit sheet, the add-unit form and the Erase alert at 1.35× and 2× text on a small phone, and fails on any overflow. The test font is wider than a real one, so it is stricter than a device.

### B32 ✅ Small items

- **Change PIN leaked its text controllers.** The dialog is now a widget that owns and disposes them (and keeps the double-tap guard from B20).
- **The unit sheet's code tile was always green**, as if the month were paid. It is green only once the month is settled.
- **Screen readers heard nothing useful** on the six-month history strip (colour and shape only) or on the icon-only reminder and clear-search buttons. Each history month now reads as "Ashwin 2083, paid / part paid / not paid"; the buttons are labelled "Send reminder" and "Clear search".
- **The contact-picker button in the unit form** had a 40 pt hit area; it is 44 pt now.
- **Tests:** `test/app_integration_test.dart`, the two tests marked (B32).

### B14 ⏸ Anyone can use up the day's sign-in codes (not fixed; needs a backend change)

- **What it is:** sign-in SMS codes are limited to 10 per 24 hours for all users together, counted in one shared Firestore document. A person reserves a slot before they are signed in, so that document has to accept writes from anyone. The security rules stop the count from being lowered or the limit exceeded, but they cannot stop someone from pushing the counter to 10 without ever requesting a code. For the next 24 hours no new device can verify, and no owner can use "Forgot PIN?".
- **Who is affected:** new sign-ins and PIN resets only. Owners already signed in keep working, offline or synced.
- **Why it is not fixed here:** it cannot be closed from the app. The options are: (1) enforce App Check on Firestore so only the genuine app can write the counter, which is a console setting plus a check that every shipped build attests correctly; (2) move the reservation into a Cloud Function, which needs the paid Blaze plan; (3) drop the shared counter and rely on Firebase's own per-number and per-device SMS limits plus a billing cap.
- **Recommendation:** option 1. App Check is already activated in the app (`PhoneAuthService`), so it is the smallest step. Tell me when you want it and I will write the rule change and the rollout check.

---

## Earlier fixes this session (before the queue)

| When | What was fixed |
|---|---|
| 2 Oct | **Sheets could trap the user.** Every bottom sheet now has a pinned close button, swipe-down works on scrollable content, the sheet never reaches the status bar, and the keyboard can be dropped by dragging or tapping empty space. Pull-to-dismiss only fires when the drag starts at the top, so scrolling back up never discards a half-filled form. |
| 2 Oct | **A save or delete still in flight could close the screen underneath** when the sheet was dismissed first. The pop is now skipped unless that sheet is still the current route. |
| 2 Oct | **Charges and history in an open unit sheet did not refresh in debug builds** (`setState` was handed a closure returning a Future). |
| 2 Oct | **"Generate demo data" could replace a real ledger.** It is now offered only to the store-review test login and the debug guest session, and requires typing REPLACE whenever there is data or cloud sync is live. |
| 22 Sep | **"Erase all data" was one tap.** It now requires typing ERASE. |
| Earlier | Deduction review fixes: negative-rent crash in `netDue`, a pre-deduction app build zeroing a synced deduction, CSV round-trip losing deductions, "paid" shown for months before a tenant started, a phantom Rs 0 payment from Collect, "rent of Rs 0" in the SMS. |
