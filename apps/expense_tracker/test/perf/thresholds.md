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
(Xeon, shared with other runs at the time, Flutter test JIT), three runs,
2026-11-23; each limit about twice the slowest run, rounded. Not measured
on a phone: expect two to four times these there.

| key | what | measured | limit |
|---|---|---|---|
| `rebuild_100k_ms` | every posting thrown away and posted afresh from the records, 1,000 intents a transaction (in the app 100, the screen drawn between) | 11,788 / 12,698 / 12,157 ms | 26,000 ms |
| `save_posting_us` | one entry's posting and the journal's mark, one transaction, `synchronous=FULL` | 784 / 1,495 / 853 µs | 3,000 µs |
| `every_balance_us` | every account's balance today, from the months' sums and this month's postings | 1,611 / 1,048 / 1,454 µs | 3,500 µs |
| `month_report_us` | a month's income and spending by category | 61 / 39 / 38 µs | 130 µs |

The save gate (`save_scale_gate_test.dart`) counts the journal's update in
the save it times, so a journal update that grows with the book fails it in
CI on any machine. Posting the whole book afresh happens once (the first
opening after this version, after a restore, or when the posting rules
change) and in the background; about a quarter of its time is the months'
sums, which could be built once at the end instead of with each posting.
