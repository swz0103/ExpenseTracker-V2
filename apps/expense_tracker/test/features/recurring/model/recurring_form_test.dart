import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/recurring_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  Ledger book() => Ledger(
    today: DateTime.utc(2026, 10, 4),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 5000),
      Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
    ],
    categories: [
      Category('居家', 'home', 0xFF5B8DB0),
      Category('薪資', 'income', 0xFF5C9A83, income: true),
    ],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Nowhere(),
  );

  test(
    'a new item needs an amount; without a name it takes the category\'s',
    () {
      final unnamed = book();
      final quiet = RecurringForm(unnamed)..amount = 500;
      expect(quiet.save(), isTrue);
      expect(unnamed.recurring.all.single.name, '居家');

      final ledger = book();
      final form = RecurringForm(ledger);
      expect(form.problem, '請輸入金額');
      form.name = '房租';
      form.amount = 15000;
      expect(form.save(), isTrue);
      final item = ledger.recurring.all.single;
      expect((item.name, item.amount, item.category), ('房租', 15000, '居家'));
      expect(item.day, 4);
    },
  );

  test(
    'income takes an income category; another currency clears the amount',
    () {
      final form = RecurringForm(book())
        ..amount = 300
        ..setIncome(true);
      expect(form.category, '薪資');
      form.setAccount('usd');
      expect(form.amount, 0);
      expect(form.currency, 'USD');
    },
  );

  test('an end before the start is refused, in the rule\'s words', () {
    final form = RecurringForm(book())..amount = 500;
    form.end = form.start.subtract(const Duration(days: 1));
    expect(form.problem, '結束日不能早於開始日');
    expect(form.save(), isFalse);
  });

  test('payments are at least one step apart', () {
    final form = RecurringForm(book())..step(-1);
    expect(form.every, 1);
    form
      ..step(1)
      ..step(1);
    expect(form.every, 3);
    expect(form.rhythm, '每 3 個月 4 日');
  });

  test('the day of the month moves the start to the next such day', () {
    final form = RecurringForm(book())..start = DateTime.utc(2026, 10, 20);
    form.setDayOfMonth(25);
    expect(form.start, DateTime.utc(2026, 10, 25));
    form.setDayOfMonth(5);
    expect(form.start, DateTime.utc(2026, 11, 5));
    // November has no 31st: December's.
    form.setDayOfMonth(31);
    expect(form.start, DateTime.utc(2026, 12, 31));
  });

  test('the weekday moves the start to the next such day', () {
    // 2026-10-20 is a Tuesday.
    final form = RecurringForm(book())..start = DateTime.utc(2026, 10, 20);
    form.setWeekday(5);
    expect(form.start, DateTime.utc(2026, 10, 23));
    form.setWeekday(5);
    expect(form.start, DateTime.utc(2026, 10, 23));
    form.setWeekday(1);
    expect(form.start, DateTime.utc(2026, 10, 26));
  });

  test('the chosen category is always among those offered', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: [
        for (final n in ['飲食', '交通', '居家', '娛樂', '醫療', '教育', '其他'])
          Category(n, 'other', 0xFF000000),
      ],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = RecurringForm(ledger);
    final usual = [for (final c in form.categoryChoices) c.name];
    expect(usual, hasLength(5));
    expect(usual, contains(form.category));

    // One not among the usual takes the first place; the last gives way.
    form.category = '其他';
    expect(
      [for (final c in form.categoryChoices) c.name],
      ['其他', ...usual.take(4)],
    );
  });

  test('the strip names only what differs from the defaults', () {
    final form = RecurringForm(book(), on: DateTime.utc(2026, 10, 5));
    expect(form.notes, ['10/5 起', '手動入帳']);
    form
      ..auto = true
      ..end = DateTime.utc(2027, 3, 5)
      ..active = false;
    expect(form.notes, ['10/5 起', '到期自動入帳', '到 3/5', '已暫停']);
  });

  group('CORR-2', () {
    test('R1: an item from before starts, saved unchanged, keeps no start '
        'and so its days', () {
      final ledger = book();
      const old = Recurring(
        id: 'old',
        name: '房租',
        amount: 9000,
        day: 25,
        account: 'bank',
        category: '居家',
      );
      ledger.recurringCommands.saveRecurring(old);
      expect(RecurringForm(ledger, old: old).save(), isTrue);
      final kept = ledger.recurring.all.single;
      expect((kept.start, kept.day), (null, 25));
      // Changing its rhythm gives it the start shown.
      final form = RecurringForm(ledger, old: kept)..step(1);
      expect(form.save(), isTrue);
      expect(ledger.recurring.all.single.start, DateTime.utc(2026, 10, 25));
    });

    test("F82: moving a new item's start moves its day until a day is "
        'chosen', () {
      final form = RecurringForm(book());
      form.start = DateTime.utc(2026, 10, 20);
      expect(form.day, 20);
      form.setDayOfMonth(10);
      // The 10th after the 20th: November 10.
      expect((form.day, form.start), (10, DateTime.utc(2026, 11, 10)));
      form.start = DateTime.utc(2026, 12, 1);
      expect(form.day, 10);
      expect(form.rhythm, '每月 10 日');
    });
  });
}
