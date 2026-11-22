// Dividends as the ledger books them: cash paid net of the premium, what
// counts as income, and what a dividend may not be.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Entry cash(
  String id,
  DateTime on,
  int amount,
  int tax, {
  String code = '2330',
}) => entryOf(
  id,
  on,
  EntryType.dividend,
  amount,
  'bank',
  holding: code,
  tax: tax,
);

Ledger held(List<Entry> more) => ledgerOf(
  today: day(2026, 12, 31),
  accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
  entries: [
    entryOf(
      'b1',
      day(2026, 1, 5),
      EntryType.buy,
      100000,
      'bank',
      holding: '2330',
      shares: 1000,
    ),
    entryOf(
      'b2',
      day(2026, 1, 5),
      EntryType.buy,
      50000,
      'bank',
      holding: '0050',
      shares: 1000,
    ),
    ...more,
  ],
);

void main() {
  group('cash dividends', () {
    test('the account receives the amount less the premium', () {
      final ledger = held([cash('d', day(2026, 8, 15), 25000, 528)]);
      // -100000 - 50000 (buys) + (25000 - 528) = -125528.
      expect(ledger.balanceService.balance('bank'), -125528);
    });
    test('a dividend under the threshold nets all of it', () {
      final ledger = held([cash('d', day(2026, 8, 15), 5000, 0)]);
      // -150000 + 5000 = -145000.
      expect(ledger.balanceService.balance('bank'), -145000);
      expect(ledger.reportService.income(2026, 8), 5000);
    });
    test('dividends of a stock add up in its holding', () {
      final ledger = held([
        cash('d1', day(2026, 7, 15), 25000, 528),
        cash('d2', day(2026, 10, 15), 5000, 0),
        cash('d3', day(2026, 10, 15), 800, 0, code: '0050'),
      ]);
      // 2330: (25000 - 528) + 5000 = 29472; 0050: 800.
      expect(ledger.holding('2330')!.dividends, 29472);
      expect(ledger.holding('0050')!.dividends, 800);
      expect(ledger.holdings.dividends, 30272);
    });
    test('income of a month counts dividends net, in their month', () {
      final ledger = held([
        cash('d1', day(2026, 7, 15), 25000, 528),
        cash('d2', day(2026, 10, 15), 5000, 0),
      ]);
      expect(ledger.reportService.income(2026, 7), 24472);
      expect(ledger.reportService.income(2026, 10), 5000);
      expect(ledger.reportService.income(2026, 8), 0);
    });
    test('totals between two days include dividends and no spending', () {
      final ledger = held([cash('d1', day(2026, 7, 15), 25000, 528)]);
      expect(
        ledger.reportService.totalsBetween(day(2026, 7, 1), day(2026, 7, 31)),
        (24472, 0),
      );
    });
    test('a dividend is not spending and is not in the spending total', () {
      final ledger = held([cash('d1', day(2026, 7, 15), 25000, 528)]);
      expect(ledger.reportService.expense(2026, 7), 0);
    });
  });

  group('what a dividend may not be', () {
    test('a premium larger than the dividend is refused', () {
      final ledger = held(const []);
      expect(
        ledger.entryValidator.validate(cash('d', day(2026, 8, 15), 1000, 1001)),
        isA<TaxExceedsDividend>(),
      );
      expect(
        ledger.entryValidator.validate(cash('d', day(2026, 8, 15), 1000, 1000)),
        isNull,
      );
    });
    test('a dividend with no stock chosen is refused', () {
      final ledger = held(const []);
      expect(
        ledger.entryValidator.validate(
          entryOf('d', day(2026, 8, 15), EntryType.dividend, 1000, 'bank'),
        ),
        isA<MissingHolding>(),
      );
    });
    test('a dividend of nothing and no shares is refused', () {
      final ledger = held(const []);
      expect(
        ledger.entryValidator.validate(cash('d', day(2026, 8, 15), 0, 0)),
        isA<MissingAmount>(),
      );
    });
    test('a dividend into a foreign account is refused', () {
      final ledger = ledgerOf(
        today: day(2026, 12, 31),
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
        ],
      );
      expect(
        ledger.entryValidator.validate(
          entryOf(
            'd',
            day(2026, 8, 15),
            EntryType.dividend,
            1000,
            'usd',
            holding: '2330',
          ),
        ),
        isA<ForeignInvestment>(),
      );
    });
    test('shares cannot be bought from a card', () {
      final ledger = ledgerOf(
        today: day(2026, 12, 31),
        accounts: const [Account('card', '信用卡', AccountKind.card, 0)],
      );
      expect(
        ledger.entryValidator.validate(
          entryOf(
            'b',
            day(2026, 8, 15),
            EntryType.buy,
            1000,
            'card',
            holding: '2330',
            shares: 10,
          ),
        ),
        isA<InvestmentFromDebt>(),
      );
    });
  });
}
