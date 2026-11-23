# Known defects: status

Each row is a finding of the audit with a test that states the CORRECT behaviour and is skipped until its work package fixes it (`skip: knownDefect(id, package)`, see `known_defect.dart`). To run them all: `flutter test --dart-define=RUN_KNOWN_DEFECTS=true test/known_defects`.

`fails-when-enabled` records whether the test FAILS when run enabled, i.e. whether it detects the defect today. `registry_test.dart` requires every skipped id to be listed here and no row to say `no`.

The expectations were written against today's APIs. A fix that changes an API (for example `BudgetService.allowance`) must update the call in the test it un-skips; the asserted behaviour stays.

| id | package | test file | fails-when-enabled | note |
|---|---|---|---|---|
| BUD-01 | 2.2 | p2_2_budgets_test.dart | yes | raising the limit on Dec 10 rewrites November allowance to 15,000 (expects 10,000) |
| BUD-02 | 2.2 | p2_2_budgets_test.dart | yes | spentAgainst(parent) is 0, expected 3,000 from the child category |
| F14 | 2.3 | p2_3_recurring_test.dart | yes | auto-booking adds a second entry on the day already entered by hand |
| F82 | 2.3 | p2_3_recurring_test.dart | yes | moving the start to the 1st turns the day 10 into 1 |
| LOG-01 | 2.3 | p2_3_recurring_test.dart | yes | bookDue books 1 entry for a US$ item with no rate |
| LOG-09 | 2.3 | p2_3_recurring_test.dart | yes | after moving a booked entry to Sep 30, pendingDate is Oct 1 (expects null) |
| REC-01 | 2.3 | p2_3_recurring_test.dart | yes | resuming books April-November entries at once |
| ACC-01 | 2.4 | p2_4_accounts_test.dart | yes | a reconciliation adjustment of 2,000 counts as 2,000 of spending |
| ACC-02 | 2.4 | p2_4_accounts_test.dart | yes | 2 tests; bank to card flips +5,000 to -5,000; a US$ account can become a card |
| ACC-03 | 2.4 | p2_4_accounts_test.dart | yes | editing the balance to 9,000 moves the Aug 31 balance from 5,000 to 10,000 |
| DEB-01 | 2.4 | p2_4_accounts_test.dart | yes | archiving a person owed 5,000 succeeds |
| LOG-06 | 2.4 | p2_4_accounts_test.dart | yes | deleting the purchase leaves spending of -1,000 |
| F22 | 2.5 | p2_5_market_test.dart | yes | only the silent-failure part: an unreadable board writes nothing to the diagnostics log; the live parse failure itself is not reproducible offline |
| INV-02 | 2.5 | p2_5_market_test.dart | yes | a dividend due on Nov 28 (a week out) gives an outlook total of 0, expected 1,000 |
| PKG-02 | 2.5 | p2_5_market_test.dart | yes | JPY missing from the second board is dropped from the stored rates |
| ENT-02 | 4.2 | p4_2_forms_test.dart | yes | form keeps the split but build() drops it after switching to a US$ account |
| ENT-03 | 4.2 | p4_2_forms_test.dart | yes | 2 widget tests (back key, scrim tap); sheet closes with no dialog and no draft |
| ENT-05 | 4.2 | p4_2_forms_test.dart | yes | picking a merchant replaces the chosen account (card) with cash |
| ENT-06 | 4.2 | p4_2_forms_test.dart | yes | editing a transfer previews fromAfter 98,000, expected 99,000 |
| DSN-01 | 5.1 | p5_1_design_test.dart | yes | 收入 tab text is 2.21:1 on white (expects 4.5:1) |
| IMP-01 | 6.1 | p6_1_import_test.dart | yes | a positive amount with no type column is imported as income |
| IMP-02 | 6.1 | p6_1_import_test.dart | yes | round trip loses the US$ currency (first of 10 differences) |

22 findings covered.

## fixed in 1.1

Work package 1.1 (one source for amounts). Each test below now runs in the ordinary suite and states the corrected behaviour; the four that were known-defect tests keep their place in `p1_1_amounts_test.dart` without the skip.

- F107: `p1_1_amounts_test.dart` (entry row read as 支出 1,844); `test/design_system/display/amount_text_test.dart`, `test/core/widgets/entry_tile_test.dart`, `test/core/widgets/calculator_test.dart` (keys named)
- IMP-04: `p1_1_amounts_test.dart` (.5 does not abort the import); `test/features/import_export/model/import_export_test.dart` (misreads refused per line)
- F78: `p1_1_amounts_test.dart` (100.35% says 超支); `test/features/budgets/ui/budgets_month_picker_test.dart` (literal expectations)
- ACC-05: `p1_1_amounts_test.dart` (80,000 is 80000; only the amount part); `test/features/accounts/model/account_form_test.dart`
- ENT-04: `test/core/widgets/calculator_test.dart`, `test/core/widgets/amount_keys_test.dart`
- ENT-09: `test/features/entries/ui/entries_filter_sheet_test.dart`
- F06: `test/design_system/display/amount_test.dart`, `test/core/widgets/entry_tile_test.dart`
- F03: `test/features/entries/forms/composer_state_test.dart`
- RPT-06: `test/app/more_page_test.dart`, `test/design_system/display/amount_test.dart` (number part only; dates belong to the next package)
- F34: `test/features/reports/model/report_test.dart`
- INV-03: `test/features/investments/ui/holding_page_test.dart`
- F21: `test/features/accounts/ui/card_page_test.dart`

## fixed in 3.1

Work package 3.1 (one lock gate above every screen). The two tests that were skipped here run unskipped in `p3_1_lock_test.dart` (the loop of wrong passwords in SEC-03 also accepts `UnlockDelayed`, the refusal 3.1 added; its expectation is unchanged). The other findings had no known-defect test; each is stated by the ordinary tests named.

- SEC-05: `p3_1_lock_test.dart`; `test/app/bootstrap_test.dart` (a sheet, a pushed page, a dialog and a note all go, widgets and semantics), `test/core/platform/lock_gate_test.dart` (sessions), `test/core/widgets/lock_cover_test.dart`
- SEC-03: `p3_1_lock_test.dart`; `infrastructure/vault/test/backup_security/attempt_policy_test.dart` (the table), `test/core/platform/unlock_attempts_test.dart` (kept across restarts, clocks set back and forth), `test/core/platform/startup_gate.dart` (run by `startup_test.dart`; passwords and recovery codes), `test/features/lock/ui/lock_screen_test.dart` (the wait counted down, the field off)
- F43: `test/app/bootstrap_test.dart` (a tap on a locked ledger shows only the lock screen, the form opens after unlocking; a tap arriving as the app comes back too late), `test/core/platform/lock_gate_test.dart` (ways in)
- SEC-07: `test/core/platform/lock_gate_test.dart` (each choice, a clock the test moves), `test/core/platform/preferences_test.dart` (the table and its keeping), `test/app/bootstrap_test.dart` (the cover), `test/features/lock/ui/security_section_test.dart` (the picker)
- SEC-08: `test/core/platform/screen_privacy_test.dart`, `test/app/bootstrap_test.dart`, `android/app/src/test/.../LockWindowTest.kt`
- AND-06, F42: `test/features/overview/model/home_widget_test.dart` (nothing written while amounts are hidden), `test/features/overview/forms/widget_face_test.dart`, `test/scenarios/app/widget_words_test.dart`, `android/app/src/test/.../WidgetViewTest.kt`
- F39: `test/features/lock/ui/security_section_test.dart` (the switch), `test/core/platform/startup_gate.dart` (on, off, not offered again), `test/features/backup/model/encrypted_backup_manager_test.dart`
- F40, F52: `test/core/platform/startup_gate.dart` (turned down: nothing thrown, nothing noted), `test/features/lock/ui/lock_screen_test.dart`, `test/features/lock/ui/security_section_test.dart`
- F38: `test/features/lock/ui/lock_screen_test.dart` (typing or trying again takes the old words away)
- F67: `test/app/shell_test.dart`, `test/app/bootstrap_test.dart`, `test/app/android/lock_adapter_test.dart`
- F92: `infrastructure/vault/test/ledger_vault/ledger_vault_test.dart` (reopen), `test/core/platform/startup_gate.dart`, `test/core/platform/lock_gate_test.dart`, `test/features/lock/ui/lock_screen_test.dart`, `test/app/shell_test.dart`, `test/app/bootstrap_test.dart`

## fixed in 6.3

These tests run (no `knownDefect` skip) and pass.

- AND-01 (p6_3_release_test.dart): REQUEST_INSTALL_PACKAGES and the update code are in the sideload flavor only; the play flavor has neither.

## fixed in 1.3

Their tests run without `knownDefect` and must pass.

- INV-01 (p1_3_trade_costs_test.dart): the holding page, the entry list, the balances and the composer all show a trade at `Entry.settlement` (ledger_trade_costs `settlementAmount`); the sale shows +996,145
- ENT-01 (p1_3_trade_costs_test.dart, 2 tests): a fee or tax still at its suggestion when the trade is opened is untouched and follows every change (1,026 after doubling the shares; 427 and 1,500 for half a sale); one the person typed stays
- ENT-08 (p1_3_trade_costs_test.dart): the cost preview of a sale replays the book up to the sale's day without the sale being changed (100,000, not 200,000)
- ACC-06 (no known-defect test; tests in test/core/ledger/services/balance_service_test.dart): `BalanceService.entriesOf` and `flowOf` replace the scans of the person, loan and account pages; ETFs are grouped by ledger_trade_costs `isEtf`
- PKG-04 / F72 (no known-defect test; decision D4, approved by the owner 2026-11-23): every loan figure is read off one exact schedule, ledger_loans `loanSchedule`, each month's interest rounded half up on its own (`loanInterestRounding`); tests in `packages/ledger/loans/test/calc/loan_plan_test.dart`, `test/baseline/loans_baseline_test.dart` (1,000,000 at 2% over 240 months: last month 5,010, interest 214,111; interest only adds up to 400,000) and `test/features/accounts/forms/loan_cards_test.dart`

## fixed in 3.2

The tests that were skipped here now run unskipped in `p3_2_keys_test.dart`; the other findings of the package are covered by the tests named.

- SEC-01: `p3_2_keys_test.dart`; `test/core/platform/startup_keys.dart` (run by `startup_test.dart`) (sealed key, migration of a plain `quick-open.key`)
- SEC-04: `p3_2_keys_test.dart`; `startup_keys.dart` (the password stays until a new one is set)
- SEC-02, SEC-13: `infrastructure/vault/test/backup_security/password_policy_test.dart`, `infrastructure/vault/test/ledger_backup/backup_v4_test.dart`, `test/core/messages/key_failures_test.dart`, `test/features/backup/model/drive_backup_test.dart`
- SEC-06: `infrastructure/vault/test/ledger_vault/reset_keys_test.dart`, `infrastructure/vault/test/backup_security/keyring_slots_test.dart`, `startup_keys.dart`
- SEC-09: `reset_keys_test.dart` (restore with files), `startup_keys.dart`
- SEC-10: `test/features/lock/ui/lock_screen_test.dart`
- SEC-11: `backup_v4_test.dart`
- SEC-12: `test/core/platform/sensitive_clipboard_test.dart`
- F97: `test/features/lock/ui/security_section_test.dart`
- F98: `key_failures_test.dart`
- F91: `startup_keys.dart`, `lock_screen_test.dart`
- F46, F90: `test/features/backup/ui/backup_section_test.dart`, `drive_backup_test.dart`

## fixed in 1.4

The tests run unskipped in `p1_4_write_invariants_test.dart`.

- LOG-02: 3 tests; every command that writes an entry checks it against the write rules of `packages/ledger/entries` and refuses a zero amount, a same-account transfer and foreign spending without NT$ amount (`RecordRefused`)
- LOG-12: renaming a merchant renames it on the recurring items too; a refused write is one typed `LedgerProblem` (`RecordRefused`, `SharesShort`) told by `describeProblem` wherever it is caught

## fixed in 1.2

Work package 1.2 (one source for dates, the clock and holidays). None of these had a known-defect test; each is now stated by ordinary tests with literal expectations.

- PKG-05: `packages/core/test/time/clock_test.dart`, `test/core/time/app_clock_test.dart` (today is the phone's own calendar day, not Taipei's)
- ARC-09: `packages/core/test/time/clock_test.dart` (time to the next local midnight; the app's lifecycle sets a timer to it)
- PKG-07: `packages/core/test/time/holidays/business_days_test.dart`, `test/features/accounts/model/card_summary_test.dart`, `test/design_system/display/date_test.dart` (card due date 順延至); stock settlement skips holidays, the market's own closures (5/1) and make-up Saturdays (the exchange neither trades nor settles on them) since decision D24 (approved by the owner 2026-11-23); 2025 to 2027 checked against the exchange's published schedule: `packages/ledger/trade_costs/test/calc/settlement_test.dart`, `packages/ledger/trade_costs/test/rules/taiwan_market_days_test.dart`, `test/core/ledger/trading_test.dart`, `test/features/entries/forms/investment_fields_test.dart` (a year in no table: weekends only, shown as 未含國定假日)
- ENT-16 (b, c): `test/features/entries/model/compose_draft_test.dart` (a draft left on today follows today); the trash retention is `packages/core/lib/constants/retention.dart`; (a) future dates left for a product decision
- F25: `test/core/ledger/repositories/holding_repository_test.dart`, `test/design_system/display/date_test.dart`
- F75: `test/design_system/display/date_test.dart` (本月 only for the current month)
- F86: `test/design_system/display/date_test.dart` (ranges carry years)
- RPT-06 (date part): rule B3 has no entries left; `test/design_system/display/date_test.dart`

## fixed in 2.1

The tests of these ids run in every test run now, no longer skipped.

- DAT-01 (p2_1_loading_test.dart, 3 tests): a row that cannot be read (not JSON, a newer `_v`, the wrong JSON type) is set aside and kept on disk; the other 100 entries load. More cases in test/core/ledger/persistence/quarantine_test.dart.
- DAT-05 (p2_1_loading_test.dart): a category made after an entry named it by name takes that entry over by id, so a rename reaches it on disk.
- DAT-02 (no known-defect test before): test/core/ledger/persistence/write_queue_test.dart, "a change made while the book is being read back brings another read" (fails before the fix).
- DAT-08 (no known-defect test before): notes of deletions older than the trash's 30 days are dropped when the book opens; test/core/ledger/persistence/quarantine_test.dart.
- DAT-09 (no known-defect test before): book version and migration steps (book_migrations_test.dart), unknown fields kept on rewrite (quarantine_test.dart), every kept book opens, is brought up and reads the same again (old_books_test.dart).
- DAT-12 (no known-defect test before): a book that was opened before is never given the starting accounts again; quarantine_test.dart.

## fixed in 1.5

Work package 1.5 (one decision and one wording per status). These findings had no known-defect test; the tests below run in the ordinary suite.

- F19: `test/features/overview/ui/sections/card_due_section_test.dart` (card page, account list and 總覽 say 已逾期 2 天); `packages/domain/test/credit_cards/card_rules_test.dart`
- F29: `test/design_system/display/status_test.dart`; the budget square keeps its colour and shows the 快用完/超支 badge only
- F07: `test/core/ledger/rules/budget_rules_test.dart` (over by amount, not rounded percent); the overview card says 本月超支 with the badge
- F44: `test/features/overview/model/home_widget_test.dart` (`state` written for the widget); `android/app/src/test/.../WidgetViewTest.kt`
- F84: `test/design_system/display/status_test.dart` (a let-go day says 已略過)
- INV-06: `test/core/ledger/repositories/holding_repository_test.dart` (sold-out not held); `packages/domain/test/investments/holding_rules_test.dart` — the sold-out part only; the stale-price mark and the neutral flat colour are not done
- REC-04: the total reads 本月合計 and a subscription row opens its item; the end-before-start check is 1.4's

## fixed in 3.5

Work package 3.5 (errors and diagnostics). These findings had no known-defect test; the tests below run in the ordinary suite.

- ARC-07: `test/core/diagnostics/error_log_test.dart` (the stack is kept, cleaned and bounded; an amount and a note never reach the file; nothing is written while recording, batches go in order, a repeated fault is counted, a full file is put aside); `test/core/diagnostics/unhandled_errors_test.dart` (faults nobody caught are kept, shown while developing, told once a minute at most in a release build; the log is written when the app is left). Quiet failures that used to pass unseen are kept now: `test/core/platform/preferences_test.dart`, `test/core/ledger/repositories/draft_repository_test.dart`, `test/app/android/market_cache_adapter_test.dart`. Not done: an opt-in crash report sent off the phone (the fix line's alternative, 一鍵回報, is the existing 診斷 › 複製／下載).
- F66: `test/app/android/scanner_adapter_test.dart` (a failed download is kept in the log with the phone's reason), `test/features/entries/forms/composer_pickers_test.dart` (each failure says what to do; the wait for the download is said), `test/core/messages/scan_messages_test.dart`, `android/app/src/test/.../ScanFaultTest.kt`. The download itself failing on the owner's phone (GMS 26.45.31) is Google Play services' side and is not reproduced here; the log now says why.
- F102: `test/app/about_section_test.dart` (group 檢查更新 always answers), `test/features/settings/model/app_update_test.dart` (group how the build stands), `test/core/messages/update_messages_test.dart`

## fixed in 3.3

Work package 3.3 (lifecycle and background work). ARC-05's test runs unskipped in `p3_3_lifecycle_test.dart`; the other findings had no known-defect test and are stated by the ordinary tests named.

- ARC-05: `p3_3_lifecycle_test.dart` (two prepare() at once write one backup); `test/core/platform/app_lifecycle_test.dart` (hidden and paused are one leave, a trip the app started is none), `test/core/platform/one_at_a_time_test.dart` (the leave's backups never run twice at once, a leave meanwhile runs them once more after)
- ARC-04: `test/app/bootstrap_test.dart` group "coming back with an item due (ARC-04)" (a lock done before resumed: nothing written to the closed ledger, it fails on the code before the fix with `寫入帳本: DataSourceException(Bad state: Store is closed.)`; back within the time the item is booked once), `test/core/platform/app_lifecycle_test.dart` (the gate decides first; a lock starting as the app comes back keeps the session from writing). Locking also waits for backups being written (the weekly backup had read a closed store).
- F65: `test/features/backup/model/encrypted_backup_manager_test.dart` group "two backups asked for at once (F65)" (fails on the code before the fix with the device's `PathNotFoundException ... (errno = 2)`), `android/app/src/test/.../BackupRulesTest.kt` (the rules of every Android version take `cloud/` only; only a backup to the Google account is noted)
- ARC-06: `test/features/lock/ui/lock_screen_test.dart` (a ledger without a password, and the fingerprint, open while the opening plays), `test/app/first_screen_test.dart` (each wait of `main()` made to fail)
- DAT-03: `infrastructure/storage/test/encrypted_database_test.dart` group "a write apart (DAT-03)", `test/core/ledger/persistence/sql_ledger_data_source_test.dart` (a change written apart keeps the same rows), `test/perf/batch_write_gate_test.dart` (20,000 entries renamed: the longest hold under 4.5% of the rename written at once; thresholds.md). Not done: a backup still reads the book's rows on the screen's isolate (it then writes it on a worker, as before).
- AND-05: `android/app/src/test/.../BackgroundWorkTest.kt`, `UploadSessionTest.kt`, `test/app/android/market_cache_adapter_test.dart`, `test/app/lifecycle_services_test.dart` (the market job fetches only what the ledger needs), `test/features/backup/ui/backup_section_test.dart` and `test/core/platform/preferences_test.dart` (photos wait for Wi-Fi, the person's switch). Not done: an upload started by hand in the app is not resumed (its file is written for that upload and deleted after it).
- AND-07: `android/app/src/test/.../OffMainTest.kt`

## fixed in 3.4

Work package 3.4 (reminders and calendar). REM-05's test runs unskipped in `p3_4_reminders_test.dart`; the other findings had no known-defect test and are stated by the ordinary tests named (Kotlin tests run in both flavors).

- AND-02, REM-03, F48: `test/features/reminders/model/reminder_alerts_test.dart` (group F48: a day 3 days overdue is handed over, 8 days is past its grace; an overdue card; the nudge not told late; ids that stay; at most 160), `test/scenarios/reminders/reminder_dates_test.dart` (today's 9:00 still told at 10; the nudge over the 62 days), `test/features/reminders/model/reminder_rules_test.dart` (the table), `test/app/android/notification_adapter_test.dart` (what the phone is handed), `android/app/src/test/.../ReminderGraceTest.kt` (armed, posted at once within its grace, dropped beyond it, posted once)
- AND-03: `ReminderGraceTest.kt` (the broadcasts that re-arm, the exact-alarm permission among them, match the manifest)
- REM-01, REM-02: `test/app/ledger_session_test.dart` (group the inbox while the ledger stays open: coming back books, an item is taken out only once kept, a refused booking leaves it, a stop between the two books nothing twice, two reads at once), `test/core/ledger/persistence/write_queue_test.dart` (refusals counted)
- REM-05: `p3_4_reminders_test.dart`; `test/core/ledger/services/recurring_service_test.dart` (group unpostedDates), `test/features/reminders/model/calendar_sync_test.dart` and `test/features/reminders/ui/reminders_section_test.dart` (calendar access taken away still lets the link go)
- REM-04, F95: `calendar_sync_test.dart` (group calendarChanges; nothing changed writes nothing, a change keeps its event's id; no amounts unless turned on), `reminder_alerts_test.dart` (a closing price plans nothing again), `android/app/src/test/.../CalendarBridgeTest.kt`; the expedited sync request itself is Android's (not unit-testable)
- F81: `reminder_alerts_test.dart` (paying a card plans again at once), `test/features/reminders/model/coalesced_run_test.dart`
- F53, F45, F101, AND-11: `reminders_section_test.dart` (最多晚 1 小時 until alarms on the minute are allowed; a kind shown off while notifications are not allowed, and ticking it asks; budget reminders start off; the battery's 去開 says what to choose), `test/core/messages/reminder_messages_test.dart`, `reminder_rules_test.dart` and `notification_adapter_test.dart` (a channel per kind). AND-11's scanner without Play services is not built: it needs a camera permission and a QR decoding library, a new dependency; 3.5 already words the failure.

## not covered

One line per finding that has no test here. Findings with an executed reproduction come first with the specific reason; the rest were found by reading code (no executed reproduction), which the brief does not require.

### With an executed reproduction

- DEB-02 (S1, 2.4): the fix adds a principal/interest repayment form and fields that do not exist yet, so nothing can be asserted on today's API
- PKG-01 (S2, 1.3): partly fixed in 1.3: the discount is the preference 券商手續費折扣 (default 6折; tests in test/core/platform/preferences_test.dart and test/features/entries/model/compose_form_test.dart); the day-trade tax stays open, as an entry has no notion of a day trade, and the holiday table belongs to the dates package
- F24 (S2, 1.4): the intended behaviour (warn or refuse a buy that overdraws) is not decided; 1.4 shows a non-blocking warning (`NegativeBalanceAfter`) for the owner to confirm
- F77 (S2, 2.2): does not reproduce at ledger level: budgetCrossings already reports 本月總預算已超支 for the same data; the device case came from other state
- F80 (S2, 2.2): the fix is a design choice (start month of carry-over or retroactive leftover); no single correct value
- F20 (S2, 2.4): design intent open: whether the first instalment belongs to the current statement
- F30 (S2, 2.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- ENT-07 (S2, 2.5): needs rates with dates (new data model in 2.5)
- F61 (S2, 2.5): the wrong input is the fetched previous close; the fix needs adjusted closes (new market data)
- F04 (S2, 4.2): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F17 (S2, 4.2): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F49 (S2, 4.2): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F11 (S2, 4.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F15 (S2, 4.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F18 (S2, 4.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F108 (S2, 5.1): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F109 (S2, 5.1): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- DSN-04 (S2, 5.2): missing platform picker abilities; feature work, not a regression
- F104 (S2, 5.2): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- CAT-01 (S2, 5.4): how a merged-away budget should combine is not decided
- F32 (S2, 5.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F87 (S2, 5.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- LOG-10 (S2, 5.4): performance, not correctness; belongs to the benchmark gate (0.2)
- RPT-02 (S2, 5.4): needs a new period-aware tag count API
- IMP-03 (S2, 6.1): feature request (column mapping, other encodings)
- REC-03 (S3, 2.3): the division by zero is inside widget code (yearly share); no API returns it
- ACC-04 (S3, 2.4): the fix is a prompt at archive time; the correct end state is not one assertion
- F16 (S3, 2.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion

### Found by reading code, no executed reproduction

- TST-01 (S2, 0.1): no executed reproduction; not turned into a test
- TST-03 (S2, 0.2): no executed reproduction; not turned into a test
- TST-05 (S2, 0.2): no executed reproduction; not turned into a test
- LOG-03 (S2, 1.4): no executed reproduction; not turned into a test
- LOG-07 (S2, 1.4): no executed reproduction; not turned into a test
- BUD-03 (S2, 2.2): no executed reproduction; not turned into a test
- BUD-04 (S2, 2.2): no executed reproduction; not turned into a test
- REC-02 (S2, 2.3): no executed reproduction; not turned into a test
- LOG-04 (S2, 2.4): no executed reproduction; not turned into a test
- INV-07 (S2, 2.5): no executed reproduction; not turned into a test
- LOG-05 (S2, 2.5): no executed reproduction; not turned into a test
- ARC-02 (S2, 4.1): no executed reproduction; not turned into a test
- DAT-06 (S2, 4.1): no executed reproduction; not turned into a test
- DSN-02 (S2, 4.1): no executed reproduction; not turned into a test
- SET-01 (S2, 4.1): no executed reproduction; not turned into a test
- F59 (S2, 4.2): no executed reproduction; not turned into a test
- ARC-01 (S2, 4.3): no executed reproduction; not turned into a test
- ARC-08 (S2, 4.3): no executed reproduction; not turned into a test
- ARC-03 (S2, 4.4): no executed reproduction; not turned into a test
- ENT-10 (S2, 4.4): no executed reproduction; not turned into a test
- DSN-03 (S2, 5.1): no executed reproduction; not turned into a test
- F47 (S2, 5.1): no executed reproduction; not turned into a test
- F50 (S2, 5.1): no executed reproduction; not turned into a test
- DSN-05 (S2, 5.2): no executed reproduction; not turned into a test
- F09 (S2, 5.2): no executed reproduction; not turned into a test
- F100 (S2, 5.2): no executed reproduction; not turned into a test
- F13 (S2, 5.2): no executed reproduction; not turned into a test
- F35 (S2, 5.2): no executed reproduction; not turned into a test
- F57 (S2, 5.2): no executed reproduction; not turned into a test
- F93 (S2, 5.2): no executed reproduction; not turned into a test
- DSN-06 (S2, 5.3): no executed reproduction; not turned into a test
- RPT-01 (S2, 5.4): no executed reproduction; not turned into a test
- RPT-03 (S2, 5.4): no executed reproduction; not turned into a test
- RPT-04 (S2, 5.4): no executed reproduction; not turned into a test
- RPT-05 (S2, 5.4): no executed reproduction; not turned into a test
- DSN-07 (S2, 5.5): no executed reproduction; not turned into a test
- IMP-05 (S2, 6.1): no executed reproduction; not turned into a test
- DAT-04 (S2, 6.2): no executed reproduction; not turned into a test
- CI-01 (S2, 6.3): no executed reproduction; not turned into a test
- TST-04 (S3, 0.1): no executed reproduction; not turned into a test
- TST-06 (S3, 0.1): no executed reproduction; not turned into a test
- TST-02 (S3, 0.2): no executed reproduction; not turned into a test
- PKG-08 (S3, 1.3): stopped in 1.3: the 2027 and 2028 rows of the rate table are the end dates the law in force sets (bond-ETF exemption, day-trade halving), not forecasts, and test/baseline/fees_and_tax_baseline_test.dart pins the 2027 bond-ETF tax
- DAT-11 (S3, 1.4): no executed reproduction; not turned into a test
- DAT-13 (S3, 1.4): no executed reproduction; not turned into a test
- ENT-12 (S3, 1.4): no executed reproduction; not turned into a test
- F56 (S3, 1.4): no executed reproduction; not turned into a test
- F68 (S3, 1.4): no executed reproduction; not turned into a test
- LOG-11 (S3, 1.4): no executed reproduction; not turned into a test
- F70 (S3, 1.5): no executed reproduction; not turned into a test
- F33 (S3, 2.3): no executed reproduction; not turned into a test
- F94 (S3, 2.3): no executed reproduction; not turned into a test
- F31 (S3, 2.4): no executed reproduction; not turned into a test
- F55 (S3, 2.4): no executed reproduction; not turned into a test
- LOG-13 (S3, 2.4): no executed reproduction; not turned into a test
- F27 (S3, 2.5): no executed reproduction; not turned into a test
- F28 (S3, 2.5): no executed reproduction; not turned into a test
- F60 (S3, 2.5): no executed reproduction; not turned into a test
- F62 (S3, 2.5): no executed reproduction; not turned into a test
- PKG-03 (S3, 2.5): no executed reproduction; not turned into a test
- PKG-06 (S3, 2.5): no executed reproduction; not turned into a test
- DAT-07 (S3, 4.1): no executed reproduction; not turned into a test
- DAT-10 (S3, 4.1): no executed reproduction; not turned into a test
- OVR-01 (S3, 4.1): no executed reproduction; not turned into a test
- ENT-13 (S3, 4.2): no executed reproduction; not turned into a test
- ENT-14 (S3, 4.2): no executed reproduction; not turned into a test
- F23 (S3, 4.2): no executed reproduction; not turned into a test
- F58 (S3, 4.2): no executed reproduction; not turned into a test
- F10 (S3, 4.4): no executed reproduction; not turned into a test
- F12 (S3, 4.4): no executed reproduction; not turned into a test
- F54 (S3, 4.4): no executed reproduction; not turned into a test
- AND-08 (S3, 4.5): no executed reproduction; not turned into a test
- AND-09 (S3, 4.5): no executed reproduction; not turned into a test
- ARC-10 (S3, 5.2): no executed reproduction; not turned into a test
- DSN-08 (S3, 5.2): no executed reproduction; not turned into a test
- F01 (S3, 5.2): no executed reproduction; not turned into a test
- F64 (S3, 5.2): no executed reproduction; not turned into a test
- F74 (S3, 5.2): no executed reproduction; not turned into a test
- CAT-02 (S3, 5.4): no executed reproduction; not turned into a test
- ENT-11 (S3, 5.4): no executed reproduction; not turned into a test
- ENT-15 (S3, 5.4): no executed reproduction; not turned into a test
- F36 (S3, 5.4): no executed reproduction; not turned into a test
- F37 (S3, 5.4): no executed reproduction; not turned into a test
- F88 (S3, 5.4): no executed reproduction; not turned into a test
- F89 (S3, 5.4): no executed reproduction; not turned into a test
- INV-04 (S3, 5.4): no executed reproduction; not turned into a test
- INV-05 (S3, 5.4): no executed reproduction; not turned into a test
- DSN-09 (S3, 5.5): no executed reproduction; not turned into a test
- IMP-06 (S3, 6.1): no executed reproduction; not turned into a test
- AND-04 (S3, 6.3): no executed reproduction; not turned into a test
- AND-10 (S3, 6.3): no executed reproduction; not turned into a test
- CI-02 (S3, 6.3): no executed reproduction; not turned into a test
- CI-03 (S3, 6.3): no executed reproduction; not turned into a test
- CI-04 (S3, 6.3): no executed reproduction; not turned into a test
