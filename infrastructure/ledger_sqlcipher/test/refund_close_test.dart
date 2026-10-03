import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:reports/reports.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.of('TWD');
final usd = Currency.of('USD');
final day = BusinessDate(2026, 10, 1);

Money ntd(int units) => Money(twd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late PublicId cash;
  late PublicId food;
  late PublicId fun;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  Account account(PublicId id) =>
      ledger.accounts(workspace).singleWhere((a) => a.id == id);

  AccountRef ref(PublicId id) => AccountRef(id, account(id).rulesVersion);

  Future<PublicId> open(
    String name,
    Currency currency, {
    AccountKind kind = AccountKind.bank,
    Money? opening,
  }) async {
    final id = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: id,
        name: name,
        kind: kind,
        currency: currency,
        openedOn: day,
        openingBalance: opening,
        openingPostingId: opening == null ? null : PublicId.generate(),
      ),
    );
    return id;
  }

  Future<PublicId> category(String name) async {
    final id = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(id, name, kind: CategoryKind.expense),
      ),
    );
    return id;
  }

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-refund-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    cash = await open('現金', twd, opening: ntd(10000));
    food = await category('餐飲');
    fun = await category('娛樂');
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<PublicId> expense(
    int units, {
    List<CategoryShare> shares = const [],
  }) async {
    final outcome = await books.recordCashFlow(
      RecordCashFlow(
        operation: op(),
        postingId: PublicId.generate(),
        flow: CashFlow.expense,
        account: ref(cash),
        date: day,
        amount: ntd(units),
        allocations: shares,
      ),
    );
    return outcome.value;
  }

  Future<PublicId> refund(
    PublicId original,
    int units, {
    List<CategoryShare> shares = const [],
    PublicId? into,
    Money? received,
  }) async {
    final outcome = await books.recordRefund(
      RecordRefund(
        operation: op(),
        postingId: PublicId.generate(),
        originalId: original,
        account: ref(into ?? cash),
        date: BusinessDate(2026, 10, 9),
        amount: ntd(units),
        received: received,
        allocations: shares,
      ),
    );
    return outcome.value;
  }

  test('refunds return money and reduce the original spending', () async {
    final dinner = await expense(
      1000,
      shares: [
        CategoryShare(food, 1, ntd(600)),
        CategoryShare(fun, 1, ntd(400)),
      ],
    );
    await refund(dinner, 300, shares: [CategoryShare(food, 1, ntd(300))]);
    expect(ledger.balance(account(cash)), ntd(10000 - 1000 + 300));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(700));
    final totals = ledger.categoryTotals(workspace, '2026-10');
    expect(totals[(food, 'TWD')]!.expense, ntd(300));
    expect(totals[(fun, 'TWD')]!.expense, ntd(400));

    await expectLater(
      refund(dinner, 800, shares: [CategoryShare(food, 1, ntd(800))]),
      fails(FailureKind.rejected, 'ledger.refundLimit'),
    );
    await expectLater(
      refund(dinner, 400, shares: [CategoryShare(food, 1, ntd(400))]),
      fails(FailureKind.rejected, 'ledger.refundLimit'),
    );
    await expectLater(
      refund(dinner, 100),
      fails(FailureKind.rejected, 'ledger.refundReference'),
    );
  });

  test('refunded expenses cannot be reversed, and the reverse', () async {
    final first = await expense(500);
    await refund(first, 100);
    await expectLater(
      books.reversePosting(
        ReversePosting(
          operation: op(),
          reversalId: PublicId.generate(),
          originalId: first,
          date: day,
        ),
      ),
      fails(FailureKind.rejected, 'posting.has-refunds'),
    );
    final second = await expense(200);
    await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: second,
        date: day,
      ),
    );
    await expectLater(
      refund(second, 50),
      fails(FailureKind.rejected, 'posting.already-reversed'),
    );
  });

  test('a refund can arrive in another currency', () async {
    final dollars = await open('美元', usd);
    final ticket = await expense(3200);
    await refund(
      ticket,
      3200,
      into: dollars,
      received: Money(usd, BigInt.from(100)),
    );
    expect(ledger.balance(account(dollars)), Money(usd, BigInt.from(100)));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(0));

    // The refund's TWD amounts belong to the TWD expense's account, not to
    // the dollar account the money reached (G6-18); so does its reversal.
    final refundFact = ledger
        .monthlyFacts(workspace, ReportMonth(2026, 10))
        .singleWhere((f) => f.kind == PostingKind.refund);
    expect(refundFact.accountId, cash);
    expect(refundFact.expense, ntd(-3200));
  });

  test('only an empty, settled account can be closed', () async {
    Future<void> close(PublicId id) => books.closeAccount(
      CloseAccount(
        operation: op(),
        accountId: id,
        expectedVersion: account(id).version,
        date: BusinessDate(2026, 10, 31),
        reason: '不再使用',
      ),
    );
    await expectLater(
      close(cash),
      fails(FailureKind.rejected, 'account.nonZeroBalance'),
    );
    final last = await expense(10000);
    await close(cash);
    expect(account(cash).state, AccountState.closed);
    await expectLater(
      expense(1),
      fails(FailureKind.rejected, 'account.unavailable'),
    );
    await expectLater(
      books.reversePosting(
        ReversePosting(
          operation: op(),
          reversalId: PublicId.generate(),
          originalId: last,
          date: BusinessDate(2026, 11, 1),
        ),
      ),
      fails(FailureKind.rejected, 'account.unavailable'),
    );

    final card = await open('信用卡', twd, kind: AccountKind.creditCard);
    await CardBook(books).authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: PublicId.generate(),
        cardId: card,
        authorizedOn: day,
        amount: ntd(99),
      ),
    );
    await expectLater(
      close(card),
      fails(FailureKind.rejected, 'account.unsettledItems'),
    );
  });

  test('a reversed refund gives its amount back to the limit', () async {
    final dinner = await expense(1000);
    final wrong = await refund(dinner, 900);
    await expectLater(
      refund(dinner, 200),
      fails(FailureKind.rejected, 'ledger.refundLimit'),
    );
    await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: wrong,
        date: BusinessDate(2026, 10, 10),
      ),
    );
    await refund(dinner, 200);
    expect(ledger.balance(account(cash)), ntd(10000 - 1000 + 200));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(800));
    final reversal = ledger
        .monthlyFacts(workspace, ReportMonth(2026, 10))
        .singleWhere((f) => f.kind == PostingKind.reversal);
    expect(reversal.accountId, cash);
    expect(reversal.expense, ntd(900));
  });

  test('replacing the opening balance reverses the old one', () async {
    Future<void> setOpening(int units) => books.setOpeningBalance(
      SetOpeningBalance(
        operation: op(),
        postingId: PublicId.generate(),
        reversalId: PublicId.generate(),
        accountId: cash,
        expectedVersion: account(cash).rulesVersion,
        amount: ntd(units),
      ),
    );
    await setOpening(12500);
    expect(ledger.balance(account(cash)), ntd(12500));
    await setOpening(-300);
    expect(ledger.balance(account(cash)), ntd(-300));
    expect(ledger.monthly(workspace, '2026-10'), isEmpty);
  });
}
