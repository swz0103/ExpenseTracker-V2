import 'package:core/foundation_values.dart'
    show BusinessDate, Verified, WeekendsOnly;
import 'package:domain/credit_cards.dart' show BillDue;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/card_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day the card is looked at: the statement closing on 9/20 is the
/// last one closed, due on 10/5.
final _today = DateTime.utc(2026, 10, 4);

Entry _spend(
  String id,
  int day,
  int amount, {
  int month = 9,
  List<String> tags = const [],
  EntryType type = EntryType.expense,
  int installments = 1,
}) => Entry(
  id: id,
  date: DateTime.utc(2026, month, day),
  type: type,
  amount: amount,
  account: 'card',
  category: '購物休閒',
  tags: tags,
  installments: installments,
);

CardSummary _summary({
  List<Entry> entries = const [],
  int? limit = 50000,
  Map<DateTime, DateTime> closes = const {},
}) {
  final card = Account(
    'card',
    '日常卡',
    AccountKind.card,
    0,
    closingDay: 20,
    dueDay: 5,
    limit: limit,
    closes: closes,
  );
  final ledger = Ledger(
    today: _today,
    accounts: [const Account('bank', '銀行', AccountKind.bank, 100000), card],
    categories: const [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
  );
  return CardSummary.of(
    ledger.account('card'),
    statements: ledger.statementService,
    balances: ledger.balanceService,
    entries: ledger.entries,
    accounts: ledger.accounts,
    today: ledger.today,
  );
}

void main() {
  test('the last statement closed, what it owes and when it is due', () {
    final card = _summary(
      entries: [_spend('a', 10, 1200), _spend('b', 25, 300)],
    );
    expect(
      (card.start, card.end, card.due),
      (
        DateTime.utc(2026, 8, 21),
        DateTime.utc(2026, 9, 20),
        DateTime.utc(2026, 10, 5),
      ),
    );
    expect(card.owed, 1200);
    // Due 10/5, looked at 10/4: one day left.
    expect(card.billStatus, BillDue(BusinessDate(2026, 10, 5), 1));
    expect(card.unbilled.map((e) => e.id), ['b']);
    expect(card.spentSince, 300);
    expect((card.daysGone, card.cycleDays), (14, 30));
  });

  test('繳卡款 starts a transfer of what is owed, from the main account', () {
    final payment = _summary(entries: [_spend('a', 10, 1200)]).payment!;
    expect(
      (payment.type, payment.amount, payment.account, payment.to),
      (EntryType.transfer, 1200, 'bank', 'card'),
    );
    expect(payment.note, '日常卡繳款');
    expect(_summary().payment, isNull);
  });

  test('the credit left counts instalments still to be billed', () {
    final card = _summary(
      entries: [
        _spend('a', 10, 10000),
        _spend('tv', 1, 12000, month: 9, installments: 6),
      ],
    );
    // One of six billed on 9/20: 10,000 left of the 12,000.
    expect(card.plans.map((e) => e.id), ['tv']);
    expect(card.periodsBilled(card.plans.single), 1);
    expect(card.unbilledOf(card.plans.single), 10000);
    expect(card.pending, 10000);
    expect(card.debt, 12000);
    expect(card.available, 50000 - 12000 - 10000);
    expect(card.usedPercent, 44);
    expect(card.nearLimit, isFalse);
  });

  test('a period that carries the remainder shows what it bills', () {
    // 10,001 in three: 3,335 first, then 3,333 each. Once shown as
    // 3,333 a period whichever it was.
    final first = _summary(entries: [_spend('tv', 1, 10001, installments: 3)]);
    expect(first.periodsBilled(first.plans.single), 1);
    expect(first.periodAmount(first.plans.single), 3335);
    final second = _summary(
      entries: [_spend('tv', 1, 10001, month: 8, installments: 3)],
    );
    expect(second.periodsBilled(second.plans.single), 2);
    expect(second.periodAmount(second.plans.single), 3333);
  });

  test('without a limit nothing about it is shown', () {
    final card = _summary(limit: null);
    expect(
      (card.available, card.usedShare, card.usedPercent),
      (null, null, null),
    );
    expect(card.nearLimit, isFalse);
  });

  test('80% of the limit taken is near it', () {
    final card = _summary(entries: [_spend('a', 10, 40000)]);
    expect(card.usedPercent, 80);
    expect(card.nearLimit, isTrue);
  });

  test('a moved close is told with the day it was due', () {
    final moved = _summary(
      closes: {DateTime.utc(2026, 10, 20): DateTime.utc(2026, 10, 17)},
    );
    expect(moved.nextClose, DateTime.utc(2026, 10, 17));
    expect(moved.scheduledClose, DateTime.utc(2026, 10, 20));
    final plain = _summary();
    expect(plain.scheduledClose, plain.nextClose);
  });

  test('cashback and fees are summed by tag, this year and this cycle', () {
    final card = _summary(
      entries: [
        _spend('r1', 5, 100, month: 3, tags: ['回饋'], type: EntryType.income),
        _spend('r2', 25, 40, tags: ['回饋'], type: EntryType.income),
        _spend('fee', 1, 1800, month: 2, tags: ['年費']),
      ],
    );
    expect(card.taggedThisYear('回饋', EntryType.income), 140);
    expect(card.taggedSinceClose('回饋', EntryType.income), 40);
    expect(card.taggedThisYear('年費', EntryType.expense), 1800);
  });

  test('a cashback or fee starts on the card, tagged and named', () {
    final card = _summary();
    final reward = card.extra(EntryType.income);
    expect((reward.account, reward.note), ('card', '日常卡回饋'));
    expect(reward.tags, ['回饋']);
    final fee = card.extra(EntryType.expense);
    expect(fee.category, feeCategory);
    expect(fee.tags, ['年費']);
    expect(card.spending.account, 'card');
    expect((card.closingDay, card.dueDay), (20, 5));
  });

  test('a due day on a day off is paid by the next business day', () {
    // 2026-10-05 is a Monday: it stays.
    expect(payByOf(DateTime.utc(2026, 10, 5)).value, BusinessDate(2026, 10, 5));
    // Fri 2026-10-09 is a make-up holiday, then the weekend: Mon 10-12.
    final holiday = payByOf(DateTime.utc(2026, 10, 9));
    expect(holiday, isA<Verified<BusinessDate>>());
    expect(holiday.value, BusinessDate(2026, 10, 12));
    // Sat 2028-01-01: 2028 is not in the table, weekends only: Mon 01-03.
    final unknown = payByOf(DateTime.utc(2028, 1, 1));
    expect(unknown, isA<WeekendsOnly<BusinessDate>>());
    expect(unknown.value, BusinessDate(2028, 1, 3));
  });
}
