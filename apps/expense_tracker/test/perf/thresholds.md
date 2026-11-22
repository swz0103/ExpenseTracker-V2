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
| `load_ms` | ms | 15 / 72 / 838 | 30 / 150 / 1,700 |
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
