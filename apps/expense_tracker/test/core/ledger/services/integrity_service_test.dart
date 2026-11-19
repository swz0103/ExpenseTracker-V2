import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/trash_repository.dart';
import 'package:expense_tracker/src/core/ledger/services/integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

List<String> _found(Book book, {List<Trashed> trash = const []}) => [
  for (final p in IntegrityService(
    entries: book.entries,
    accounts: book.accounts,
    recurring: book.recurring,
    trash: TrashRepository(trash),
  ).problems())
    '$p ${p.id}',
];

void main() {
  test('a sound book has no problems', () {
    final bought = entry('bought', amount: 500);
    final book = Book(
      entries: [
        bought,
        entry('back', type: EntryType.income, amount: 100, refundOf: 'bought'),
        entry('move', type: EntryType.transfer, to: 'cash'),
      ],
    );
    expect(_found(book), isEmpty);
  });

  test('an entry paying from or into an account not kept is found', () {
    final book = Book(
      entries: [
        entry('a', account: 'gone'),
        entry('b', type: EntryType.transfer, to: 'gone too'),
      ],
    );
    expect(_found(book), [
      'MissingAccount(entry) a',
      'MissingAccount(entry) b',
    ]);
  });

  test('the trash and recurring items are looked over too', () {
    final book = Book(
      recurring: const [
        Recurring(
          id: 'rent',
          name: '房租',
          amount: 1,
          day: 1,
          account: 'gone',
          category: '居家',
        ),
      ],
    );
    expect(_found(book, trash: [Trashed(entry('t', account: 'gone'), day)]), [
      'MissingAccount(trash) t',
      'MissingAccount(recurring) rent',
    ]);
  });

  test('a refund of an entry no longer kept is found', () {
    final book = Book(
      entries: [entry('back', type: EntryType.income, refundOf: 'deleted')],
    );
    expect(_found(book), ['MissingRefundOriginal(entry) back']);
  });

  test('what goes to the log names the kind only', () {
    const problem = MissingAccount(RecordKind.entry, 'e-42', 'Amy 的帳戶');
    final kept = ErrorLog.describe(problem);
    expect(kept, contains('MissingAccount'));
    expect(kept, isNot(contains('Amy')));
    expect(kept, isNot(contains('42')));
  });
}
