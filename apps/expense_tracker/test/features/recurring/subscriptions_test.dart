import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/subscriptions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  test('訂閱總覽: a year of each active spending item, dearest first', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 20),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: [
        const Recurring(
          id: 'n',
          name: 'Netflix',
          amount: 390,
          day: 5,
          account: 'bank',
          category: '娛樂',
        ),
        Recurring(
          id: 'i',
          name: '保險',
          amount: 12000,
          day: 1,
          account: 'bank',
          category: '保險',
          unit: RepeatUnit.year,
          start: DateTime.utc(2025, 3, 1),
        ),
        const Recurring(
          id: 's',
          name: '薪水',
          amount: 50000,
          day: 5,
          account: 'bank',
          category: '薪資',
          income: true,
        ),
        const Recurring(
          id: 'p',
          name: '暫停的健身房',
          amount: 999,
          day: 1,
          account: 'bank',
          category: '健身',
          active: false,
        ),
      ],
      journal: _Nowhere(),
    );
    final rows = yearlyCosts(ledger);
    expect([for (final (r, yearly) in rows) (r.name, yearly)], [
      ('Netflix', 390 * 12),
      ('保險', 12000),
    ]);
  });
}
