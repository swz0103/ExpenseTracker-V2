# Known defects: status

Each row is a finding of the audit with a test that states the CORRECT behaviour and is skipped until its work package fixes it (`skip: knownDefect(id, package)`, see `known_defect.dart`). To run them all: `flutter test --dart-define=RUN_KNOWN_DEFECTS=true test/known_defects`.

`fails-when-enabled` records whether the test FAILS when run enabled, i.e. whether it detects the defect today. `registry_test.dart` requires every skipped id to be listed here and no row to say `no`.

The expectations were written against today's APIs. A fix that changes an API (for example `BudgetService.allowance`) must update the call in the test it un-skips; the asserted behaviour stays.

| id | package | test file | fails-when-enabled | note |
|---|---|---|---|---|
| ACC-05 | 1.1 | p1_1_amounts_test.dart | yes | a credit limit typed as 80,000 becomes null |
| F107 | 1.1 | p1_1_amounts_test.dart | yes | no semantics label carrying 支出 on the amount of an entry row |
| F78 | 1.1 | p1_1_amounts_test.dart | yes | a month 100.35% used shows 100% in the picker, not 超支 |
| IMP-04 | 1.1 | p1_1_amounts_test.dart | yes | importCsv throws FormatException on an amount of .5 (TWD) |
| ENT-01 | 1.3 | p1_3_trade_costs_test.dart | yes | 2 tests; fee stays 513 after doubling shares (expects 1,026); sale fee stays 855 (expects 427) |
| ENT-08 | 1.3 | p1_3_trade_costs_test.dart | yes | sale-cost preview of an old sale is 200,000, expected 100,000 |
| INV-01 | 1.3 | p1_3_trade_costs_test.dart | yes | holding page row shows +999,145, the account got +996,145 |
| LOG-02 | 1.4 | p1_4_write_invariants_test.dart | yes | 3 tests; add() stores a zero amount, a same-account transfer and foreign spending without NT$ amount |
| LOG-12 | 1.4 | p1_4_write_invariants_test.dart | yes | renaming a merchant leaves the recurring item on the old name |
| DAT-01 | 2.1 | p2_1_loading_test.dart | yes | 3 tests (not json / newer _v / wrong JSON type); load() throws, 0 of 100 good rows load |
| DAT-05 | 2.1 | p2_1_loading_test.dart | yes | category rename is not written to entries on disk; reopened entry keeps the old name |
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
| SEC-03 | 3.1 | p3_1_lock_test.dart | yes | the right password opens the ledger straight after 10 wrong ones |
| SEC-05 | 3.1 | p3_1_lock_test.dart | yes | full VaultRoot on a real encrypted store: a sheet opened over the book is still on screen after startup.lock() |
| ARC-05 | 3.3 | p3_3_lifecycle_test.dart | yes | two back-to-back prepare() calls write two backups |
| REM-05 | 3.4 | p3_4_reminders_test.dart | yes | a reminder is still made for the skipped Nov 25 |
| ENT-02 | 4.2 | p4_2_forms_test.dart | yes | form keeps the split but build() drops it after switching to a US$ account |
| ENT-03 | 4.2 | p4_2_forms_test.dart | yes | 2 widget tests (back key, scrim tap); sheet closes with no dialog and no draft |
| ENT-05 | 4.2 | p4_2_forms_test.dart | yes | picking a merchant replaces the chosen account (card) with cash |
| ENT-06 | 4.2 | p4_2_forms_test.dart | yes | editing a transfer previews fromAfter 98,000, expected 99,000 |
| DSN-01 | 5.1 | p5_1_design_test.dart | yes | 收入 tab text is 2.21:1 on white (expects 4.5:1) |
| IMP-01 | 6.1 | p6_1_import_test.dart | yes | a positive amount with no type column is imported as income |
| IMP-02 | 6.1 | p6_1_import_test.dart | yes | round trip loses the US$ currency (first of 10 differences) |
| AND-01 | 6.3 | p6_3_release_test.dart | yes | main AndroidManifest.xml declares REQUEST_INSTALL_PACKAGES |

38 findings covered.

## fixed in 3.2

The tests that were skipped here now run unskipped in `p3_2_keys_test.dart`; the other findings of the package are covered by the tests named.

- SEC-01: `p3_2_keys_test.dart`; `test/core/platform/startup_keys_test.dart` (sealed key, migration of a plain `quick-open.key`)
- SEC-04: `p3_2_keys_test.dart`; `startup_keys_test.dart` (the password stays until a new one is set)
- SEC-02, SEC-13: `infrastructure/vault/test/backup_security/password_policy_test.dart`, `infrastructure/vault/test/ledger_backup/backup_v4_test.dart`, `test/core/messages/key_messages_test.dart`, `test/features/backup/model/drive_backup_test.dart`
- SEC-06: `infrastructure/vault/test/ledger_vault/reset_keys_test.dart`, `infrastructure/vault/test/backup_security/keyring_slots_test.dart`, `startup_keys_test.dart`
- SEC-09: `reset_keys_test.dart` (restore with files), `startup_keys_test.dart`
- SEC-10: `test/features/lock/ui/lock_screen_test.dart`
- SEC-11: `backup_v4_test.dart`
- SEC-12: `test/core/platform/sensitive_clipboard_test.dart`
- F97: `test/features/lock/ui/security_section_test.dart`
- F98: `key_messages_test.dart`
- F91: `startup_keys_test.dart`, `lock_screen_test.dart`
- F46, F90: `test/features/backup/ui/backup_section_test.dart`, `drive_backup_test.dart`

## not covered

One line per finding that has no test here. Findings with an executed reproduction come first with the specific reason; the rest were found by reading code (no executed reproduction), which the brief does not require.

### With an executed reproduction

- DEB-02 (S1, 2.4): the fix adds a principal/interest repayment form and fields that do not exist yet, so nothing can be asserted on today's API
- F43 (S1, 3.1): needs the Android quick-action/notification channel while locked; SEC-05 covers the shared cause (routes above the lock screen)
- F65 (S1, 3.3): device-only: Google system backup copy rename race on Android
- AND-02 (S1, 3.4): Android alarm receiver behaviour after reboot; needs a device or emulator (Kotlin side), reproduced on an API 34 emulator
- REM-01 (S1, 3.4): the resume path is inline in a State (didChangeAppLifecycleState) and the inbox source exists only on Android; testable once LedgerSession gets a resume step
- PKG-01 (S2, 1.3): the fix adds a configurable discount and a day-trade parameter (new API); today's fixed 6折 is what the baseline pins
- F24 (S2, 1.4): the intended behaviour (warn or refuse a buy that overdraws) is not decided
- F19 (S2, 1.5): wording and one shared overdue judgement across three screens; no single value to assert
- F77 (S2, 2.2): does not reproduce at ledger level: budgetCrossings already reports 本月總預算已超支 for the same data; the device case came from other state
- F80 (S2, 2.2): the fix is a design choice (start month of carry-over or retroactive leftover); no single correct value
- F20 (S2, 2.4): design intent open: whether the first instalment belongs to the current statement
- F30 (S2, 2.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- ENT-07 (S2, 2.5): needs rates with dates (new data model in 2.5)
- F61 (S2, 2.5): the wrong input is the fetched previous close; the fix needs adjusted closes (new market data)
- F39 (S2, 3.1): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- ARC-04 (S2, 3.3): needs LifecycleServices on a real vault with timing between microtasks; the audit repro only printed, a deterministic assertion was not found
- F48 (S2, 3.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F53 (S2, 3.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F95 (S2, 3.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
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
- F06 (S3, 1.1): thousands separators: the amount type of 1.1 defines the correct strings
- F34 (S3, 1.1): rounding of averages: defined by the amount rules of 1.1
- F07 (S3, 1.5): wording on the budget card; UI text only
- REC-04 (S3, 1.5): labels and an inert row in the recurring page; UI only
- REC-03 (S3, 2.3): the division by zero is inside widget code (yearly share); no API returns it
- ACC-04 (S3, 2.4): the fix is a prompt at archive time; the correct end state is not one assertion
- F16 (S3, 2.4): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion
- F66 (S3, 3.5): observed on a device; UI, visual or platform behaviour with no deterministic unit or widget assertion

### Found by reading code, no executed reproduction

- TST-01 (S2, 0.1): no executed reproduction; not turned into a test
- TST-03 (S2, 0.2): no executed reproduction; not turned into a test
- TST-05 (S2, 0.2): no executed reproduction; not turned into a test
- ENT-04 (S2, 1.1): no executed reproduction; not turned into a test
- ENT-09 (S2, 1.1): no executed reproduction; not turned into a test
- INV-03 (S2, 1.1): no executed reproduction; not turned into a test
- PKG-05 (S2, 1.2): no executed reproduction; not turned into a test
- PKG-07 (S2, 1.2): no executed reproduction; not turned into a test
- PKG-04 (S2, 1.3): no executed reproduction; not turned into a test
- LOG-03 (S2, 1.4): no executed reproduction; not turned into a test
- LOG-07 (S2, 1.4): no executed reproduction; not turned into a test
- DAT-02 (S2, 2.1): no executed reproduction; not turned into a test
- BUD-03 (S2, 2.2): no executed reproduction; not turned into a test
- BUD-04 (S2, 2.2): no executed reproduction; not turned into a test
- REC-02 (S2, 2.3): no executed reproduction; not turned into a test
- LOG-04 (S2, 2.4): no executed reproduction; not turned into a test
- INV-07 (S2, 2.5): no executed reproduction; not turned into a test
- LOG-05 (S2, 2.5): no executed reproduction; not turned into a test
- AND-05 (S2, 3.3): no executed reproduction; not turned into a test
- ARC-06 (S2, 3.3): no executed reproduction; not turned into a test
- DAT-03 (S2, 3.3): no executed reproduction; not turned into a test
- REM-03 (S2, 3.4): no executed reproduction; not turned into a test
- REM-04 (S2, 3.4): no executed reproduction; not turned into a test
- ARC-07 (S2, 3.5): no executed reproduction; not turned into a test
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
- F03 (S3, 1.1): no executed reproduction; not turned into a test
- F21 (S3, 1.1): no executed reproduction; not turned into a test
- RPT-06 (S3, 1.1): no executed reproduction; not turned into a test
- ARC-09 (S3, 1.2): no executed reproduction; not turned into a test
- ENT-16 (S3, 1.2): no executed reproduction; not turned into a test
- F25 (S3, 1.2): no executed reproduction; not turned into a test
- F75 (S3, 1.2): no executed reproduction; not turned into a test
- F86 (S3, 1.2): no executed reproduction; not turned into a test
- ACC-06 (S3, 1.3): no executed reproduction; not turned into a test
- PKG-08 (S3, 1.3): no executed reproduction; not turned into a test
- DAT-11 (S3, 1.4): no executed reproduction; not turned into a test
- DAT-13 (S3, 1.4): no executed reproduction; not turned into a test
- ENT-12 (S3, 1.4): no executed reproduction; not turned into a test
- F56 (S3, 1.4): no executed reproduction; not turned into a test
- F68 (S3, 1.4): no executed reproduction; not turned into a test
- LOG-11 (S3, 1.4): no executed reproduction; not turned into a test
- F29 (S3, 1.5): no executed reproduction; not turned into a test
- F44 (S3, 1.5): no executed reproduction; not turned into a test
- F70 (S3, 1.5): no executed reproduction; not turned into a test
- F84 (S3, 1.5): no executed reproduction; not turned into a test
- INV-06 (S3, 1.5): no executed reproduction; not turned into a test
- DAT-08 (S3, 2.1): no executed reproduction; not turned into a test
- DAT-09 (S3, 2.1): no executed reproduction; not turned into a test
- DAT-12 (S3, 2.1): no executed reproduction; not turned into a test
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
- AND-06 (S3, 3.1): no executed reproduction; not turned into a test
- F38 (S3, 3.1): no executed reproduction; not turned into a test
- F40 (S3, 3.1): no executed reproduction; not turned into a test
- F42 (S3, 3.1): no executed reproduction; not turned into a test
- F52 (S3, 3.1): no executed reproduction; not turned into a test
- F67 (S3, 3.1): no executed reproduction; not turned into a test
- F92 (S3, 3.1): no executed reproduction; not turned into a test
- SEC-07 (S3, 3.1): no executed reproduction; not turned into a test
- SEC-08 (S3, 3.1): no executed reproduction; not turned into a test
- AND-07 (S3, 3.3): no executed reproduction; not turned into a test
- AND-03 (S3, 3.4): no executed reproduction; not turned into a test
- AND-11 (S3, 3.4): no executed reproduction; not turned into a test
- F101 (S3, 3.4): no executed reproduction; not turned into a test
- F45 (S3, 3.4): no executed reproduction; not turned into a test
- F81 (S3, 3.4): no executed reproduction; not turned into a test
- REM-02 (S3, 3.4): no executed reproduction; not turned into a test
- F102 (S3, 3.5): no executed reproduction; not turned into a test
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
