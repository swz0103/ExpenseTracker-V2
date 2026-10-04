import 'package:accounts/accounts.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final twd = Currency.of('TWD');
  final usd = Currency.of('USD');
  final date = BusinessDate(2026, 10, 3);
  OperationKey key() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  PostingAccount account(Currency currency, [int version = 1]) =>
      PostingAccount(
        id: PublicId.generate(),
        workspace: workspace,
        currency: currency,
        expectedVersion: version,
      );
  Money money(Currency currency, int units) =>
      Money(currency, BigInt.from(units));

  Posting roundTrip(Posting posting) =>
      PostingCodec.decode(PostingCodec.encode(posting));

  void expectSame(Posting a, Posting b) {
    expect(PostingCodec.encode(b), PostingCodec.encode(a));
    expect(b.legs.map((leg) => leg.amount), a.legs.map((leg) => leg.amount));
    expect(b.reportIncome, a.reportIncome);
    expect(b.reportExpense, a.reportExpense);
  }

  test('accounts round trip through restore', () {
    final opened = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: '  錢包 ',
      kind: AccountKind.cash,
      currency: twd,
      openedOn: date,
    );
    final archived = opened.archive(workspace: workspace, expectedVersion: 1);
    final decoded = AccountCodec.decode(AccountCodec.encode(archived));
    expect(AccountCodec.encode(decoded), AccountCodec.encode(archived));
    expect(decoded.name, '錢包');
    expect(decoded.state, AccountState.archived);
    expect(decoded.version, 2);
    for (final kind in AccountKind.values) {
      final account = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: kind.name,
        kind: kind,
        currency: twd,
        openedOn: date,
      );
      final json = AccountCodec.encode(account);
      expect(AccountCodec.decode(json).kind, kind);
    }
  });

  test('every supported posting kind round trips', () {
    final cash = account(twd, 3);
    final income = Posting.income(
      id: PublicId.generate(),
      operation: key(),
      date: date,
      account: cash,
      amount: money(twd, 50000),
    );
    final postings = [
      Posting.opening(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        account: cash,
        amount: money(twd, -1200),
      ),
      income,
      Posting.expense(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        account: cash,
        amount: money(twd, 15000),
        allocations: [
          Allocation(PublicId.generate(), money(twd, 10000)),
          Allocation(
            PublicId.generate(),
            money(twd, 5000),
            expectedCategoryVersion: 4,
          ),
        ],
      ),
      Posting.transfer(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        source: cash,
        destination: account(usd),
        principal: money(twd, 320000),
        received: money(usd, 10000),
        fee: money(twd, 1500),
      ),
      Posting.transfer(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        source: cash,
        destination: account(usd),
        principal: money(twd, 320000),
        received: money(usd, 10000),
        fee: money(usd, 50),
        allocations: [Allocation(PublicId.generate(), money(usd, 50))],
      ),
      Posting.reversal(
        id: PublicId.generate(),
        operation: key(),
        date: BusinessDate(2026, 10, 5),
        original: income,
        reason: '重複記錄',
      ),
      Posting.refund(
        id: PublicId.generate(),
        operation: key(),
        date: BusinessDate(2026, 10, 6),
        account: account(usd),
        originalId: PublicId.generate(),
        amount: money(twd, 3200),
        received: money(usd, 100),
      ),
      Posting.investmentBuy(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        account: cash,
        investmentBuyId: PublicId.generate(),
        gross: money(twd, 10000),
        fee: money(twd, 20),
        tax: money(twd, 0),
        cashDebit: money(twd, 10020),
      ),
      Posting.investmentSell(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        account: cash,
        investmentSellId: PublicId.generate(),
        gross: money(twd, 12000),
        fee: money(twd, 20),
        tax: money(twd, 36),
        cashCredit: money(twd, 11944),
      ),
      Posting.investmentDividend(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        account: cash,
        investmentDividendId: PublicId.generate(),
        gross: money(twd, 500),
        withholdingTax: money(twd, 50),
        fee: money(twd, 10),
        cashCredit: money(twd, 440),
      ),
    ];
    final kinds = {for (final posting in postings) posting.kind};
    expect(kinds, PostingKind.values.toSet());
    for (final posting in postings) {
      expectSame(posting, roundTrip(posting));
    }
  });

  test('stored postings are validated again on decode', () {
    final expense = Posting.expense(
      id: PublicId.generate(),
      operation: key(),
      date: date,
      account: account(twd),
      amount: money(twd, 100),
    );
    final json = PostingCodec.encode(expense);
    final cases = [
      {...json, 'amount': money(twd, -100).toJson()},
      {...json, 'extra': true},
      {...json, 'version': 2},
      {...json, 'kind': 'refund'},
      {...json, 'date': '2026-02-30'},
    ];
    for (final value in cases) {
      expect(() => PostingCodec.decode(value), throwsA(isA<CodecException>()));
    }
  });

  test('a reversal of a reversal cannot be stored', () {
    final income = Posting.income(
      id: PublicId.generate(),
      operation: key(),
      date: date,
      account: account(twd),
      amount: money(twd, 100),
    );
    final reversal = Posting.reversal(
      id: PublicId.generate(),
      operation: key(),
      date: date,
      original: income,
    );
    final json = PostingCodec.encode(reversal);
    final nested = {...json, 'original': json};
    expect(() => PostingCodec.decode(nested), throwsA(isA<CodecException>()));
  });
}
