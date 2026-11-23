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
