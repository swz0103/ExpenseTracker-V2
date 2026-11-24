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
  EntryMark? mark,
}) => Entry(
  id: id,
  date: DateTime.utc(2026, month, day),
  type: type,
  amount: amount,
  account: 'card',
  category: '購物休閒',
  tags: tags,
  installments: installments,
  mark: mark,
);

CardSummary _summary({
  List<Entry> entries = const [],
  int? limit = 50000,
  Map<DateTime, DateTime> closes = const {},
  int closingDay = 20,
  DateTime? today,
}) {
  final card = Account(
    'card',
    '日常卡',
    AccountKind.card,
    0,
    closingDay: closingDay,
    dueDay: 5,
    limit: limit,
    closes: closes,
  );
  final ledger = Ledger(
    today: today ?? _today,
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

  group('R26: a cycle that starts on a close held to the month end', () {
    // Looked at 3 days after each close [end]; the cycle runs to the
    // next close, which falls on the closing day itself again.
    for (final (closingDay, end, next, days) in [
      // Closing 31: Feb 28 -> Mar 31 is 31 days (28 Feb + 31 = 31 Mar).
      (31, DateTime.utc(2026, 2, 28), DateTime.utc(2026, 3, 31), 31),
      // Leap year: Feb 29 -> Mar 31, 31 days.
      (31, DateTime.utc(2028, 2, 29), DateTime.utc(2028, 3, 31), 31),
      // Apr 30 -> May 31, Jun 30 -> Jul 31, Sep 30 -> Oct 31,
      // Nov 30 -> Dec 31: 31 days each.
      (31, DateTime.utc(2026, 4, 30), DateTime.utc(2026, 5, 31), 31),
      (31, DateTime.utc(2026, 6, 30), DateTime.utc(2026, 7, 31), 31),
      (31, DateTime.utc(2026, 9, 30), DateTime.utc(2026, 10, 31), 31),
      (31, DateTime.utc(2026, 11, 30), DateTime.utc(2026, 12, 31), 31),
      // Closing 30: Feb 28 -> Mar 30 is 30 days; Feb 29 -> Mar 30, 30.
      (30, DateTime.utc(2026, 2, 28), DateTime.utc(2026, 3, 30), 30),
      (30, DateTime.utc(2028, 2, 29), DateTime.utc(2028, 3, 30), 30),
      // Closing 29: Feb 28 -> Mar 29 is 29 days.
      (29, DateTime.utc(2026, 2, 28), DateTime.utc(2026, 3, 29), 29),
    ]) {
      test('closing day $closingDay, closed $end', () {
        final card = _summary(
          closingDay: closingDay,
          today: end.add(const Duration(days: 3)),
        );
        expect(card.end, end);
        expect(card.nextClose, next);
        expect((card.daysGone, card.cycleDays), (3, days));
      });
    }
  });

  test('R28: two closes moved apart make a 42-day cycle, not a 0-day one', () {
    // Closing 15: the February close moved 7 days earlier (8 Feb), the
    // March one 7 days later (22 Mar); 8 Feb -> 22 Mar is 28 + 14 = 42
    // days, 21 of them gone on 1 Mar.
    final card = _summary(
      closingDay: 15,
      closes: {
        DateTime.utc(2027, 2, 15): DateTime.utc(2027, 2, 8),
        DateTime.utc(2027, 3, 15): DateTime.utc(2027, 3, 22),
      },
      today: DateTime.utc(2027, 3, 1),
    );
    expect(card.end, DateTime.utc(2027, 2, 8));
    expect(card.nextClose, DateTime.utc(2027, 3, 22));
    expect(card.scheduledClose, DateTime.utc(2027, 3, 15));
    expect((card.daysGone, card.cycleDays), (21, 42));
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

  test('cashback and fees are summed by their mark, this year and this '
      'cycle', () {
    final card = _summary(
      entries: [
        _spend(
          'r1',
          5,
          100,
          month: 3,
          tags: ['回饋'],
          type: EntryType.income,
          mark: EntryMark.reward,
        ),
        _spend(
          'r2',
          25,
          40,
          tags: ['回饋'],
          type: EntryType.income,
          mark: EntryMark.reward,
        ),
        _spend(
          'fee',
          1,
          1800,
          month: 2,
          tags: ['年費'],
          mark: EntryMark.annualFee,
        ),
      ],
    );
    expect(card.markedThisYear(EntryMark.reward), 140);
    expect(card.markedSinceClose(EntryMark.reward), 40);
    expect(card.markedThisYear(EntryMark.annualFee), 1800);
  });

  test('a tag renamed changes no figure; a tag alone makes none (D52)', () {
    final card = _summary(
      entries: [
        _spend(
          'r1',
          25,
          40,
          tags: ['獎勵'],
          type: EntryType.income,
          mark: EntryMark.reward,
        ),
        _spend('r2', 26, 70, tags: ['回饋'], type: EntryType.income),
      ],
    );
    expect(card.markedThisYear(EntryMark.reward), 40);
    expect(card.markedSinceClose(EntryMark.reward), 40);
  });

  test('an annual fee given back is taken off the year\'s (r13 F7)', () {
    final fee = _spend(
      'fee',
      1,
      1800,
      month: 2,
      tags: ['年費'],
      mark: EntryMark.annualFee,
    );
    final waived = Entry(
      id: 'waived',
      date: DateTime.utc(2026, 3, 5),
      type: EntryType.income,
      amount: 1800,
      account: 'card',
      category: '購物休閒',
      refundOf: 'fee',
    );
    final card = _summary(entries: [fee, waived]);
    // 1800 charged, 1800 given back: 0.
    expect(card.markedThisYear(EntryMark.annualFee), 0);
    expect(card.markedThisYear(EntryMark.reward), 0);
  });

  test('the cashback and fee the page starts carry their mark', () {
    final card = _summary();
    expect(card.extra(EntryType.income).mark, EntryMark.reward);
    expect(card.extra(EntryType.expense).mark, EntryMark.annualFee);
  });

  test('a 預定 cashback, fee or purchase counts on its day only (D71)', () {
    // Looked at 10/4. 回饋 of 40 on 9/25 counts; 60 on 10/9 is 預定.
    // 年費 of 1,800 on 2/1 counts; 900 on 10/20 is 預定. A purchase of
    // 500 on 10/12 is 預定 too.
    final card = _summary(
      entries: [
        _spend(
          'r2',
          25,
          40,
          tags: ['回饋'],
          type: EntryType.income,
          mark: EntryMark.reward,
        ),
        _spend(
          'r3',
          9,
          60,
          month: 10,
          tags: ['回饋'],
          type: EntryType.income,
          mark: EntryMark.reward,
        ),
        _spend(
          'fee',
          1,
          1800,
          month: 2,
          tags: ['年費'],
          mark: EntryMark.annualFee,
        ),
        _spend(
          'fee2',
          20,
          900,
          month: 10,
          tags: ['年費'],
          mark: EntryMark.annualFee,
        ),
        _spend('later', 12, 500, month: 10),
      ],
    );
    expect(card.markedThisYear(EntryMark.reward), 40);
    expect(card.markedSinceClose(EntryMark.reward), 40);
    expect(card.markedThisYear(EntryMark.annualFee), 1800);
    expect(card.markedSinceClose(EntryMark.annualFee), 0);
    // Since the 9/20 close only the 9/25 cashback counts: −40 spent.
    expect(card.unbilled.map((e) => e.id), ['r2']);
    expect(card.spentSince, -40);
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

  group('credit taken from day to day (D67)', () {
    test('2,396 in 6 bought on the closing day: debt + still to bill is '
        '2,396 on every day, closing days included', () {
      var now = DateTime.utc(2026, 9, 5);
      final ledger = Ledger(
        today: now,
        clock: () => now,
        accounts: const [
          Account(
            'card',
            '卡',
            AccountKind.card,
            0,
            closingDay: 5,
            dueDay: 20,
            limit: 10000,
          ),
        ],
        categories: const [],
        entries: [
          Entry(
            id: 'a',
            date: DateTime.utc(2026, 9, 5),
            type: EntryType.expense,
            amount: 2396,
            account: 'card',
            category: '購物',
            installments: 6,
          ),
        ],
        holdings: const [],
        budgets: const [],
        recurring: const [],
      );
      final wrong = <String>[];
      for (
        var d = DateTime.utc(2026, 9, 5);
        !d.isAfter(DateTime.utc(2027, 4, 30));
        d = d.add(const Duration(days: 1))
      ) {
        now = d;
        final s = CardSummary.of(
          ledger.account('card'),
          statements: ledger.statementService,
          balances: ledger.balanceService,
          entries: ledger.entries,
          accounts: ledger.accounts,
          today: d,
        );
        if (s.debt + s.pending != 2396) {
          wrong.add('${d.month}/${d.day}: ${s.debt} + ${s.pending}');
        }
        // 2396 of 10000 is 24%; 10000 - 2396 = 7604 left.
        if (s.usedPercent != 24 || s.available != 7604) {
          wrong.add('${d.month}/${d.day}: ${s.usedPercent}% ${s.available}');
        }
      }
      expect(wrong, isEmpty);
    });
  });

  group('edges review 11 found untested', () {
    test('the share taken counts instalments and stops at the whole limit', () {
      final card = _summary(
        entries: [
          _spend('a', 10, 1000),
          _spend('tv', 1, 12000, installments: 6),
        ],
        limit: 10000,
      );
      // Owed 1,000 + 2,000 billed, 10,000 still to bill: 13,000 of
      // 10,000, shown as all of it.
      expect(card.usedShare, 1.0);
      final half = _summary(
        entries: [_spend('tv', 1, 12000, installments: 6)],
        limit: 24000,
      );
      // 2,000 billed + 10,000 to bill = 12,000 of 24,000.
      expect(half.usedShare, 0.5);
    });

    test('a limit of 0 is never near', () {
      expect(_summary(limit: 0).nearLimit, isFalse);
    });

    test('marked this year counts this month; since the close, not the '
        'close day', () {
      final card = _summary(
        entries: [
          // The close of 9/20 itself, then 10/2 of this month.
          _spend(
            'onClose',
            20,
            40,
            type: EntryType.income,
            mark: EntryMark.reward,
          ),
          _spend(
            'thisMonth',
            2,
            60,
            month: 10,
            type: EntryType.income,
            mark: EntryMark.reward,
          ),
        ],
      );
      expect(card.markedThisYear(EntryMark.reward), 100);
      expect(card.markedSinceClose(EntryMark.reward), 60);
    });

    test('one payment is billed once its statement closes', () {
      final card = _summary(entries: [_spend('a', 10, 1000)]);
      expect(card.unbilled, isEmpty);
      // Bought 9/10, billed by the close of 9/20.
      expect(card.periodsBilled(_spend('a', 10, 1000)), 1);
    });

    test('an instalment billed today is billed, not still to bill', () {
      // 3,000 in three from 9/1, looked at on the close of 9/20.
      final card = _summary(
        entries: [_spend('tv', 1, 3000, installments: 3)],
        today: DateTime.utc(2026, 9, 20),
      );
      expect(card.unbilledOf(card.plans.single), 2000);
    });
  });

  test('a card without billing days closes on the 1st, due on the 15th', () {
    final ledger = Ledger(
      today: _today,
      accounts: const [Account('card', '卡', AccountKind.card, 0)],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    // Closed 10/1 (10/4 today), opened 9/2, due 10/15.
    expect(ledger.statementService.statement(ledger.account('card')), (
      DateTime.utc(2026, 9, 2),
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 15),
    ));
  });
}
