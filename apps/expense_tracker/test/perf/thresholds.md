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
| `100k_journal_rebuild_ms` (every posting made afresh from the records, on worker isolates) | ms | 4,000–7,500 | 15,000 |
| `100k_journal_rebuild_held_ms` (the longest the screen's isolate was held meanwhile) | ms | 30–125 | 250 |

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

| key | what | measured | limit |
|---|---|---|---|
| `rebuild_100k_ms` | every posting thrown away and posted afresh from the records, as the app does it on first opening: decoding, mapping and posting on worker isolates (`journalSlices` at once), written in one transaction with the indexes made after and the mark last (`EncryptedDatabase.postApart`) | 2,610 / 2,875 / 2,669 ms (quiet), up to 3,792 under load | 6,000 ms |
| `rebuild_held_ms` | the longest the screen's isolate was held meanwhile (`test/support/held.dart`) | 27 / 35 / 43 ms, up to 122 under load | 250 ms |
| `save_posting_us` | one entry's posting and the journal's mark, one transaction, `synchronous=FULL` | 536 / 574 / 882 µs, one run 2,279 under load | 3,000 µs |
| `every_balance_us` | every account's balance today, from the months' sums and this month's postings | 955 / 538 / 520 µs | 2,000 µs |
| `month_report_us` | a month's income and spending by category | 89 / 44 / 52 µs | 130 µs |

Measured 2026-11-24 after D51 (before it: the rebuild 11,788 / 12,698 /
12,157 ms in the screen's isolate, 1,000 intents a transaction, limit
26,000 ms; every balance 1,611 / 1,048 / 1,454 µs, limit 3,500 µs). Where
the rebuild's time goes at 100k (one isolate, JIT): decoding the records
350–500 ms, making entries 170–330, mapping 160–300, posting 450–900; in
SQL intents and streams 190–280, postings 290–550, the indexes made after
420–720, the months' sums 54–120, the commit 400–600. The workers
overlap the first four; the SQL write is the floor that is left.

The save gate (`save_scale_gate_test.dart`) counts the journal's update in
the save it times, so a journal update that grows with the book fails it in
CI on any machine. Posting the whole book afresh happens once (the first
opening after this version, after a restore, after an older version wrote
records, or when the posting rules change). `journal_rebuild_gate_test.dart`
gates, in the ordinary `flutter test`, the longest hold of the screen's
isolate while a 20,000-entry book is posted afresh, as a share of posting
it at once there (at most 0.045, as the batch-write gate below).

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
