// A purchase in instalments and up to two refunds of it, changed in
// any order: the journal kept change by change must equal the book posted
// afresh (a refund's cancelled instalments depend on the purchase and on the
// other refunds, whether or not it was itself in the card's stream).
import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../../../baseline/baseline_ledger.dart';
import '../../../core/ledger/journal/posted_book.dart';
import 'awkward_book.dart' show keptClock;

String line(Posting p) =>
    '${p.account.value} ${p.amount} ${p.currency.value} ${p.date.ymd} q${p.quantity} ${p.sub}';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('r14-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<String?> compare(Ledger ledger, EncryptedDatabase store) async {
    final fresh = await post(ledger);
    final ids = {for (final e in ledger.entries.all) e.id, 'p', 'r1', 'r2'};
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
    return null;
  }

  Entry purchase(int inst, {int amount = 1200}) => entryOf(
    'p',
    day(2026, 8, 10),
    EntryType.expense,
    amount,
    'card',
    category: '飲食',
    installments: inst,
  );
  Entry refund(String id, int amount, int d, {int month = 9}) => entryOf(
    id,
    day(2026, month, d),
    EntryType.income,
    amount,
    'card',
    category: '飲食',
    refundOf: 'p',
  );

  Future<(Ledger, SqlLedgerDataSource, EncryptedDatabase)> open(
    String name,
  ) async {
    final store = EncryptedDatabase.open(
      File('${scratch.path}/$name.db'),
      StorageKey.random(),
    );
    final source = SqlLedgerDataSource(
      store,
      clock: keptClock,
      keepsJournal: true,
    );
    final ledger = await source.load();
    await source.journal.settled;
    ledger.accountCommands
      ..addAccount(const Account('bank', '銀行', AccountKind.bank, 10000))
      ..addAccount(
        const Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 5,
          dueDay: 20,
        ),
      );
    await ledger.settled;
    await source.journal.settled;
    return (ledger, source, store);
  }

  test('hand cases: the instalments given to a refund already kept', () async {
    final cases = <String, List<(String, void Function(Ledger))>>{
      'a plain purchase refunded, then made instalments': [
        ('buy plain', (l) => l.entryCommands.add(purchase(0))),
        ('refund', (l) => l.entryCommands.add(refund('r1', 600, 20))),
        ('purchase in 12', (l) => l.entryCommands.replace(purchase(12))),
      ],
      'full refund first, then a later partial one, then the full one goes': [
        ('buy 12', (l) => l.entryCommands.add(purchase(12))),
        ('r1 full', (l) => l.entryCommands.add(refund('r1', 1200, 20))),
        ('r2 later', (l) => l.entryCommands.add(refund('r2', 300, 25))),
        ('r1 gone', (l) => l.entryCommands.remove('r1')),
      ],
      'refund dated after a later one by editing': [
        ('buy 12', (l) => l.entryCommands.add(purchase(12))),
        ('r1', (l) => l.entryCommands.add(refund('r1', 700, 20))),
        ('r2', (l) => l.entryCommands.add(refund('r2', 700, 25))),
        (
          'r1 moves after r2',
          (l) => l.entryCommands.replace(refund('r1', 700, 28, month: 10)),
        ),
      ],
      'purchase edited to fewer instalments with refunds kept': [
        ('buy 12', (l) => l.entryCommands.add(purchase(12))),
        ('r1', (l) => l.entryCommands.add(refund('r1', 500, 20))),
        ('r2', (l) => l.entryCommands.add(refund('r2', 400, 25))),
        ('buy 3', (l) => l.entryCommands.replace(purchase(3))),
        ('buy 0', (l) => l.entryCommands.replace(purchase(0))),
        ('buy 6', (l) => l.entryCommands.replace(purchase(6))),
      ],
      'purchase removed and put back': [
        ('buy 12', (l) => l.entryCommands.add(purchase(12))),
        ('r1', (l) => l.entryCommands.add(refund('r1', 500, 20))),
        ('purchase gone', (l) => l.entryCommands.remove('p')),
        ('purchase back', (l) => l.entryCommands.add(purchase(12))),
      ],
    };
    final failures = <String>[];
    var n = 0;
    for (final MapEntry(key: name, value: steps) in cases.entries) {
      final (ledger, source, store) = await open('c${n++}');
      for (final (what, step) in steps) {
        try {
          step(ledger);
        } catch (_) {
          continue;
        }
        await ledger.settled;
        await source.journal.settled;
        final msg = await compare(ledger, store);
        if (msg != null) {
          failures.add('$name / $what\n$msg');
          break;
        }
      }
      store.close();
    }
    expect(failures, isEmpty, reason: failures.join('\n---\n'));
  });

  test('random orders of changes to a purchase and two refunds', () async {
    final failures = <String>[];
    for (var seed = 1; seed <= 80; seed++) {
      final r = Random(seed);
      final (ledger, source, store) = await open('s$seed');
      for (var step = 0; step < 14; step++) {
        final k = r.nextInt(100);
        String what;
        try {
          if (k < 30) {
            final inst = [0, 2, 3, 12][r.nextInt(4)];
            what = 'p->$inst';
            ledger.entries.byId('p') == null
                ? ledger.entryCommands.add(
                    purchase(inst, amount: [1200, 900, 600][r.nextInt(3)]),
                  )
                : ledger.entryCommands.replace(
                    purchase(inst, amount: [1200, 900, 600][r.nextInt(3)]),
                  );
          } else if (k < 75) {
            final id = r.nextBool() ? 'r1' : 'r2';
            final e = refund(
              id,
              [100, 300, 700, 1200, 2000][r.nextInt(5)],
              1 + r.nextInt(27),
              month: 9 + r.nextInt(3),
            );
            what = '$id ${e.amount} ${e.date.month}/${e.date.day}';
            ledger.entries.byId(id) == null
                ? ledger.entryCommands.add(e)
                : ledger.entryCommands.replace(e);
          } else if (k < 90) {
            final id = ['p', 'r1', 'r2'][r.nextInt(3)];
            what = 'remove $id';
            if (ledger.entries.byId(id) != null)
              ledger.entryCommands.remove(id);
          } else {
            what = 'card closing';
            final c = ledger.accounts.all.firstWhere((a) => a.id == 'card');
            ledger.accountCommands.updateAccount(
              c.copyWith(closingDay: 1 + r.nextInt(27), dueDay: 28),
            );
          }
        } catch (_) {
          continue;
        }
        await ledger.settled;
        await source.journal.settled;
        final msg = await compare(ledger, store);
        if (msg != null) {
          failures.add('seed $seed step $step: $what\n$msg');
          break;
        }
      }
      store.close();
    }
    final kinds = <String, int>{};
    for (final f in failures) {
      final k = f
          .split('\n')
          .first
          .replaceAll(RegExp(r'seed \d+ step \d+: '), '')
          .split(' ')
          .first
          .replaceAll(RegExp(r'->.*'), '->');
      kinds[k] = (kinds[k] ?? 0) + 1;
    }
    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} seeds, by the change that broke it: $kinds\n${failures.take(2).join('\n---\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
