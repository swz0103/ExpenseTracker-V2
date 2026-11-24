# Performance thresholds (rule C4)

`thresholds.json` holds the upper limit of each emulator-bench figure.
`tool/check_bench.dart` compares them with `build/integration_response_data.json`
(written by `integration_test/bench_test.dart`) and fails the emulator
workflow when one is exceeded or missing. Keys are the bench's report keys:
`10k_` / `100k_` prefix the 10,000 and 100,000 entry runs, none means 3,600.
A dotted key reads a field of a nested frame-timing report (`save` is the
`watchPerformance` summary taken while one entry is saved).

## Source of the numbers

Measured on an Android 14 emulator (API 34, x86_64), profile mode, commit
91c76bd. Each limit is about 2x the measured value, rounded, so noise on a
shared CI runner does not fail the build but a real regression does.

| key | unit | measured 3.6k / 10k / 100k | limit 3.6k / 10k / 100k |
|---|---|---|---|
| `load_ms` | ms | 15–151 / 72–76 / 838–1,007 | 400 / 150 / 1,700 |
| `save_shown_us` (save until the screen shows it) | microseconds | 117 / 118 / 133 ms | 250 / 250 / 270 ms |
| `month_ms` (one month switch) | ms | 115 / 116 / 116 | 240 / 240 / 240 |
| `reports_open_ms` | ms | 232 / 233 / 249 | 470 / 470 / 500 |
| `save.average_frame_build_time_millis` (frame build after a save) | ms | 1.8 / 2.1 / 6.5 | 4 / 5 / 13 |
| `memory_mb` (RSS with the book loaded) | MiB | 232 / 286 / 475 | 470 / 580 / 950 |

### The first-open journal rebuild (work package 2.0, D51)

| key | unit | estimate 100k | limit 100k |
|---|---|---|---|
| `100k_journal_rebuild_ms` (every posting made afresh from the records, on worker isolates) | ms | 3,709 (CI emulator, 2026-11-24) | 7,500 |
| `100k_journal_rebuild_held_ms` (the longest the screen's isolate was held meanwhile) | ms | 28 (CI emulator, 2026-11-24) | 60 |

Not yet measured on the emulator: these two limits are twice an estimate
from the host bench below (2,600–3,800 ms and 27–122 ms on the development
VM), the rebuild scaled by about two for an emulator or a mid-range phone
(the emulator's 100k load is close to the Galaxy A56's). Replace them with
twice the first emulator run's figures; lowering is welcome, raising needs
a reason as above. The 3.6k and 10k runs report the same figures, ungated.

Which `save` field the "frame build after save" figure came from was not
recorded with the measurements; the average frame build time is assumed (the
worst frame would be a flakier gate). Check against a real run.

Real-phone reference (Galaxy A56, not gated, for context only): load
37 / 125 / 1,144 ms; tab switch p99 33.9 / 36.6 / 85.6 ms; memory
278 / 348 / 525 MiB.

Raising a limit needs a reason in the commit message; lowering one after an
optimisation is welcome.

## Why the smallest ledger has the loosest load limit

The 3,600-entry load is the first thing the bench measures after the app
starts, so it carries one-time start-up cost: two runs of the same code gave
15 ms (run 44913445914) and 151 ms (run 45014933750), while the 10k load in
the same runs was 72 and 76 ms. Its limit is therefore an absolute ceiling
(400 ms), not twice a measurement; the 10k and 100k limits are the ones that
catch a regression in loading itself.

## The journal of postings (host bench, work package 2.0)

`journal_thresholds.json` holds the limits of `journal_bench_test.dart`
(`BENCH=1 flutter test test/perf/journal_bench_test.dart`): a book of
100,000 entries (70% spending, 2% of it in 3 instalments, 10% income, 15%
transfers, 5% buys of three stocks; 100,017 intents, 212,340 postings) in
the encrypted file, as the app keeps it. Measured on the development VM
(Xeon, shared with other runs at the time, Flutter test JIT), three runs;
each limit about twice the slowest quiet run, rounded, and never above
the limit before it (a figure whose doubled run would be, `save_posting_us`
and `month_report_us`, keeps its earlier limit). Not measured on a phone:
expect about two times these there (the emulator section above).

| key | what | measured, load 1.6–2.6 (2026-11-24, round 2, before D87) | measured, load 15–17 (after D87 and the holdings read on the worker) | limit |
|---|---|---|---|---|
| `open_100k_ms` | the first opening after this version until the book is on the screen: every row read, decoded and brought up once on a worker (`book_opening.dart`, `EncryptedDatabase.workApart`), the holdings replayed there too | 1,131–1,258 ms | 1,706–2,367 ms | 2,700 ms |
| `open_held_ms` | the longest the screen's isolate was held meanwhile: only adopting what the worker made (target < 100 ms) | 90–159 ms (the `Ledger` replayed the holdings here then) | 66 ms | 100 ms |
| `rebuild_100k_ms` | from the start of that opening until every posting is written: the same worker posts the decoded entries (`postBook`, `journalApartChunk` at a time) into one transaction, indexes after, the mark last | 2,839–3,307 ms | 4,710–5,378 ms | 6,000 ms |
| `rebuild_held_ms` | the longest the screen's isolate was held while the journal was posted (the book sent to it as a copy, then collected) | 90–113 ms | 266–315 ms (over its limit at this load) | 250 ms |
| `repost_100k_ms` | posting the whole book afresh later, from the records alone (`postApart`: the posting rules changed, a change the keeper could not follow) | 2,662–2,794 ms | 3,429–6,197 ms | 6,000 ms |
| `parity_held_share` | `parity_hold_gate_test.dart`: the journal's check of a 100,000-entry book in memory, on the screen's isolate in slices of `journalSlice`: the longest the isolate is held, as a share of the whole check run at once (r13 F8). What is left in one piece is the first balance of an account worked out cold (the ledger's own index, which the screens build too) | — | 0.428 (84 of 197 ms, load ~15, 2026-11-24) | 0.6 |
| `parity_held_ms` | the same gate's longest hold itself, in ms (review 18): the share stays the same as the book grows, the hold does not, so both are gated. Twice the slowest quiet run, 110 ms, as the rule above | — | 84 ms (2026-11-24, r13); 110 ms (review 18); 95–186 ms (three runs, load 7–10, 2026-11-24, not a basis) | 220 ms |
| `save_posting_us` | one entry's posting and the journal's mark, one transaction, `synchronous=FULL` | 777–804 µs | 1,055–2,852 µs | 3,000 µs |
| `every_balance_us` | every account's balance today, from the months' sums and this month's postings | 557–908 µs | 582–1,144 µs | 2,000 µs |
| `month_report_us` | a month's income and spending by category | 38–55 µs | 44–63 µs | 130 µs |

Before D51 the rebuild took 11,788–12,698 ms in the screen's isolate
(limit then 26,000 ms). Where the time went at 100k before round 2
(round 1's single worker, load 1.2): reading the rows 258–308 ms, decoding
158–207, making entries 128–173, mapping 54–62, posting 248–308; in SQL the
inserts 785–930, the indexes made after 330, the commit 235–269. Round 2:
the book is decoded once, for the screens and the journal (the read,
decode and entries leave the rebuild); intents and accounts are named by
integer keys in the journal tables (a 100k posting write on 22-character
ids 834–1,013 → 471–506 ms, 30 → 13 MB); every journal query reads through
one of the five indexes (EXPLAIN QUERY PLAN), so none is dropped. The
figures under load 15–17 (four cores) are about twice the quiet ones and
are not a basis for a limit; the emulator bench decides what is next.
Isolates of one group share their collections of garbage: what the
opening's worker leaves is collected while every isolate waits, which is
why the book comes back whole (handed over, not copied) when nothing is
to be posted.

The two journal limits were provisional until the first CI emulator run
(2026-11-24, commit c172444): 3,709 ms to post 100,000 entries afresh,
the screen held at most 28 ms. They are now about twice those figures.

The save gate (`save_scale_gate_test.dart`) counts the journal's update in
the save it times, so a journal update that grows with the book fails it in
CI on any machine. Posting the whole book afresh happens once (the first
opening after this version, after a restore, after an older version wrote
records, or when the posting rules change). `journal_rebuild_gate_test.dart`
gates, in the ordinary `flutter test`, the longest hold of the screen's
isolate while a 20,000-entry book is posted afresh, as a share of posting
it at once there (at most 0.045, as the batch-write gate below). Both
share gates take the least of `gateTries` (3) runs of each side
(`leastOf`, `test/support/held.dart`): what the code holds is held every
time, while a machine busy elsewhere or another isolate's garbage
collection stalls a run now and then.

## Batch writes on the computer (`batch_write_block`, DAT-03)

Not an emulator figure: `test/perf/batch_write_gate_test.dart` runs in the
ordinary `flutter test`. It renames the merchant of 20,000 entries of a real
encrypted book twice: once written at once, and once as the app writes a
change of 500 records or more (`writeApartFrom`: the rows made 8 ms at a
time with the screen drawn between, then kept on a worker isolate through
the same connection, `EncryptedDatabase.writeApart`). It gates the longest
time the main isolate was held, as a share of the rename written at once,
so the gate holds on any machine.

| measured (5 runs, Linux host, 2026-11-23) | limit |
|---|---|
| at once: held 772–945 ms; apart: held 14–19 ms, 1,023–1,238 ms in all; share 0.016–0.021 | 0.045 (about 2× the worst share) |

What is left held includes the rename of the screens' own copy of the book
in memory, which is not the store's. Written apart, the rename takes about
a quarter longer in all; the screen keeps drawing meanwhile. Not yet in the
emulator bench: a phone figure needs a run there.

## A CSV import on the computer (`import_block`, review 12)

Not an emulator figure: `test/perf/import_gate_test.dart` runs in the
ordinary `flutter test`. It imports a CSV of 100,000 lines into the demo
book twice: once at once (`importCsv`), and once as the import page does
(`importCsvApart`: a long file read as CSV on a worker isolate, its lines
and what is found 8 ms at a time with the screen drawn between). It gates
the longest time the main isolate was held, the least of three runs, as a
share of the import at once, with the batch writes' limit.

| measured (4 runs, Linux host, 2026-11-24) | limit |
|---|---|
| at once: held 2,101–2,768 ms; apart: held 17–26 ms; share 0.008–0.011 | 0.045 (the batch writes') |

What is left held is the garbage collection of the 100,000 entries made.

## A backup's read on the computer (`backup_read_block`, D41)

Not an emulator figure: `test/perf/backup_read_gate_test.dart` runs in the
ordinary `flutter test`. It backs up a real encrypted book of 100,000
records five times as the app does (`LedgerBackup.write`: the records read
in one read transaction on a worker isolate through the same connection,
`EncryptedDatabase.readApart`, then compressed and sealed on that worker),
and gates the longest time the main isolate was held, the middle of the
five runs, as a share of the same records read on the main isolate at
once, as the backup read them before. Read there, the share would be 1 or
more.

| measured (5 runs, Linux host, 2026-11-23) | limit |
|---|---|
| read at once: held 431–641 ms; backup apart: middle of five 16–31 ms (single runs 14–318 ms); share 0.037–0.065 | 0.2 (about 3× the worst share) |

What is left held is the garbage collection of the isolate group: the
worker's allocations (the rows read, the JSON and the sealed chunks) now
and then stop every isolate of the group for a scavenge, which is why one
run in five can be held far longer than the others. It was so before as
well, when only the sealing ran on the worker. Not yet in the emulator
bench: a phone figure needs a run there.

## Pages and services that grow with the book (work package PERF)

Not emulator figures: both run in the ordinary `flutter test`.

`index_follow_gate_test.dart` deletes an entry, puts it back where it was
(as undo does) and moves one to another day on a book of 100,000 entries,
each with what a screen reads right after (the month, an entry by id, an
untouched account's entries), and gates each as a share of working the
entries' indexes out afresh, the least of three runs after a warm-up.
Before, each of these threw every index away (120–150 ms at 100k).

| measured (3 runs, Linux host, load 3–4.5, 2026-11-24) | limit |
|---|---|
| afresh 165–245 ms; entries written lately: delete 30–48 µs, undo 13–23 µs, move 20–34 µs; worst share 0.00023 | 0.0005 (about 2× the worst share) |

An entry written long ago also moves every later one along the list, a
copy that grows with the book: 1.5–2.7 ms at 100k on the host (`BENCH=1`
prints it), not gated.

`records_page_gate_test.dart` opens 紀錄 at 360 dp on the demo book and on
it with 100,000 entries more over three years (about 2,800 a month, as
the page bench of review 10), and compares the widgets built again on
隱藏金額 and on a save (counted, the same on every machine), and the
first letter searched for after a save (the least of three, as a ratio).

| measured (Linux host, 2026-11-24) | limit |
|---|---|
| 隱藏金額 686 → 723 widgets (×1.05); a save 692 → 723 (×1.04); first letter after a save 88 → 82 ms (×0.93). Before: 577 → 3,572 and 610 → 3,605 widgets | ×1.5 widgets, ×2 time (set by the work package) |

`rebuild_gate_test.dart`: 總覽 builds 79 widgets after a budget changes
(was 153), its title row following the entries rather than the whole
ledger.
