import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/categories/model/project.dart';
import 'package:expense_tracker/src/features/reports/model/comparison.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  Entry entry(
    String id,
    DateTime date,
    int amount, {
    EntryType type = EntryType.expense,
    String category = '飲食',
    List<String> tags = const [],
  }) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: 'bank',
    category: category,
    tags: tags,
  );

  final ledger = Ledger(
    today: DateTime.utc(2026, 10, 20),
    accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
    categories: const [],
    entries: [
      entry('a', DateTime.utc(2026, 9, 3), 300),
      entry('b', DateTime.utc(2026, 9, 10), 1200, category: '交通', tags: const ['花蓮']),
      entry('c', DateTime.utc(2026, 9, 12), 800, category: '住宿', tags: const ['花蓮']),
      entry('s', DateTime.utc(2026, 9, 25), 50000, type: EntryType.income, category: '薪資'),
      entry('d', DateTime.utc(2026, 10, 2), 500),
      entry('e', DateTime.utc(2026, 10, 15), 400, category: '交通'),
    ],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

  test('two stretches side by side, the largest difference first', () {
    final october = sumsBetween(
      ledger,
      DateTime.utc(2026, 10),
      DateTime.utc(2026, 10, 20),
    );
    final september = sumsBetween(
      ledger,
      DateTime.utc(2026, 9),
      DateTime.utc(2026, 9, 30),
    );
    expect(october.expense, 900);
    expect(september.income, 50000);
    final rows = compare(october, september);
    expect(rows.take(3), [
      ('收入', 0, 50000),
      ('支出', 900, 2300),
      ('結餘', -900, 47700),
    ]);
    expect(rows.skip(3), [
      ('住宿', 0, 800),
      ('交通', 400, 1200),
      ('飲食', 500, 300),
    ]);
  });

  test('a tag as a project: when it ran, what it cost, on what', () {
    final trip = projectOf(ledger, '花蓮')!;
    expect(trip.from, DateTime.utc(2026, 9, 10));
    expect(trip.to, DateTime.utc(2026, 9, 12));
    expect(trip.days, 3);
    expect(trip.spent, 2000);
    expect(trip.perDay, 666);
    expect(trip.byCategory, [('交通', 1200), ('住宿', 800)]);
    expect([for (final e in trip.entries) e.id], ['c', 'b']);
    expect(projectOf(ledger, '沒有'), isNull);
  });
}
