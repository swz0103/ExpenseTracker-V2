import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/commands/account_commands.dart';
import 'package:expense_tracker/src/core/ledger/commands/category_commands.dart';
import 'package:expense_tracker/src/core/ledger/commands/command_exceptions.dart';
import 'package:expense_tracker/src/core/ledger/commands/entry_commands.dart';
import 'package:expense_tracker/src/core/ledger/commands/recurring_commands.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:expense_tracker/src/core/ledger/repositories/budget_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/receipt_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/trash_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/book.dart';
import 'recording_context.dart';

/// The write side wired on a [Book], as the ledger wires it.
final class _Writes {
  _Writes(this.book, {List<Budget> budgets = const []})
    : budgets = BudgetRepository(budgets);

  final Book book;
  final BudgetRepository budgets;
  final trash = TrashRepository();
  final receipts = ReceiptRepository();
  late final context = RecordingContext(day, cache: book.cache);

  late final entries = EntryCommands(
    context: context,
    entryRepository: book.entries,
    accountRepository: book.accounts,
    categoryRepository: book.categories,
    holdingRepository: book.holdings,
    recurringRepository: book.recurring,
    budgetRepository: budgets,
    trashRepository: trash,
    receiptRepository: receipts,
    recurringService: book.recurringService,
    entryQueryService: book.queries,
    entryValidator: book.validator,
  );
  late final accounts = AccountCommands(
    context: context,
    accountRepository: book.accounts,
    entryRepository: book.entries,
    trashRepository: trash,
    recurringRepository: book.recurring,
    balanceService: book.balances,
  );
  late final categories = CategoryCommands(
    context: context,
    categoryRepository: book.categories,
    entryRepository: book.entries,
    trashRepository: trash,
    recurringRepository: book.recurring,
    budgetRepository: budgets,
  );
  late final recurring = RecurringCommands(
    context: context,
    recurringRepository: book.recurring,
    entryRepository: book.entries,
    accounts: book.accounts,
    recurringService: book.recurringService,
    entryCommands: entries,
  );
}

Entry _trade(String id, EntryType type, int shares, {int day = 1}) => Entry(
  id: id,
  date: DateTime.utc(2026, 9, day),
  type: type,
  amount: 1000,
  account: 'bank',
  holding: '2330',
  shares: shares,
);

const _rent = Recurring(
  id: 'rent',
  name: '房租',
  amount: 12000,
  day: 1,
  account: 'bank',
  category: '居家',
  auto: true,
);

void main() {
  group('EntryCommands', () {
    test('an entry added is kept with its photo, as one batch', () {
      final w = _Writes(Book());
      w.entries.add(entry('a'), receipt: 'a.jpg');
      expect(w.book.entries.byId('a'), isNotNull);
      expect(w.receipts.of('a'), 'a.jpg');
      expect(w.context.changes, [
        {Topic.entries},
      ]);
      final batch = w.context.batches.single;
      expect(batch.entries.single.id, 'a');
      expect(batch.receipts, {'a': 'a.jpg'});
    });

    test('a sale of shares not held is refused and leaves nothing', () {
      final w = _Writes(Book(entries: [_trade('buy', EntryType.buy, 5)]));
      expect(
        () => w.entries.add(_trade('sell', EntryType.sell, 9, day: 2)),
        throwsStateError,
      );
      expect(w.book.entries.all.map((e) => e.id), ['buy']);
      expect(w.book.holdings.byCode('2330')?.shares, 5);
      expect(w.context.batches, isEmpty);
    });

    test('a removal that would leave a sale short is told, not thrown', () {
      final w = _Writes(
        Book(
          entries: [
            _trade('buy', EntryType.buy, 5),
            _trade('sell', EntryType.sell, 5, day: 2),
          ],
        ),
      );
      expect(w.entries.remove('buy'), isNull);
      expect(w.context.problem.value, isA<SharesShort>());
      expect(w.book.entries.length, 2);
      expect(w.trash.all, isEmpty);
    });

    test('a booking removed goes to the trash and skips its day', () {
      final booked = entry(
        'r1',
        recurring: 'rent',
        amount: 12000,
        date: DateTime.utc(2026, 10, 1),
      );
      final w = _Writes(Book(entries: [booked], recurring: [_rent]));
      final removed = w.entries.remove('r1')!;
      expect(w.trash.all.single.entry.id, 'r1');
      expect(w.book.recurring.byId('rent')!.skipped, {
        DateTime.utc(2026, 10, 1),
      });
      final batch = w.context.batches.single;
      expect(batch.dropped, [(Collection.entry, 'r1')]);
      expect(batch.recurring.single.id, 'rent');

      expect(w.entries.restore(removed), isTrue);
      expect(w.book.entries.byId('r1'), isNotNull);
      expect(w.trash.all, isEmpty);
      expect(w.book.recurring.byId('rent')!.skipped, isEmpty);
    });

    test('a tag renamed reaches entries, the trash and its budget', () {
      final w = _Writes(
        Book(
          entries: [
            entry('a', tags: ['旅遊']),
            entry('b', tags: ['旅遊']),
          ],
        ),
        budgets: [Budget('#旅遊', 500)],
      );
      w.entries.remove('b');
      w.entries.renameTag('旅遊', '旅行');
      expect(w.book.entries.byId('a')!.tags, ['旅行']);
      expect(w.trash.all.single.entry.tags, ['旅行']);
      expect(w.budgets.all.single.category, '#旅行');
      final batch = w.context.batches.last;
      expect(batch.dropped, [(Collection.budget, '#旅遊')]);
      expect(batch.budgets.single.category, '#旅行');
    });
  });

  group('AccountCommands', () {
    test('an account still named anywhere is kept, one never used goes', () {
      final w = _Writes(
        Book(
          accounts: const [
            Account('bank', '銀行', AccountKind.bank, 0),
            Account('cash', '現金', AccountKind.cash, 0),
            Account('old', '舊帳戶', AccountKind.cash, 0),
          ],
          entries: [entry('a', account: 'cash')],
          recurring: [_rent],
        ),
      );
      expect(w.accounts.isUsed('cash'), isTrue);
      expect(w.accounts.isUsed('bank'), isTrue);
      w.accounts.removeAccount('cash');
      w.accounts.removeAccount('old');
      expect(w.book.accounts.all.map((a) => a.id), ['bank', 'cash']);
      expect(w.context.batches.single.dropped, [(Collection.account, 'old')]);
    });

    test('a balance set by hand moves the opening sum', () {
      final w = _Writes(Book(entries: [entry('a', amount: 300)]));
      w.accounts.setBalance('bank', 2000);
      expect(w.book.accounts.byId('bank')!.opening, 2300);
    });
  });

  group('CategoryCommands', () {
    test('a taken name is refused and told', () {
      final w = _Writes(Book(categories: [Category('飲食', 'food', 0)]));
      w.categories.addCategory(Category(' 飲食 ', 'food', 0));
      expect(w.context.problem.value, isA<NameTaken>());
      expect(w.book.categories.all, hasLength(1));
    });

    test('a merge moves every use and drops the category and its budget', () {
      final w = _Writes(
        Book(
          categories: [
            Category('飲食', 'food', 0, id: 'c1'),
            Category('吃飯', 'food', 0, id: 'c2'),
          ],
          entries: [entry('a', category: '吃飯')],
        ),
        budgets: [Budget('吃飯', 100)],
      );
      w.categories.mergeCategory('吃飯', '飲食');
      expect(w.book.entries.byId('a')!.category, '飲食');
      expect(w.budgets.all, isEmpty);
      final batch = w.context.batches.single;
      expect(batch.entries.single.id, 'a');
      expect(batch.dropped.toSet(), {
        (Collection.budget, '吃飯'),
        (Collection.category, 'c2'),
      });
    });
  });

  group('RecurringCommands', () {
    test('an automatic item books each day that came, once', () {
      final w = _Writes(Book(recurring: [_rent]));
      expect(w.recurring.bookDue(), 1);
      expect(w.recurring.bookDue(), 0);
      final booked = w.book.entries.all.single;
      expect(
        (booked.recurring, booked.date),
        ('rent', DateTime.utc(2026, 10, 1)),
      );
    });

    test('an item whose account is gone books nothing', () {
      final gone = _rent.copyWith(account: 'closed');
      expect(_Writes(Book(recurring: [gone])).recurring.bookDue(), 0);
    });
  });
}
