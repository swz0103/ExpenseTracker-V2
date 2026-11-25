import 'package:ledger_entries/model.dart';
import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 10, 4);

const _bank = AccountFacts(AccountKind.bank);
const _cash = AccountFacts(AccountKind.cash);
const _card = AccountFacts(AccountKind.card);
const _usd = AccountFacts(AccountKind.bank, currency: 'USD');

Entry _entry({
  String id = 'e',
  DateTime? date,
  EntryType type = EntryType.expense,
  int amount = 100,
  String account = 'bank',
  String? to,
  String? holding,
  int shares = 0,
  int fee = 0,
  int tax = 0,
  int installments = 0,
  int? home,
  int? received,
  String? refundOf,
  List<(String, int)> parts = const [],
}) => Entry(
  id: id,
  date: date ?? _day,
  type: type,
  amount: amount,
  account: account,
  to: to,
  holding: holding,
  shares: shares,
  fee: fee,
  tax: tax,
  installments: installments,
  home: home,
  received: received,
  refundOf: refundOf,
  parts: parts,
);

/// The issues of [e] by their type, in the order found.
List<Type> _issues(
  Entry e, [
  EntryFacts facts = const EntryFacts(account: _bank),
]) => [for (final i in entryIssues(e, facts)) i.runtimeType];

void main() {
  test('a plain spending has nothing to say', () {
    expect(_issues(_entry()), isEmpty);
  });

  group('amount', () {
    test('nothing is refused', () {
      expect(_issues(_entry(amount: 0)), [MissingAmount]);
    });
    test('a trade of nothing asks for shares and price', () {
      final issue = entryIssues(
        _entry(type: EntryType.buy, amount: 0, holding: '2330', shares: 1),
        const EntryFacts(account: _bank),
      ).single;
      expect(issue, isA<MissingAmount>().having((m) => m.trade, 'trade', true));
    });
    test('a stock dividend needs no amount', () {
      expect(
        _issues(
          _entry(
            type: EntryType.dividend,
            amount: 0,
            holding: '2330',
            shares: 5,
          ),
        ),
        isEmpty,
      );
    });
    test('NT\$999,999,999 is kept, one more is refused', () {
      expect(_issues(_entry(amount: 999999999)), isEmpty);
      final issue = entryIssues(
        _entry(amount: 1000000000),
        const EntryFacts(account: _bank),
      ).single;
      expect(
        issue,
        isA<AmountTooLarge>().having((a) => a.max, 'max', 999999999),
      );
    });
    test('the most of a US\$ account is counted in cents', () {
      // (999,999,999 + 1) dollars × 100 cents − 1: up to US$999,999,999.99.
      expect(maxAmountOf('USD'), 99999999999);
      expect(maxAmountOf('JPY'), 999999999);
      expect(
        _issues(
          _entry(amount: 99999999999, account: 'usd', home: 1),
          const EntryFacts(account: _usd),
        ),
        isEmpty,
      );
    });
    test('a fee or tax below nothing is refused', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'cash', fee: -1),
          const EntryFacts(account: _bank, to: _cash),
        ),
        [NegativeCharge],
      );
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'cash', fee: 15),
          const EntryFacts(account: _bank, to: _cash),
        ),
        isEmpty,
      );
    });
  });

  group('date', () {
    test('a UTC midnight is kept', () {
      expect(_issues(_entry(date: DateTime.utc(2026, 10, 4))), isEmpty);
    });
    test('a local day or a time of day is refused', () {
      expect(_issues(_entry(date: DateTime(2026, 10, 4))), [DateNotMidnight]);
      expect(_issues(_entry(date: DateTime.utc(2026, 10, 4, 8))), [
        DateNotMidnight,
      ]);
    });
  });

  group('accounts', () {
    test('an account the book does not have is refused', () {
      expect(
        _issues(_entry(account: 'gone'), const EntryFacts(account: null)),
        [UnknownAccount],
      );
    });
    test('a transfer needs a receiving account the book has', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer),
          const EntryFacts(account: _bank),
        ),
        [MissingDestination],
      );
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'gone'),
          const EntryFacts(account: _bank),
        ),
        [MissingDestination],
      );
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'cash'),
          const EntryFacts(account: _bank, to: _cash),
        ),
        isEmpty,
      );
    });
    test('a transfer to the same account is refused', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'bank'),
          const EntryFacts(account: _bank, to: _bank),
        ),
        [SameAccountTransfer],
      );
    });
  });

  group('currencies', () {
    test('foreign spending needs its worth in NT\$', () {
      const usd = EntryFacts(account: _usd);
      expect(_issues(_entry(account: 'usd'), usd), [MissingHomeAmount]);
      expect(_issues(_entry(account: 'usd', home: 32), usd), isEmpty);
    });
    test('a transfer between currencies needs the amount received', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'usd'),
          const EntryFacts(account: _bank, to: _usd),
        ),
        [MissingReceivedAmount],
      );
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'usd', received: 3),
          const EntryFacts(account: _bank, to: _usd),
        ),
        isEmpty,
      );
    });
    test('a foreign transfer takes no fee', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, account: 'usd', to: 'u2', fee: 1),
          const EntryFacts(account: _usd, to: _usd),
        ),
        [ForeignTransferFee],
      );
    });
    test('a foreign account pays no card', () {
      expect(
        _issues(
          _entry(
            type: EntryType.transfer,
            account: 'usd',
            to: 'card',
            received: 1,
          ),
          const EntryFacts(account: _usd, to: _card),
        ),
        [ForeignCardPayment],
      );
    });
  });

  group('cards', () {
    test('a card sends no money out', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, account: 'card', to: 'bank'),
          const EntryFacts(account: _card, to: _bank),
        ),
        [CardTransferOut],
      );
    });
    test('a card payment takes no fee', () {
      expect(
        _issues(
          _entry(type: EntryType.transfer, to: 'card', fee: 15),
          const EntryFacts(account: _bank, to: _card),
        ),
        [CardPaymentFee],
      );
    });
    test('instalments only on card spending', () {
      expect(
        _issues(_entry(installments: 3), const EntryFacts(account: _card)),
        isEmpty,
      );
      expect(_issues(_entry(installments: 3)), [InstallmentsOffCard]);
      expect(
        _issues(
          _entry(type: EntryType.income, installments: 3),
          const EntryFacts(account: _card),
        ),
        [InstallmentsOffCard],
      );
    });
    test('instalments from none to 60', () {
      const card = EntryFacts(account: _card);
      expect(_issues(_entry(installments: 60), card), isEmpty);
      expect(_issues(_entry(installments: 61), card), [InstallmentsOutOfRange]);
      expect(_issues(_entry(installments: -1), card), [InstallmentsOutOfRange]);
    });
  });

  group('splits', () {
    test('parts that add up to the amount are kept', () {
      // 60 + 40 = 100.
      expect(_issues(_entry(parts: [('食', 60), ('衣', 40)])), isEmpty);
    });
    test('parts short of the amount are refused, with the difference', () {
      // 500 − (200 + 100) = 200.
      final issue = entryIssues(
        _entry(amount: 500, parts: [('食', 200), ('衣', 100)]),
        const EntryFacts(account: _bank),
      ).single;
      expect(
        issue,
        isA<SplitTotalMismatch>().having(
          (s) => s.difference,
          'difference',
          200,
        ),
      );
    });
    test('a part of nothing is refused (F56)', () {
      // 100 + 0 = 100: adds up, but a part is empty.
      expect(_issues(_entry(parts: [('食', 100), ('衣', 0)])), [
        SplitPartNotPositive,
      ]);
    });
  });

  group('investments', () {
    test('a trade from a card or loan is refused', () {
      expect(
        _issues(
          _entry(
            type: EntryType.buy,
            account: 'card',
            holding: '2330',
            shares: 1,
          ),
          const EntryFacts(account: _card),
        ),
        [InvestmentFromDebt],
      );
    });
    test('a foreign trade is refused', () {
      expect(
        _issues(
          _entry(
            type: EntryType.buy,
            account: 'usd',
            holding: 'AAPL',
            shares: 1,
          ),
          const EntryFacts(account: _usd),
        ),
        [ForeignInvestment],
      );
    });
    test('a trade needs a stock and shares', () {
      expect(_issues(_entry(type: EntryType.buy, shares: 1)), [MissingHolding]);
      expect(_issues(_entry(type: EntryType.buy, holding: '2330')), [
        MissingShares,
      ]);
    });
    test('a fee beyond what any currency keeps is refused (R12 F3)', () {
      // 99,999,999,999 is the most in any currency (US cents).
      expect(_issues(_entry(fee: 100000000000)), [AmountTooLarge]);
    });
    test('more than 999,999,999 shares is refused (R12 F3)', () {
      // maxShares is core's maxAmountUnits, 999,999,999.
      expect(
        _issues(
          _entry(type: EntryType.buy, holding: '2330', shares: 999999999),
        ),
        isEmpty,
      );
      expect(
        _issues(
          _entry(type: EntryType.buy, holding: '2330', shares: 1000000000),
        ),
        [SharesTooLarge],
      );
    });
    test('a premium larger than the dividend is refused', () {
      expect(
        _issues(
          _entry(
            type: EntryType.dividend,
            holding: '2330',
            amount: 100,
            tax: 101,
          ),
        ),
        [TaxExceedsDividend],
      );
    });
    test('a reduction of more than is held is refused, saying how many', () {
      final issues = entryIssues(
        _entry(type: EntryType.dividend, holding: '2330', shares: -11),
        const EntryFacts(account: _bank, heldBefore: 10),
      );
      expect(
        issues.single,
        isA<ReductionExceedsHolding>().having((r) => r.held, 'held', 10),
      );
      expect(
        _issues(
          _entry(type: EntryType.dividend, holding: '2330', shares: -10),
          const EntryFacts(account: _bank, heldBefore: 10),
        ),
        isEmpty,
      );
    });
    test('a reduction is not checked against shares not looked up', () {
      expect(
        _issues(_entry(type: EntryType.dividend, holding: '2330', shares: -11)),
        isEmpty,
      );
    });
    test('a sale leaving a trade short of shares is refused', () {
      final sale = _entry(type: EntryType.sell, holding: '2330', shares: 1);
      expect(_issues(sale, const EntryFacts(account: _bank, oversells: true)), [
        SaleExceedsHolding,
      ]);
      expect(_issues(sale), isEmpty);
    });
    test('D12: the rules name the sale itself short, not a later one', () {
      final sale = _entry(type: EntryType.sell, holding: '2330', shares: 1);
      final found = entryIssues(
        sale,
        const EntryFacts(account: _bank, oversells: true),
      ).whereType<SaleExceedsHolding>().single;
      expect(found.later, false);
      expect(const SaleExceedsHolding(later: true).later, true);
    });
  });

  group('D6: a day trade', () {
    Entry trade(EntryType type) => Entry(
      id: 't',
      date: _day,
      type: type,
      amount: 100000,
      account: 'bank',
      holding: '2330',
      shares: 1000,
      dayTrade: true,
    );
    test('a sale may be one', () {
      expect(_issues(trade(EntryType.sell)), isEmpty);
    });
    test('nothing else may', () {
      expect(_issues(trade(EntryType.buy)), [DayTradeNotSale]);
      expect(
        _issues(
          Entry(
            id: 'd',
            date: _day,
            type: EntryType.expense,
            amount: 1,
            account: 'bank',
            dayTrade: true,
          ),
        ),
        [DayTradeNotSale],
      );
    });
    test('kept through a change of group or labels', () {
      final sale = trade(EntryType.sell);
      expect(sale.inGroup('g').dayTrade, isTrue);
      expect(sale.withLabels(tags: const ['x']).dayTrade, isTrue);
    });
  });

  group('refunds', () {
    test('a refund of card spending goes back to the card', () {
      expect(
        _issues(
          _entry(type: EntryType.income, refundOf: 'x'),
          const EntryFacts(
            account: _bank,
            refunded: RefundFacts(
              account: 'card',
              kind: AccountKind.card,
              left: 500,
            ),
          ),
        ),
        [RefundToOtherAccount],
      );
    });
    test('a refund goes back in the currency of its spending (r37 1)', () {
      // A US\$ refund of NT\$ bank spending: refused before its amount is
      // weighed against what is left, which is in another currency.
      expect(
        _issues(
          _entry(type: EntryType.income, amount: 500, refundOf: 'x', home: 150),
          const EntryFacts(
            account: _usd,
            refunded: RefundFacts(
              account: 'bank',
              kind: AccountKind.bank,
              left: 1000,
            ),
          ),
        ),
        [RefundOtherCurrency],
      );
      // A NT\$ refund of US\$ card spending says the currency, once.
      expect(
        _issues(
          _entry(type: EntryType.income, amount: 500, refundOf: 'x'),
          const EntryFacts(
            account: _bank,
            refunded: RefundFacts(
              account: 'card',
              kind: AccountKind.card,
              currency: 'USD',
              left: 1000,
            ),
          ),
        ),
        [RefundOtherCurrency],
      );
    });
    test('a refund of non-card spending may go to another account of its '
        'currency, as the composer offers', () {
      expect(
        _issues(
          _entry(type: EntryType.income, amount: 500, refundOf: 'x'),
          const EntryFacts(
            account: _cash,
            refunded: RefundFacts(
              account: 'bank',
              kind: AccountKind.bank,
              left: 1000,
            ),
          ),
        ),
        isEmpty,
      );
    });
    test('a refund of more than is left is refused, saying what is left', () {
      final issue = entryIssues(
        _entry(type: EntryType.income, amount: 600, refundOf: 'x'),
        const EntryFacts(
          account: _bank,
          refunded: RefundFacts(
            account: 'bank',
            kind: AccountKind.bank,
            left: 500,
          ),
        ),
      ).single;
      expect(
        issue,
        isA<RefundExceedsRemaining>().having((r) => r.left, 'left', 500),
      );
    });
    test('the refund being changed counts its own amount as left', () {
      // 500 left + 100 it gave already = 600.
      expect(
        _issues(
          _entry(type: EntryType.income, amount: 600, refundOf: 'x'),
          const EntryFacts(
            account: _bank,
            refunded: RefundFacts(
              account: 'bank',
              kind: AccountKind.bank,
              left: 500,
              own: 100,
            ),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('the balance after buying shares (F24)', () {
    final buy = _entry(type: EntryType.buy, holding: '2330', shares: 1);
    test('below nothing is a warning, not an error', () {
      final issue = entryIssues(
        buy,
        const EntryFacts(account: _cash, balanceAfter: -85172),
      ).single;
      expect(
        issue,
        isA<NegativeBalanceAfter>().having((n) => n.after, 'after', -85172),
      );
      expect(issue.severity, Severity.warning);
      expect(issue.isError, isFalse);
    });
    test('nothing left is no warning', () {
      expect(
        _issues(buy, const EntryFacts(account: _cash, balanceAfter: 0)),
        isEmpty,
      );
    });
    test('spending is not warned about', () {
      expect(
        _issues(_entry(), const EntryFacts(account: _cash, balanceAfter: -1)),
        isEmpty,
      );
    });
  });

  group('a record read back', () {
    test('a sound one has nothing wrong with it', () {
      expect(entryShapeIssues(_entry()), isEmpty);
    });
    test('an amount of nothing still reads: older books kept some', () {
      expect(entryShapeIssues(_entry(amount: 0)), isEmpty);
    });
    test('the most in any currency reads; one more does not (R12 F3)', () {
      // US$ has 2 decimals: (999,999,999 + 1) * 100 - 1 = 99,999,999,999.
      expect(maxAmountAnyCurrency, 99999999999);
      expect(entryShapeIssues(_entry(amount: 99999999999)), isEmpty);
      for (final huge in [
        _entry(amount: 100000000000),
        _entry(fee: 9223372036854775807),
        _entry(tax: 100000000000),
        _entry(home: 100000000000),
        _entry(received: 100000000000),
        _entry(amount: 50, parts: const [('a', 100000000000)]),
      ]) {
        expect([
          for (final i in entryShapeIssues(huge)) i.runtimeType,
        ], contains(AmountTooLarge));
      }
    });
    test('a trade of fewer than no shares is refused (R12 F2)', () {
      for (final type in [EntryType.buy, EntryType.sell]) {
        expect(
          [
            for (final i in entryShapeIssues(
              _entry(type: type, holding: '2330', shares: -5),
            ))
              i.runtimeType,
          ],
          [MissingShares],
        );
      }
      // A reduction takes shares away: fewer than none is its shape.
      expect(
        entryShapeIssues(
          _entry(type: EntryType.dividend, holding: '2330', shares: -5),
        ),
        isEmpty,
      );
      // A sale of none still reads: an older book may keep one.
      expect(
        entryShapeIssues(_entry(type: EntryType.sell, holding: '2330')),
        isEmpty,
      );
    });
    test('more shares than kept are refused (R12 F3)', () {
      expect(
        [
          for (final i in entryShapeIssues(
            _entry(
              type: EntryType.buy,
              holding: '2330',
              shares: 9223372036854775807,
            ),
          ))
            i.runtimeType,
        ],
        [SharesTooLarge],
      );
    });
    test(
      'a negative amount, a transfer to nowhere and the rest are refused',
      () {
        expect(
          [
            for (final i in entryShapeIssues(
              _entry(
                type: EntryType.transfer,
                amount: -1,
                fee: -1,
                installments: 99,
                date: DateTime.utc(2026, 1, 1, 1),
              ),
            ))
              i.runtimeType,
          ],
          [
            DateNotMidnight,
            MissingAmount,
            NegativeCharge,
            MissingDestination,
            InstallmentsOutOfRange,
          ],
        );
      },
    );
  });

  group('edges review 11 found untested', () {
    List<Type> shape(Entry e) => [
      for (final i in entryShapeIssues(e)) i.runtimeType,
    ];

    test('a negative tax is a negative charge, written or read back', () {
      expect(_issues(_entry(tax: -1)), [NegativeCharge]);
      expect(shape(_entry(tax: -1)), [NegativeCharge]);
    });

    test('a date a millisecond or a microsecond past midnight is refused', () {
      for (final date in [
        DateTime.utc(2026, 10, 4, 0, 0, 0, 1),
        DateTime.utc(2026, 10, 4, 0, 0, 0, 0, 1),
      ]) {
        expect(_issues(_entry(date: date)), [DateNotMidnight]);
      }
    });

    test('instalments read back: 0 to 60 hold, -1 and 61 do not', () {
      expect(shape(_entry(installments: 60)), isEmpty);
      expect(shape(_entry(installments: 61)), [InstallmentsOutOfRange]);
      expect(shape(_entry(installments: -1)), [InstallmentsOutOfRange]);
    });

    test('one instalment is a plain payment, off a card too', () {
      expect(_issues(_entry(installments: 1)), isEmpty);
    });

    test('only a reduction is held against the shares held', () {
      // A purchase of fewer than no shares is missing its shares, not a
      // reduction past the 10 held.
      expect(
        _issues(
          _entry(type: EntryType.buy, holding: '2330', shares: -11),
          const EntryFacts(account: _bank, heldBefore: 10),
        ),
        [MissingShares],
      );
    });

    test('a reduction leaving a later trade short is refused', () {
      expect(
        _issues(
          _entry(type: EntryType.dividend, holding: '2330', shares: -1),
          const EntryFacts(account: _bank, oversells: true),
        ),
        [SaleExceedsHolding],
      );
    });
  });
}
