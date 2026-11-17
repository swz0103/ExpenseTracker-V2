import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing: only counts the batches it was handed.
final class _Batches implements LedgerDataSource {
  var kept = 0;

  @override
  Future<void> keep(WriteBatch batch) async => kept++;

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 4);

  Ledger book() => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
    categories: [Category('飲食', 'food', 0xFF5C9A83)],
    entries: [
      Entry(
        id: 'lunch',
        date: day,
        type: EntryType.expense,
        amount: 120,
        account: 'bank',
        category: '飲食',
        merchant: '便當店',
      ),
    ],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Batches(),
  );

  Entry spend(String id) => Entry(
    id: id,
    date: day,
    type: EntryType.expense,
    amount: 80,
    account: 'bank',
    category: '飲食',
    merchant: '飲料店',
  );

  test('a budget change keeps what rests on entries only', () async {
    final ledger = book();
    final merchants = ledger.entryQueryService.merchants;
    final entriesBefore = ledger.revisionOf(Topic.entries);
    ledger.budgetCommands.setBudget('飲食', 5000);
    expect(ledger.revisionOf(Topic.budgets), 1);
    expect(ledger.revisionOf(Topic.entries), entriesBefore);
    expect(identical(ledger.entryQueryService.merchants, merchants), isTrue);

    ledger.entryCommands.add(spend('tea'));
    expect(ledger.revisionOf(Topic.entries), entriesBefore + 1);
    expect(identical(ledger.entryQueryService.merchants, merchants), isFalse);
    expect(ledger.entryQueryService.merchants, containsAll(['便當店', '飲料店']));
    await ledger.settled;
  });

  test('a page watching some topics hears only of those', () async {
    final ledger = book();
    var budgets = 0;
    var market = 0;
    var all = 0;
    ledger.watch(const {Topic.budgets}).addListener(() => budgets++);
    ledger.watch(const {Topic.market}).addListener(() => market++);
    ledger.addListener(() => all++);

    ledger.budgetCommands.setBudget('飲食', 5000);
    expect((budgets, market, all), (1, 0, 1));

    ledger.entryCommands.add(spend('tea'));
    expect((budgets, market, all), (1, 0, 2));
    await ledger.settled;
  });

  test('hiding amounts is a change of display and leaves every sum', () async {
    final ledger = book();
    final merchants = ledger.entryQueryService.merchants;
    final revision = ledger.revision;
    var all = 0;
    var display = 0;
    var budgets = 0;
    ledger.addListener(() => all++);
    // A page watching budgets alone still hears of how amounts are shown.
    ledger.watch(const {Topic.budgets}).addListener(() => budgets++);
    ledger.watch(const <Topic>{}).addListener(() => display++);

    expect(ledger.amounts.hidden, isFalse);
    ledger.amounts.toggle();
    expect(ledger.amounts.hidden, isTrue);
    expect((all, display, budgets), (1, 1, 1));
    expect(ledger.revision, revision);
    expect(identical(ledger.entryQueryService.merchants, merchants), isTrue);

    ledger.amounts.toggle();
    expect(ledger.amounts.hidden, isFalse);
    expect(all, 2);
  });

  test('starting a book over shows amounts again, once', () {
    final ledger = book();
    ledger.amounts.toggle();
    var heard = 0;
    ledger.addListener(() => heard++);
    ledger.resetTo(book());
    expect(ledger.amounts.hidden, isFalse);
    // resetTo itself tells the screens once; showing again adds one more
    // change of display, never a lost one.
    expect(heard, greaterThanOrEqualTo(1));
    ledger.amounts.reset();
    final after = heard;
    ledger.amounts.reset();
    expect(heard, after);
  });
}
