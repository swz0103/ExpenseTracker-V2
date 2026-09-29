import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 26);
  PostingAccount account({Currency? currency, WorkspaceId? owner}) =>
      PostingAccount(
        id: PublicId.generate(),
        workspace: owner ?? workspace,
        currency: currency ?? usd,
        expectedVersion: 1,
      );
  OperationKey operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  Money money(String value) => Money.parse(usd, value);
  Posting opening(PostingAccount a, String amount) => Posting.opening(
    id: PublicId.generate(),
    operation: operation(),
    date: date,
    account: a,
    amount: money(amount),
  );
  Matcher error(LedgerError code) =>
      throwsA(isA<LedgerException>().having((e) => e.code, 'code', code));

  test('LED-01 opening plus income minus expense rebuilds 115', () {
    final a = account();
    final initial = opening(a, '100');
    final income = Posting.income(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      account: a,
      amount: money('20'),
    );
    final expense = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      account: a,
      amount: money('5'),
    );
    expect(rebuildBalance(a, [initial, income, expense]), money('115'));
    expect(initial.reportIncome, money('0'));
    expect(initial.reportExpense, money('0'));
    expect(income.reportIncome, money('20'));
    expect(expense.reportExpense, money('5'));
  });
  test('LED-02 transfer principal is not income or consumption', () {
    final a = account();
    final b = account();
    final transfer = Posting.transfer(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      source: a,
      destination: b,
      principal: money('25'),
    );
    final events = [opening(a, '100'), transfer];
    expect(rebuildBalance(a, events), money('75'));
    expect(rebuildBalance(b, events), money('25'));
    expect(transfer.reportIncome, money('0'));
    expect(transfer.reportExpense, money('0'));
  });
  test('LED-03 fee moves source cash once and alone counts as consumption', () {
    final a = account();
    final b = account();
    final transfer = Posting.transfer(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      source: a,
      destination: b,
      principal: money('25'),
      fee: money('1'),
    );
    final events = [opening(a, '100'), transfer];
    expect(rebuildBalance(a, events), money('74'));
    expect(rebuildBalance(b, events), money('25'));
    expect(transfer.reportExpense, money('1'));
    expect(transfer.legs.where((l) => l.role == LegRole.fee).length, 1);
  });
  test('investment buy debits cash once without income or consumption', () {
    final a = account();
    final buyId = PublicId.generate();
    final purchase = Posting.investmentBuy(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      account: a,
      investmentBuyId: buyId,
      gross: money('50'),
      fee: money('0.75'),
      tax: money('0.25'),
      cashDebit: money('51'),
    );
    expect(purchase.kind, PostingKind.investmentBuy);
    expect(purchase.legs, hasLength(1));
    expect(purchase.legs.single.account.id, a.id);
    expect(purchase.legs.single.role, LegRole.principal);
    expect(purchase.legs.single.amount, money('-51'));
    expect(purchase.reportIncome, money('0'));
    expect(purchase.reportExpense, money('0'));
    expect(purchase.allocations, isEmpty);
    expect(purchase.conversion, isNull);
    expect(purchase.investmentBuy?.buyId, buyId);
    expect(purchase.investmentBuy?.gross, money('50'));
    expect(purchase.investmentBuy?.fee, money('0.75'));
    expect(purchase.investmentBuy?.tax, money('0.25'));
    expect(purchase.investmentBuy?.cashDebit, money('51'));
    expect(rebuildBalance(a, [opening(a, '100'), purchase]), money('49'));
  });
  test('investment buy rejects wrong workspace, currency and buy identity', () {
    final a = account();
    final id = PublicId.generate();
    Posting purchase({
      PostingAccount? cashAccount,
      PublicId? buyId,
      Money? gross,
      Money? fee,
      Money? tax,
      Money? debit,
    }) => Posting.investmentBuy(
      id: id,
      operation: operation(),
      date: date,
      account: cashAccount ?? a,
      investmentBuyId: buyId ?? PublicId.generate(),
      gross: gross ?? money('50'),
      fee: fee ?? money('1'),
      tax: tax ?? money('0'),
      cashDebit: debit ?? money('51'),
    );
    expect(
      () => purchase(
        cashAccount: account(owner: WorkspaceId(PublicId.generate())),
      ),
      error(LedgerError.workspaceMismatch),
    );
    expect(
      () => purchase(fee: Money.parse(Currency('EUR', 2), '1')),
      error(LedgerError.currencyMismatch),
    );
    expect(() => purchase(buyId: id), error(LedgerError.duplicateIdentity));
  });
  test('investment buy rejects invalid components and inconsistent debit', () {
    final a = account();
    Posting purchase({Money? gross, Money? fee, Money? tax, Money? debit}) =>
        Posting.investmentBuy(
          id: PublicId.generate(),
          operation: operation(),
          date: date,
          account: a,
          investmentBuyId: PublicId.generate(),
          gross: gross ?? money('50'),
          fee: fee ?? money('1'),
          tax: tax ?? money('0'),
          cashDebit: debit ?? money('51'),
        );
    expect(() => purchase(gross: money('0')), error(LedgerError.invalidAmount));
    expect(() => purchase(fee: money('-1')), error(LedgerError.invalidAmount));
    expect(() => purchase(tax: money('-1')), error(LedgerError.invalidAmount));
    expect(() => purchase(debit: money('0')), error(LedgerError.invalidAmount));
    expect(
      () => purchase(debit: money('50.99')),
      error(LedgerError.investmentBuyMismatch),
    );
    expect(
      () => purchase(
        gross: Money(usd, Money.maxMinorUnits),
        fee: money('0.01'),
        debit: Money(usd, Money.maxMinorUnits),
      ),
      error(LedgerError.investmentBuyMismatch),
    );
  });
  test('LED-05 split allocation is not another cash movement', () {
    final a = account();
    final allocations = [
      Allocation(PublicId.generate(), money('6')),
      Allocation(PublicId.generate(), money('4')),
    ];
    final expense = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: date,
      account: a,
      amount: money('10'),
      allocations: allocations,
    );
    allocations.clear();
    expect(expense.allocations.length, 2);
    expect(rebuildBalance(a, [expense]), money('-10'));
    expect(() => expense.legs.clear(), throwsUnsupportedError);
    expect(
      () => Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: date,
        account: a,
        amount: money('10'),
        allocations: [
          Allocation(PublicId.generate(), money('6')),
          Allocation(PublicId.generate(), money('5')),
        ],
      ),
      error(LedgerError.allocationMismatch),
    );
  });
  test('reject foreign workspace, same account and unsupported currency conversion', () {
    final a = account();
    expect(
      () => opening(account(owner: WorkspaceId(PublicId.generate())), '1'),
      error(LedgerError.workspaceMismatch),
    );
    expect(
      () => Posting.transfer(
        id: PublicId.generate(),
        operation: operation(),
        date: date,
        source: a,
        destination: a,
        principal: money('1'),
      ),
      error(LedgerError.sameAccount),
    );
    expect(
      () => Posting.transfer(
        id: PublicId.generate(),
        operation: operation(),
        date: date,
        source: a,
        destination: account(currency: Currency('EUR', 2)),
        principal: money('1'),
      ),
      error(LedgerError.currencyMismatch),
    );
  });
  test(
    'negative opening allowed; income expense and fee signs are constrained',
    () {
      final a = account();
      expect(rebuildBalance(a, [opening(a, '-3')]), money('-3'));
      for (final value in ['0', '-1']) {
        expect(
          () => Posting.income(
            id: PublicId.generate(),
            operation: operation(),
            date: date,
            account: a,
            amount: money(value),
          ),
          error(LedgerError.invalidAmount),
        );
        expect(
          () => Posting.expense(
            id: PublicId.generate(),
            operation: operation(),
            date: date,
            account: a,
            amount: money(value),
          ),
          error(LedgerError.invalidAmount),
        );
      }
      expect(
        () => Posting.transfer(
          id: PublicId.generate(),
          operation: operation(),
          date: date,
          source: a,
          destination: account(),
          principal: money('1'),
          fee: money('-1'),
        ),
        error(LedgerError.invalidAmount),
      );
    },
  );
  test(
    'balance reconstruction rejects duplicate identity and foreign workspace',
    () {
      final a = account();
      final event = opening(a, '1');
      expect(
        () => rebuildBalance(a, [event, event]),
        error(LedgerError.duplicateIdentity),
      );
      expect(
        () => rebuildBalance(account(owner: WorkspaceId(PublicId.generate())), [
          event,
        ]),
        error(LedgerError.workspaceMismatch),
      );
    },
  );
  test(
    'rebuild uses wide intermediate total and checks final persisted bound',
    () {
      final a = account();
      final max = Posting.opening(
        id: PublicId.generate(),
        operation: operation(),
        date: date,
        account: a,
        amount: Money(usd, Money.maxMinorUnits),
      );
      final positive = opening(a, '0.01');
      final negative = opening(a, '-0.01');
      expect(
        rebuildBalance(a, [max, positive, negative]),
        Money(usd, Money.maxMinorUnits),
      );
      expect(
        () => rebuildBalance(a, [max, positive]),
        throwsA(isA<MoneyException>()),
      );
    },
  );
}
