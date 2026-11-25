@Tags(['timing'])
library;

import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/trade_book.dart';

/// An ordinary save of a sale asks whether the book still holds its
/// shares (`EntryValidator.holdsWith`). Before FIX-R34 that replayed the
/// whole book with the sale: 4–6 ms a sale at 100,000 entries. Now only
/// the sale's own stock is replayed, every other one answered once until
/// a trade of it changes.
///
/// On the book of [tradeBook], [_saves] sales of the twenty stocks are
/// saved one after another; each is asked first, and timed, both the new
/// way and the old ([wholeBookHolds]), which must answer alike. The new
/// way is gated as a share of the old, the least of [gateTries] runs.
/// With `BENCH=1` the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;
  final today = tradeBookToday;

  test('a sale saved is held to its own stock', () async {
    Future<(int, int)> run() async {
      final ledger = tradeBook();
      final validator = ledger.entryValidator;
      final r = Random(5);
      var old = 0;
      var now = 0;
      final watch = Stopwatch();
      for (var i = 0; i < _saves; i++) {
        // A sale of up to 300 shares today: each stock holds 75,000.
        final sale = Entry(
          id: 'sale$i',
          date: today,
          type: EntryType.sell,
          amount: 1000,
          account: 'bank',
          holding: '${1101 + r.nextInt(20)}',
          shares: 1 + r.nextInt(300),
        );
        watch
          ..reset()
          ..start();
        final whole = wholeBookHolds(ledger, [sale]);
        old += watch.elapsedMicroseconds;
        watch
          ..reset()
          ..start();
        final holds = validator.holdsWith([sale]);
        now += watch.elapsedMicroseconds;
        expect(holds, whole, reason: sale.id);
        expect(holds, isTrue, reason: sale.id);
        ledger.entryCommands.add(sale);
      }
      expect(ledger.entries.length, 100000 + _saves);
      return (old, now);
    }

    var old = 1 << 62;
    var now = 1 << 62;
    for (var i = 0; i < gateTries; i++) {
      final (o, n) = await run();
      old = min(old, o);
      now = min(now, n);
    }
    if (bench) {
      // ignore: avoid_print
      print('$_saves saves: old $old µs; now $now µs');
    }
    expect(
      now / old,
      lessThanOrEqualTo(_most),
      reason:
          'asking $_saves saves took $now µs, the whole replay per save '
          '$old µs',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('prepared after the book opens, its first sale save replays only '
      'its own stock (PERF-3)', () async {
    final sale = Entry(
      id: 'sale',
      date: today,
      type: EntryType.sell,
      amount: 1000,
      account: 'bank',
      holding: '1105',
      shares: 10,
    );
    // The order of the entries worked out, as the month first shown does.
    Ledger opened() => tradeBook()..entries.inMonth(2026, 10);
    Future<(int, int, int)> run() async {
      final cold = opened();
      final watch = Stopwatch()..start();
      expect(cold.entryValidator.holdsWith([sale]), isTrue);
      final coldUs = watch.elapsedMicroseconds;
      final warm = opened();
      final step = Stopwatch();
      var longest = 0;
      void endStep() {
        if (step.elapsedMicroseconds > longest) {
          longest = step.elapsedMicroseconds;
        }
      }

      await warm.entryValidator.prepare(() async {
        endStep();
        step
          ..reset()
          ..start();
        return true;
      });
      endStep();
      watch
        ..reset()
        ..start();
      expect(warm.entryValidator.holdsWith([sale]), isTrue);
      return (coldUs, watch.elapsedMicroseconds, longest);
    }

    var cold = 1 << 62;
    var warm = 1 << 62;
    var step = 1 << 62;
    for (var i = 0; i < gateTries; i++) {
      final (c, w, s) = await run();
      cold = min(cold, c);
      warm = min(warm, w);
      step = min(step, s);
    }
    if (bench) {
      // ignore: avoid_print
      print('first save: cold $cold µs; prepared $warm µs; step $step µs');
    }
    expect(
      warm / cold,
      lessThanOrEqualTo(_preparedMost),
      reason: 'prepared $warm µs, cold $cold µs',
    );
    // No step of the preparing holds longer than the cold save did.
    expect(step / cold, lessThanOrEqualTo(_stepMost), reason: 'step $step µs');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// How many sales are saved.
const _saves = 40;

/// The largest share of the first save without preparing that the first
/// save after it may take: about twice the largest measured
/// (thresholds.md).
const _preparedMost = 0.1;

/// The largest share of that first save one step of preparing may take:
/// about twice the largest measured (thresholds.md).
const _stepMost = 0.35;

/// The largest share of the old way the check may take: about twice the
/// largest measured (thresholds.md).
const _most = 0.25;
