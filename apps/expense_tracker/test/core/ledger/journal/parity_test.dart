import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/modules.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/journal/valuation.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_loans/feature/loans_module.dart';
import 'package:ledger_postings/model/vocabulary.dart' show homeCurrency;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../../../baseline/baseline_ledger.dart';
import 'posted_book.dart';

/// The books each version of the app kept (test/fixtures/books), opened
/// as the app opens them.
const _books = 'test/fixtures/books';
const _password = 'fixture password';
final _clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

void printParity(String what, Parity p) {
  // ignore: avoid_print
  print(
    '$what: ${p.figures} figures, '
    '${p is OutOfParity ? p.differences.length : 0} differ; shapes ${p.shapes}',
  );
}

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('parity-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  final versions = [
    for (final d in Directory(_books).listSync().whereType<Directory>())
      d.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();

  for (final version in versions) {
    test('the book kept by $version: every figure from its postings', () async {
      final copy = Directory('${scratch.path}/vault')..createSync();
      for (final f in Directory('$_books/$version/vault').listSync()) {
        if (f is File) f.copySync('${copy.path}/${f.uri.pathSegments.last}');
      }
      final open = await LedgerVault(
        copy,
        codec: KeyringCodec(minimumPassword: 6),
      ).unlockWithPassword(_password);
      addTearDown(open.close);
      final ledger = await SqlLedgerDataSource(
        open.store,
        clock: _clock,
      ).load();
      expectGoldenPostings(version, await post(ledger));
      final parity = await parityOf(ledger);
      printParity(version, parity);
      expect(parity, isA<InParity>(), reason: _said(parity));
      expect(parity.figures, greaterThan(100));
      // The same from the file's own tables (D51's store), not only from
      // memory.
      open.store.journal.transaction(open.store.journal.clear);
      final kept = await parityOf(ledger, into: open.store.journal);
      expect(kept, isA<InParity>(), reason: _said(kept));
      expect(kept.figures, parity.figures);
    });
  }

  test('the demo book: every figure from its postings', () async {
    final parity = await parityOf(demoLedger());
    printParity('demo', parity);
    expect(parity, isA<InParity>(), reason: _said(parity));
    expect(parity.figures, greaterThan(1000));
    final file = EncryptedDatabase.open(
      File('${scratch.path}/demo.db'),
      StorageKey.random(),
    );
    addTearDown(file.close);
    final kept = await parityOf(demoLedger(), into: file.journal);
    expect(kept, isA<InParity>(), reason: _said(kept));
    expect(kept.figures, parity.figures);
  });

  test('the loans module\'s balance-sheet rows are compared with what the '
      'app counts, and an account two modules claim is caught', () async {
    final ledger = demoLedger();
    final b = await post(ledger);
    final parity = await checkParity(
      today: figuresOf(ledger),
      reader: b.reader,
    );
    expect(parity, isA<InParity>(), reason: _said(parity));
    final now = Day.of(BusinessDate.of(ledger.today));
    final sheet = b.reader.balanceSheet(now);
    expect(
      [for (final r in sheet.rows) (r.owner, r.row)],
      [
        (LoansModule.owner, LoansModule.loansRow),
        (LoansModule.owner, LoansModule.peopleRow),
      ],
    );
    // The demo's one loan, 車貸, opens at 286,000 owed; its payments
    // come after.
    expect(sheet.rows.first.accounts, [const AccountId('acct:car-loan')]);
    expect(sheet.rows.first.worth, lessThan(0));
    // A second module claiming the loans as well is a boundary to mend.
    final twice = valuedAsTheApp(
      holdings: ledger.holdings,
      market: ledger.marketData,
    );
    installModules(twice);
    twice
        .on(sheetClaims)
        .add(
          const OwnerId('other'),
          SheetClaim(row: 'other', claims: (a) => a.tag == 'loan'),
        );
    final caught = await checkParity(
      today: figuresOf(ledger),
      reader: BookReader(b.store, b.journal.accounts, twice, homeCurrency),
    );
    expect(
      (caught as OutOfParity).differences.map(
        (d) => (d.figure, d.app, d.postings),
      ),
      [(Figure.sheetClaims, 0, 1)],
    );
  });

  test('the check can fail: one intent taken away and it says where', () async {
    final ledger = demoLedger();
    final b = await post(ledger);
    final lunch = ledger.entries.all.firstWhere(
      (e) => e.type.name == 'expense' && e.installments < 2,
    );
    expect(b.journal.delete(IntentId(lunch.id)), isA<Written>());
    final parity = await checkParity(
      today: figuresOf(ledger),
      reader: b.reader,
    );
    final out = parity as OutOfParity;
    expect(
      out.differences.map((d) => (d.figure, d.subject)),
      contains((Figure.balance, lunch.account)),
    );
  });

  test('the check offers a pause between each piece of its work, counted, '
      'not timed (review 23)', () async {
    // 30 entries, entry i on account i % 3 and i % 10 days before today:
    // as 3 and 10 share no factor, each account has an entry on each of
    // the 10 days, 2026-09-25 to 2026-10-04.
    final today = day(2026, 10, 4);
    final ledger = ledgerOf(
      today: today,
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('cash', '現金', AccountKind.cash, 500),
        Account('card', '卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
      ],
      categories: [Category('飲食', 'food', 0xFF111111)],
      entries: [
        for (var i = 0; i < 30; i++)
          entryOf(
            'e$i',
            today.subtract(Duration(days: i % 10)),
            EntryType.expense,
            10 + i,
            ['bank', 'cash', 'card'][i % 3],
            category: '飲食',
          ),
      ],
    );
    final posted = await post(ledger);
    var offered = 0;
    final parity = await checkParity(
      today: figuresOf(ledger),
      reader: posted.reader,
      pause: () async {
        offered++;
        await Future<void>.delayed(Duration.zero);
      },
    );
    expect(parity, isA<InParity>(), reason: _said(parity));
    // 30 (one per entry, the days each account changes on)
    // + 3 accounts x (1 before its sums + 10 days + 1 after) = 36
    // + 2 the opening balances of the bank and the cash, posted before
    //   every day (the card opens at 0)
    // + 2 months (September, October) + 0 stocks + 1 card's statement
    // + 1 the book's worth + 1 the modules' balance-sheet rows
    // + 1 the currencies' sum = 74.
    expect(offered, 74);
    // A regression that stops offering pauses (or offers one per account
    // only) falls far below the count.
  });
}

String _said(Parity p) => switch (p) {
  InParity() => '',
  OutOfParity(:final differences) => differences.take(20).join('\n'),
};
