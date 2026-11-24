// The journal kept change by change equals the book posted afresh after
// every change (review 9's random operations, kept).
import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../../../baseline/baseline_ledger.dart';

import '../journal/posted_book.dart';
import '../../../scenarios/ledger/journal/awkward_book.dart' show keptClock;

String line(Posting p) =>
    '${p.account.value} ${p.amount} ${p.currency.value} ${p.date.ymd} q${p.quantity} ${p.sub}';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('inc-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<String?> compare(
    Ledger ledger,
    EncryptedDatabase store,
    bool ignoreSeqOrder,
  ) async {
    final fresh = await post(ledger);
    final ids = <String>{
      for (final e in ledger.entries.all) e.id,
      for (final a in ledger.accounts.all) 'opening:${a.id}',
      for (final h in (ledger.holdings as dynamic).start as List<Holding>)
        'position:${h.code}',
    };
    for (final id in ids) {
      final a = [
        for (final p in fresh.store.postingsOfIntent(IntentId(id))) line(p),
      ];
      final b = [
        for (final p in store.journal.postingsOfIntent(IntentId(id))) line(p),
      ];
      if (a.join('|') != b.join('|')) {
        return 'intent $id\n fresh: ${a.join(' | ')}\n kept:  ${b.join(' | ')}';
      }
    }
    if (fresh.store.intentCount != store.journal.intentCount) {
      return 'intent count ${fresh.store.intentCount} vs ${store.journal.intentCount}';
    }
    if (fresh.store.postingCount != store.journal.postingCount) {
      return 'posting count ${fresh.store.postingCount} vs ${store.journal.postingCount}';
    }
    return null;
  }

  test('incremental journal equals a fresh posting after every change', () async {
    final failures = <String>[];
    var ops = 0;
    final kinds = <String, int>{};
    for (var seed = 1; seed <= 60; seed++) {
      final file = File('${scratch.path}/s$seed.db');
      final store = EncryptedDatabase.open(file, StorageKey.random());
      final source = SqlLedgerDataSource(
        store,
        clock: keptClock,
        keepsJournal: true,
      );
      final ledger = await source.load();
      await source.journal.settled;
      final r = Random(seed);
      for (final a in const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('cash', '現金', AccountKind.cash, 0),
        Account('usd', '美元', AccountKind.bank, 50000, currency: 'USD'),
        Account('card', '卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
        Account(
          'ucard',
          '美元卡',
          AccountKind.card,
          0,
          currency: 'USD',
          closingDay: 10,
          dueDay: 25,
        ),
      ]) {
        ledger.accountCommands.addAccount(a);
      }
      await ledger.settled;
      await source.journal.settled;
      var n = 0;
      int pick(int lo, int hi) => lo + r.nextInt(hi - lo + 1);
      T of<T>(List<T> xs) => xs[r.nextInt(xs.length)];
      Entry make(String id) {
        final d = day(2026, 8, 1).add(Duration(days: r.nextInt(70)));
        final k = r.nextInt(100);
        final h = ledger.holdings.byCode('A')?.shares ?? 0;
        if (k < 30) {
          final acct = of(['bank', 'card', 'ucard', 'usd', 'cash']);
          final f = acct == 'ucard' || acct == 'usd';
          return entryOf(
            id,
            d,
            EntryType.expense,
            pick(2, f ? 9000 : 3000),
            acct,
            category: of(['飲食', '購物']),
            installments:
                (acct == 'card' || acct == 'ucard') && r.nextInt(3) == 0
                ? of([2, 3, 6])
                : 0,
            home: f ? pick(1, 300) : null,
          );
        } else if (k < 40) {
          return entryOf(
            id,
            d,
            EntryType.income,
            pick(1, 9000),
            'bank',
            category: '薪水',
          );
        } else if (k < 55) {
          return entryOf(
            id,
            d,
            EntryType.transfer,
            pick(1, 3000),
            of(['bank', 'cash']),
            to: of(['card', 'bank', 'cash'].where((x) => true).toList()),
          );
        } else if (k < 75) {
          return entryOf(
            id,
            d,
            EntryType.buy,
            pick(10, 900),
            'bank',
            holding: 'A',
            shares: pick(1, 5),
            fee: pick(0, 9),
            category: 'x',
          );
        } else if (k < 85 && h > 0) {
          return entryOf(
            id,
            d,
            EntryType.sell,
            pick(10, 900),
            'bank',
            holding: 'A',
            shares: pick(1, min(h, 3)),
            fee: 1,
            tax: 1,
            average: r.nextBool(),
            category: 'x',
          );
        } else if (k < 92 && h > 0) {
          return entryOf(
            id,
            d,
            EntryType.dividend,
            pick(0, 500),
            'bank',
            holding: 'A',
            shares: -pick(1, min(h, 3)),
            category: 'x',
          );
        } else {
          return entryOf(
            id,
            d,
            EntryType.dividend,
            pick(1, 500),
            'bank',
            holding: 'A',
            category: 'x',
          );
        }
      }

      for (var step = 0; step < 40; step++) {
        final op = r.nextInt(100);
        String what;
        try {
          if (op < 55 || ledger.entries.all.length < 5) {
            final e = make('e${n++}');
            what =
                'add ${e.id} ${e.type.name} ${e.account}${e.to != null ? '->${e.to}' : ''} ${e.date.toIso8601String().substring(5, 10)} amt${e.amount} sh${e.shares} inst${e.installments}';
            ledger.entryCommands.add(e);
          } else if (op < 75) {
            final old = of(ledger.entries.all.toList());
            final ne = make(old.id);
            what =
                'replace ${old.id} (${old.type.name}) -> ${ne.type.name} ${ne.account} ${ne.date.toIso8601String().substring(5, 10)} amt${ne.amount} sh${ne.shares} inst${ne.installments}';
            ledger.entryCommands.replace(ne);
          } else if (op < 88) {
            final old = of(ledger.entries.all.toList());
            what =
                'remove ${old.id} (${old.type.name} ${old.account} ${old.date.toIso8601String().substring(5, 10)})';
            ledger.entryCommands.remove(old.id);
          } else if (op < 95) {
            final card = ledger.accounts.all.firstWhere(
              (a) => a.id == of(['card', 'ucard']),
            );
            final cd = pick(1, 28);
            what = 'card ${card.id} closing->$cd';
            ledger.accountCommands.updateAccount(
              card.copyWith(closingDay: cd, dueDay: pick(1, 28)),
            );
          } else {
            final a = ledger.accounts.all.firstWhere(
              (a) => a.id == of(['bank', 'cash', 'card']),
            );
            final o = pick(-500, 5000);
            what = 'opening ${a.id}->$o';
            ledger.accountCommands.updateAccount(
              Account(
                a.id,
                a.name,
                a.kind,
                o,
                closingDay: a.closingDay,
                dueDay: a.dueDay,
                history: a.history,
                closes: a.closes,
              ),
            );
          }
        } catch (_) {
          continue;
        }
        await ledger.settled;
        await source.journal.settled;
        final msg = await compare(ledger, store, true);
        if (msg != null) {
          failures.add('seed $seed step $step: $what\n$msg');
          break;
        }
        ops++;
        kinds[what.split(' ').first] = (kinds[what.split(' ').first] ?? 0) + 1;
        if (source.journal.lastParity is OutOfParity) {
          failures.add(
            'seed $seed step $step: $what -> keeper parity: ${(source.journal.lastParity as OutOfParity).differences.take(3).join('; ')}',
          );
          break;
        }
      }
      store.close();
    }
    expect(ops, greaterThan(1000), reason: '$kinds');
    expect(failures, isEmpty, reason: failures.take(5).join('\n---\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
