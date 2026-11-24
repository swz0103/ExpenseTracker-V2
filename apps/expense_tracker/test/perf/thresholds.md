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

## Opening a large book (`open_gate_test.dart`, after CORR-2 and FIX-R13)

`100k_load_ms` went from 1,000–1,600 ms (16ffb7a and before) to 1,887–2,174
ms on the CI emulator (c172444 … e05adbf), over its 1,700 ms limit. The
emulator has about two cores and the opening runs on a worker isolate
(`openingWork`, `EncryptedDatabase.workApart`), so the host was pinned to
two cores (`taskset -c 0,1`) for these figures. The development VM was
shared with other runs at the time (load 3–12 on four cores), so each
figure is the least of four loads, two runs each; flutter test, JIT.

Where an opening of the bench's 100,000 entries went (65f9d4b, two cores,
least / median of nine loads): reading the rows 436 / 565 ms (SQLCipher;
reading by cursor and column index was no faster); decoding the JSON
480–690; bringing records up (`upgradeRecord`) 100–200, of it the D80
kept-category check about 40; making the entries 430–500 (`entryFromJson`
305, the shape rules 61, the names 28, finding each row's record in a map
by row 37); the holdings 14–60; a map of each entry's place by id 28–275,
built on every opening, handed to the screen's isolate and kept there, but
read only by a posting the app never does there; handing the book back
(`Isolate.exit`) 71 / 155; the ledger made of it 4 / 6. At c172444 the
screen's isolate also built a map of 100,000 places by id
(`EntryRepository`, 84–250 ms, the longest hold 74–156 ms against 31–54
at 16ffb7a); PERF (8838491) put the places beside the entries instead.
FIX-R13 added nothing that grows with the book to `load()` (a loop check of
the categories, three more maps of the market row). Nothing of CORR-2's
recurring rules runs in `load()`: `bookDue` runs after it, at
`LedgerSession.start`, and reads every entry once (cached), not once per
item. The emulator's 10k and small-book save figures rose in the same run
as its 100k one (124 → 166 ms, 4 → 4.9 ms a frame) with no change on
those paths: that run was slower throughout.

What was changed: the map of places by id is gone (the journal posts each
entry at the place beside it); what entries repeat (accounts, categories
kept by name, merchants, stocks, tags, days) is one copy for the book
(`SameValues`, about 300,000 objects fewer to hand back and to collect);
no list or map is made per entry for nothing (tags and parts with none,
the marks' names); the records are kept by shelf beside their rows, not in
a map by row; and from 20,000 entries (`splitOpeningFrom`) half of the
entries' JSON is decoded on a second worker at once when there is a core
for it.

| commit | 100k load, two cores (least, two runs) | CPU used (median) |
|---|---|---|
| 16ffb7a | 1,651 / 1,741 ms | 2,700 / 2,840 ms |
| c172444 | 1,895 / 1,809 ms | 2,870 / 2,900 ms |
| 65f9d4b | 1,575 / 1,915 ms | 2,410 / 3,260 ms |
| e05adbf | 1,596 / 1,741 ms | 2,490 / 3,040 ms |
| this change | 1,281 / 1,532 ms | 2,240 / 2,360 ms |

At 10,000 entries (no second worker): e05adbf 108–178 ms, CPU 340–380;
this change 100–147 ms, CPU 230–260. The second worker alone: 55–100 ms
less at 100k, about 100–200 ms more CPU.

The gate runs in the ordinary `flutter test`: a book of 100,000 entries
(the bench's mix) opened three times through `SqlLedgerDataSource.load`,
which times itself and the worker's part (`lastOpening`). It gates two
shares, the least of the three openings each, so it holds on any machine
and core count:

| share | measured (2 cores; 4 cores) | limit |
|---|---|---|
| the longest hold of the screen's isolate, of the opening | 0.013–0.018; 0.013; 0.041 in a full run on a machine at load 12 | 0.08 (about twice the full run's) |
| the opening spent outside the worker's own work (starting it, the hand-back, the ledger made here) | 0.042–0.046; 0.042; 0.031 in the full run | 0.06 |

A map of 100,000 places built here again measured 0.064; the hand-back of
65f9d4b's book (its map by id included) about 0.05–0.09.

### What the gate checks besides its shares (review 24)

Review 24 found that the two shares did not catch the regressions they
were there for: with the second worker lost (`helpers: 0`) the gate
passed, and with `SameValues` lost the outside share rose only to 0.049,
under its 0.06. The gate now also:

- checks that, with a core beside the worker's, the last half of the
  entries was decoded on a second worker (`lastOpening.split`, reported
  by `openingWork`);
- checks that what entries repeat is one object for each value (accounts,
  notes, merchants, tags, days: as many identities as distinct values);
- limits the worker's own time (`workerUs`, least of three) to 2,600 ms,
  about twice the least measured here (1,299 ms);
- opens the book once more with the journal kept, as the app does (the
  book sent as a copy, then posted on the worker), and checks the mark
  and that every entry was posted.

Measured 2026-11-24 (FIX-R24) on the development VM at load 5–9 on four
cores (other agents' runs; a quiet host was not to be had), flutter
test JIT, not pinned; each figure the least of three openings:

| | worker's own time | outside share | gate |
|---|---|---|---|
| as it is (split, `SameValues`) | 1,269–1,933 ms (8 runs) | 0.027–0.037 | passes |
| second worker lost (`split: false` in `_openApart`) | 1,394 / 1,664 ms | 0.035 / 0.037 | fails: "half the entries on a second worker" |
| `SameValues` lost (`entryFromJson(j, refs)` in `decodeBook`) | 1,541 / 1,706 ms | 0.048 / 0.051 | fails: "accounts shared" (100,000 for 2) |

At this load the worker's time with and without the second worker
overlaps (as review 24 found), so the split is gated by what it leaves,
not by its time; the time limit catches a gross slowing only.

Each half building its entries on its own worker as well (review 24,
item 3: `entryFromJson`, the shape rules and the names there, each half
with its own `SameValues`, the second half's values made one with the
first's after) was tried and not kept: alternated with the change above
on the gate's book, four runs each at load 7–9, the worker's least time
was 1,269–1,933 ms (median about 1,490) without it and 1,498–1,763 ms
(median about 1,610) with it. The experiment is on the local branch
`r24-entry-halves-experiment`, to be measured again on a quiet host or a
phone.

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
| `parity_held_ms` | the same gate's longest hold itself, in ms (review 18): the share stays the same as the book grows, the hold does not, so both are gated. Twice the slowest quiet run, 110 ms, as the rule above. Since review 23 (review 25 finding 8) both are judged on the clean pairs only: the median share and the median sliced hold of the pairs the host did not stall, so an absolute ms figure is no longer read on a busy host | — | 84 ms (2026-11-24, r13); 110 ms (review 18); 95–186 ms (three runs, load 7–10, 2026-11-24, not a basis) | 220 ms |
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
(`journal_rebuild_block`) gates the longest hold of the screen's isolate
while a 50,000-entry book is posted afresh, as a share of posting it at
once there, judged as every share gate is (below, "How a timing gate is
judged").

| measured | limit |
|---|---|
| 20,000 entries, before review 23 (least of three, full runs): 0.042 pass, 0.056 fail; no quiet figure was ever taken, the limit was copied from the batch writes | 0.045 |
| 50,000 entries, no quiet run yet: the host stayed at load 5.7–12 on four cores, every sample's PSI 4.6–76% (2026-11-24, six runs of nine pairs, every pair contended, not a basis). Ratios 0.007–0.096; the median of each run's nine 0.014, 0.017, 0.018, 0.019, 0.019, 0.022; at once held 1,519–2,425 ms, apart 17–150 ms | 0.045 |

The book went from 20,000 to 50,000 entries (review 23): posting at once
grows with the book, the hold apart (one slice of the work, a hand-over)
does not, so the same limit has room instead of sitting next to one 8 ms
slice. The limit was not raised.

## How a timing gate is judged (review 23)

The gates below, the journal's, the opening's, the save's, the index's,
the page's and the scale scenario are tagged `timing` (dart_test.yaml).
CI and `tooling/run-host-checks.ps1` run the rest of the app's suite at
the default concurrency with coverage, then
`flutter test --tags timing --concurrency=1` without coverage (coverage
slows the code measured and distorts the ratios). A plain `flutter test`
still runs them all.

A share gate (`journal_rebuild_block`, `batch_write_block`,
`import_block`, `backup_read_block`, `parity_held`) is judged in
`test/support/held.dart`:

- **One timer**: `timeHeld`, a 1 ms timer whose widest gap is the hold,
  in µs, settled 20 ms before and after.
- **A witness of the host around each sample.** On Linux the PSI `some`
  total of `/proc/pressure/cpu` (time some runnable task waited for a
  core) and the steal ticks of `/proc/stat`; elsewhere a fixed loop of
  about 3 ms timed before and after, against the fastest seen. A sample
  is contended past 5% PSI of its wall time, 1% steal, or a loop 1.5
  times its fastest. The one-minute load per core is printed, not
  judged.
- **Interleaved pairs**: apart, then at once, five times; each ratio from
  two runs a moment apart, so a slow drift of the host's load falls on
  both. A pair either of whose samples is contended is dropped.
- **The verdict**: the median ratio of at least three clean pairs against
  the limit (and for `parity_held` also the median hold of the clean
  sliced runs against `parity_held_ms`). When the verdict is not a pass
  and at least half the pairs were contended, pairs are taken on to nine
  and all clean ones judged together; a failure on clean pairs gets no
  second chance. Fewer than three clean pairs is `INCONCLUSIVE: host
  contended (n of m samples clean)`, with every figure: a failure under
  `CI`, a loud skip elsewhere, never a pass. The contention filter only
  drops samples: a hold the code makes appears in every sample, the
  clean ones included.
- Every pair's figures, the witness's with them, are printed with every
  result, pass or fail.

Figures taken on a host at load 7 and more (on four cores) are not a
basis for a limit; the quiet figures below were taken with PSI under
5% throughout.

Five quiet runs of the journal gate were to set its limit at about twice
the worst (never above 0.045). None could be taken on 2026-11-24: the
development host stayed at load 5.7–12 on four cores, and the witness
marked every one of 99 pairs across the share gates contended. The limit
stays 0.045 until five quiet runs exist; the figures under load (table
above) suggest the quiet share at 50,000 entries is well under it. The
same day, under that load (every pair contended, not a basis):

| gate | ratios of nine pairs | apart held |
|---|---|---|
| `batch_write_block` | 0.014–0.171 | 20–226 ms |
| `import_block` | 0.007–0.301 | 25–696 ms |
| `backup_read_block` | 0.040–0.304 | 18–176 ms |
| `parity_held` | 0.214–0.436 | 98–161 ms (limit 220) |

## Batch writes on the computer (`batch_write_block`, DAT-03)

Not an emulator figure: `test/perf/batch_write_gate_test.dart` runs in the
ordinary `flutter test`. It renames the merchant of 20,000 entries of a real
encrypted book twice: once written at once, and once as the app writes a
change of 500 records or more (`writeApartFrom`: the rows made 8 ms at a
time with the screen drawn between, then kept on a worker isolate through
the same connection, `EncryptedDatabase.writeApart`). It gates the longest
time the main isolate was held, as a share of the rename written at once,
so the gate holds on any machine; judged as above ("How a timing gate is
judged"), with the shared timer in µs (the gate's own ms timer is gone).

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
the longest time the main isolate was held, as a share of the import at
once, with the batch writes' limit (judged as above, "How a timing gate is
judged"; the figures below are of the former least of three).

| measured (4 runs, Linux host, 2026-11-24) | limit |
|---|---|
| at once: held 2,101–2,768 ms; apart: held 17–26 ms; share 0.008–0.011 | 0.045 (the batch writes') |

What is left held is the garbage collection of the 100,000 entries made.

## A backup's read on the computer (`backup_read_block`, D41)

Not an emulator figure: `test/perf/backup_read_gate_test.dart` runs in the
ordinary `flutter test`. It backs up a real encrypted book of 100,000
records as the app does (`LedgerBackup.write`: the records read
in one read transaction on a worker isolate through the same connection,
`EncryptedDatabase.readApart`, then compressed and sealed on that worker),
and gates the longest time the main isolate was held as a share of the
same records read on the main isolate at once, as the backup read them
before: since review 23 in interleaved pairs, a read at once beside each
backup (no longer one read for five backups, which a lucky-short read
could fail), judged as above. Read there, the share would be 1 or more.
The figures below are of the former middle of five.

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
entries' indexes out afresh (the least of three runs) after a warm-up,
each change the least of fifteen tries (review 23: tens of µs each, so a
try a busy host preempts is likely, all fifteen are not).
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

`sale_cost_gate_test.dart` (review 19, 4.1): on a book of 100,000 entries,
3,000 of them trades of twenty stocks, the sale form's 已實現損益 cost after
a change of the shares (worked out again from the sold stock's own trades,
kept by the entries in book order) and read again with nothing changed
(kept), each as a share of the old way, every entry before the sale
replayed whole; the least of three runs. Before, that whole replay ran on
every rebuild of the form, the fold closed or not. That the stock's own
trades give the same cost as all of them is proved in
`test/features/entries/model/compose_form_trade_test.dart`.

| measured (7 runs, Linux host, 2026-11-24) | limit |
|---|---|
| whole 16.7–37.6 ms; a change of the shares 0.68–2.6 ms (worst share 0.086); kept 1–3 µs (worst share 0.00008) | changed 0.2 (about 2× the worst); kept 0.0005 (about 2× the worst, and no less than 1 µs over a 2 ms replay) |

`rebuild_gate_test.dart`: 總覽 builds 79 widgets after a budget changes
(was 153), its title row following the entries rather than the whole
ledger.
